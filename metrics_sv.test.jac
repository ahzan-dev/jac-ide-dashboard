# Deterministic tests for the byLLM-adjacent plumbing in metrics_sv.jac.
# Annex: `jac test metrics_sv.jac` — sees the module's declarations without imports.
#
# NOTE ON MOCKING: the `by INSIGHT_LLM(...)` functions (_plan_query, _write_insight)
# CANNOT be mocked by reassigning INSIGHT_LLM to a MockLLM in a test — byLLM binds the
# model at definition time, so a reassigned glob is ignored and the real model runs.
# So the LLM PLANNER quality is covered by the real-LLM eval harness (eval/scenarios),
# NOT here. Here we lock down the pure/sync machinery the planner's output flows through
# (env injection, shaping, delta, tile routing) — deterministic, no API key, no network.

# ---------------------------------------------------------------------------
# env filter — the load-bearing "prod ≠ noise" guarantee
# ---------------------------------------------------------------------------
test "env_expr prod is super-property OR host allowlist" {
    e = env_expr("prod");
    assert "environment = 'prod'" in e;
    assert "jachammer.ai" in e;
    assert "jac-builder.jaseci.org" in e;
}
test "env_expr dev and preview differ from prod" {
    assert "'dev'" in env_expr("dev");
    assert "preview" in env_expr("preview");
    assert "jac-builder-pr-%" in env_expr("preview");
}
test "env_expr unknown/all is empty" {
    assert env_expr("all") == "";
    assert env_expr("") == "";
}
test "env_filter prepends AND to a non-empty expr, empty stays empty" {
    assert env_filter("prod").startswith("AND (");
    assert env_filter("all") == "";
}

# ---------------------------------------------------------------------------
# _prep_query_sql — read-only guard + non-negotiable env injection + LIMIT cap
# ---------------------------------------------------------------------------
test "prep replaces the {env} placeholder with the prod filter" {
    r = _prep_query_sql("SELECT count() FROM events WHERE {env} AND event='x'", "prod");
    assert r["ok"] == True;
    assert "{env}" not in r["sql"];
    assert "environment = 'prod'" in r["sql"];
}
test "prep injects env into the first WHERE when {env} is missing" {
    r = _prep_query_sql("SELECT count() FROM events WHERE event='x'", "prod");
    assert r["ok"] == True;
    assert "environment = 'prod'" in r["sql"];
    assert " AND event='x'" in r["sql"];
}
test "prep rejects a query with no WHERE to filter" {
    r = _prep_query_sql("SELECT count() FROM events", "prod");
    assert r["ok"] == False;
    assert "WHERE" in r["error"];
}
test "prep rejects non-SELECT (write) statements" {
    r = _prep_query_sql("DELETE FROM events WHERE {env}", "prod");
    assert r["ok"] == False;
}
test "prep rejects multiple statements" {
    r = _prep_query_sql("SELECT 1 WHERE {env}; DROP TABLE events", "prod");
    assert r["ok"] == False;
}
test "prep appends a LIMIT when none is present" {
    r = _prep_query_sql("SELECT person_id FROM events WHERE {env} GROUP BY person_id", "prod");
    assert "LIMIT 200" in r["sql"];
}
test "prep does not double-add LIMIT when the query already has one" {
    r = _prep_query_sql("SELECT person_id FROM events WHERE {env} LIMIT 10", "prod");
    assert r["sql"].lower().count("limit") == 1;
}
test "prep with env=all still runs (1=1) instead of dropping the filter silently" {
    r = _prep_query_sql("SELECT count() FROM events WHERE {env}", "all");
    assert r["ok"] == True;
    assert "1=1" in r["sql"];
}

# ---------------------------------------------------------------------------
# _pct_delta — comparison math, guards on zero / non-numeric
# ---------------------------------------------------------------------------
test "pct_delta computes signed percent change" {
    assert _pct_delta(15, 10) == 50.0;
    assert _pct_delta(5, 10) == -50.0;
    assert _pct_delta(10, 10) == 0.0;
}
test "pct_delta returns None when previous is zero" {
    assert _pct_delta(5, 0) is None;
}
test "pct_delta returns None for non-numeric input" {
    assert _pct_delta("abc", "def") is None;
}

# ---------------------------------------------------------------------------
# _col_index — used to read compare aggregates by alias, order-independent
# ---------------------------------------------------------------------------
test "col_index finds a column and reports -1 when absent" {
    cols = ["current_value", "previous_value"];
    assert _col_index(cols, "previous_value") == 1;
    assert _col_index(cols, "nope") == -1;
}

# ---------------------------------------------------------------------------
# _shape_ai_tile — how a raw HogQL result becomes tile data per chart type
# ---------------------------------------------------------------------------
test "shape stat pulls the single value and carries good_up into meta" {
    res = {"columns": ["c"], "results": [[42]]};
    d = _shape_ai_tile(res, "stat", "2026-06-01", "2026-07-01", "prod", "q", True);
    assert d["value"] == 42;
    assert d["meta"]["good_when_up"] == True;
}
test "shape compare reads by alias regardless of column order" {
    # previous listed FIRST — must still map current_value=10, previous_value=5
    res = {"columns": ["previous_value", "current_value"], "results": [[5, 10]]};
    d = _shape_ai_tile(res, "compare", "2026-06-01", "2026-07-01", "prod", "q", True);
    assert d["value"] == 10;
    assert d["prev"] == 5;
    assert d["delta"] == 100.0;
}
test "shape compare falls back to positional (col0=current, col1=previous)" {
    res = {"columns": ["today", "yesterday"], "results": [[9, 6]]};
    d = _shape_ai_tile(res, "compare", "2026-06-01", "2026-07-01", "prod", "q", True);
    assert d["value"] == 9;
    assert d["prev"] == 6;
    assert d["delta"] == 50.0;
}
test "shape compare honors good_up=False for lower-is-better metrics" {
    res = {"columns": ["current_value", "previous_value"], "results": [[8, 4]]};
    d = _shape_ai_tile(res, "compare", "2026-06-01", "2026-07-01", "prod", "q", False);
    assert d["meta"]["good_when_up"] == False;
    assert d["delta"] == 100.0;
}
test "shape table passes columns+rows through with no scalar value" {
    res = {"columns": ["person_id", "n"], "results": [["u1", 3], ["u2", 1]]};
    d = _shape_ai_tile(res, "table", "2026-06-01", "2026-07-01", "prod", "q", True);
    assert d["value"] is None;
    assert len(d["rows"]) == 2;
    assert d["columns"] == ["person_id", "n"];
}
test "shape line builds an {x,y} series from 2-col rows" {
    res = {"columns": ["d", "n"], "results": [["2026-06-01", 4], ["2026-06-02", 7]]};
    d = _shape_ai_tile(res, "line", "2026-06-01", "2026-07-01", "prod", "q", True);
    assert len(d["series"]) == 2;
    assert d["series"][0]["x"] == "2026-06-01";
    assert d["series"][1]["y"] == 7;
}
test "shape always carries the honest AI-written caveat" {
    res = {"columns": ["c"], "results": [[1]]};
    d = _shape_ai_tile(res, "stat", "2026-06-01", "2026-07-01", "prod", "q", True);
    assert "AI-written query" in d["meta"]["caveat"];
}

# ---------------------------------------------------------------------------
# _tile_for — deterministic chart choice from a metric's shape/unit (+overrides)
# ---------------------------------------------------------------------------
test "tile_for maps scalar unit to gauge(%)/stat and series to line/area" {
    assert _tile_for(Metric(key="a", title="A", definition="d", shape="scalar", unit="%")) == "gauge";
    assert _tile_for(Metric(key="b", title="B", definition="d", shape="scalar", unit="")) == "stat";
    assert _tile_for(Metric(key="c", title="C", definition="d", shape="series", unit="%")) == "line";
    assert _tile_for(Metric(key="d", title="D", definition="d", shape="series", unit="")) == "area";
    assert _tile_for(Metric(key="e", title="E", definition="d", shape="rows", unit="")) == "bars";
}
test "tile_for honors per-key overrides and native shapes" {
    assert _tile_for(Metric(key="signup_method", title="S", definition="d", shape="rows")) == "donut";
    assert _tile_for(Metric(key="feature_table", title="F", definition="d", shape="rows")) == "table";
    assert _tile_for(Metric(key="peak_hours", title="P", definition="d", shape="series")) == "vbar";
    assert _tile_for(Metric(key="funnel", title="Fn", definition="d", shape="funnel")) == "funnel";
    assert _tile_for(Metric(key="retention", title="R", definition="d", shape="retention")) == "retention";
    assert _tile_for(Metric(key="lifecycle", title="L", definition="d", shape="lifecycle")) == "stackbar";
}

# ---------------------------------------------------------------------------
# _catalog — the grounding the planner reads; must list every registry metric
# ---------------------------------------------------------------------------
test "catalog lists every registry metric key and shape" {
    cat = _catalog();
    for k in METRICS.keys() {
        assert str(k) in cat, f"catalog missing key {k}";
    }
    assert "[scalar]" in cat or "[series]" in cat;
}

# ---------------------------------------------------------------------------
# QueryPlan defaults — the planner's typed contract (what the client relies on)
# ---------------------------------------------------------------------------
test "QueryPlan defaults are safe (clarify-mode, good_up True, table chart)" {
    p = QueryPlan();
    assert p.mode == "clarify";
    assert p.good_up == True;
    assert p.chart == "table";
    assert p.keys == [];
    assert p.sql == "";
}
