"""Metric layer: server-side HogQL / native PostHog queries with env-filter + Redis cache.

Non-negotiables enforced HERE, once, for every tile:
  * POSTHOG_API_KEY (phx_, READ) is server-only; the browser calls `metric`, this module calls PostHog.
  * Every query injects the environment filter (default 'prod').
  * 'prod' matches `environment='prod'` OR a $host allowlist (prod does not yet emit the super-prop).
  * Every result carries an honest definition + window + caveat.

Response contract returned by `metric`:
  { value, series:[{x,y}], columns:[str], rows:[[...]], meta:{definition,window,caveat,env,unit,cached,good_when_up} }
Shapes: scalar (value + optional spark series) · series (line/bar) · rows (hbars/table/grouped)
        · funnel (rows=[[step,users]]) · retention (rows=[[cohort,base,w0,w1,...]]).
"""

import os;
import json;
import asyncio;
import requests;
import redis;
import from datetime { datetime, timedelta, timezone }
import from byllm.lib { Model }

glob PH_KEY: str = os.environ.get("POSTHOG_API_KEY", "");
glob PH_HOST: str = os.environ.get("POSTHOG_HOST", "https://us.posthog.com");
glob PH_PROJECT: str = os.environ.get("POSTHOG_PROJECT_ID", "425465");
glob REDIS_URL: str = os.environ.get("REDIS_URL", "redis://localhost:6379");
glob CACHE_TTL: int = 600;

# byLLM narrative (AI insights tile). Server-only key; degrades honestly if unset.
glob ANTH_KEY: str = os.environ.get("ANTHROPIC_API_KEY", "");
# Haiku accepts `temperature` (byLLM/litellm inject a default); Opus 4.7+ rejects it.
# Right-sized for a 3-4 sentence readout. Override with INSIGHTS_MODEL if desired.
glob ANTH_MODEL: str = os.environ.get("INSIGHTS_MODEL", "claude-haiku-4-5");
glob INSIGHT_LLM: Model = Model(model_name=ANTH_MODEL);

# ---------------------------------------------------------------------------
# Redis cache (degrades gracefully to no-cache if Redis is unreachable)
# ---------------------------------------------------------------------------

def _make_redis() -> any {
    try {
        r = redis.Redis.from_url(
            REDIS_URL, decode_responses=True, socket_connect_timeout=1, socket_timeout=1
        );
        r.ping();
        return r;
    } except Exception {
        return None;
    }
}

glob RDS: any = _make_redis();

def _cache_get(k: str) -> dict | None {
    if RDS is None {
        return None;
    }
    try {
        raw = RDS.get(k);
        if raw {
            d = json.loads(str(raw)) as dict;
            d["meta"]["cached"] = True;
            return d;
        }
    } except Exception {
        return None;
    }
    return None;
}

def _cache_put(k: str, val: dict) -> None {
    if RDS is None {
        return;
    }
    try {
        RDS.setex(k, CACHE_TTL, json.dumps(val));
    } except Exception {
        return;
    }
}

# ---------------------------------------------------------------------------
# Query runner (HogQL string OR native query kind)
# ---------------------------------------------------------------------------

def run_query(query_obj: dict) -> dict {
    if not PH_KEY {
        return {"error": "POSTHOG_API_KEY not set (server env)"};
    }
    url = f"{PH_HOST}/api/projects/{PH_PROJECT}/query/";
    try {
        resp = requests.post(
            url,
            headers={"Authorization": f"Bearer {PH_KEY}", "Content-Type": "application/json"},
            data=json.dumps({"query": query_obj}),
            timeout=20
        );
        if resp.status_code != 200 {
            return {"error": f"posthog http {resp.status_code}: {str(resp.text)[:160]}"};
        }
        d = resp.json();
        if d.get("error") {
            return {"error": str(d.get("error"))};
        }
        return {"columns": d.get("columns", []), "results": d.get("results", [])};
    } except Exception as e {
        return {"error": str(e)};
    }
}

def run_hogql(sql: str) -> dict {
    return run_query({"kind": "HogQLQuery", "query": sql});
}

# ---------------------------------------------------------------------------
# Environment filter (rule 1) — super-property OR $host allowlist
# ---------------------------------------------------------------------------

def env_expr(env: str) -> str {
    if env == "prod" {
        return "(properties.environment = 'prod' OR properties.$host IN ('jachammer.ai','www.jachammer.ai','jac-builder.jaseci.org'))";
    }
    if env == "dev" {
        return "(properties.environment = 'dev' OR properties.$host = 'jac-builder-dev.jaseci.org')";
    }
    if env == "preview" {
        return "(properties.environment = 'preview' OR properties.$host LIKE 'jac-builder-pr-%')";
    }
    return "";
}

def env_filter(env: str) -> str {
    e = env_expr(env);
    if e {
        return f"AND {e}";
    }
    return "";
}

# ---------------------------------------------------------------------------
# Metric registry — one entry per tile-backing metric
# ---------------------------------------------------------------------------

obj Metric {
    has key: str;
    has title: str;
    has definition: str;
    has shape: str = "scalar";        # scalar | series | rows | funnel | retention
    has sql: str = "";                # HogQL template ({env_filter}, {from}, {to})
    has spark: str = "";              # optional weekly series HogQL for a scalar's sparkline
    has unit: str = "";
    has window: str = "";             # fixed label; empty => use computed date-range label
    has caveat: str = "";
    has good_when_up: bool = True;
    has steps: list[str] = [];        # funnel step labels
    has readiness: str = "green";
}

# Common time predicate injected via {from} / {to} (alongside {env_filter} and the {bkt} bucket).
glob _RANGE: str = "AND timestamp >= toDateTime('{from}') AND timestamp < toDateTime('{to}')";

glob METRICS: dict[str, Metric] = {
    # ---- scalars / KPIs -------------------------------------------------
    "new_signups": Metric(
        key="new_signups", title="New signups", unit="",
        definition="How many people signed up for an account in the selected date range.",
        sql="SELECT count() FROM events WHERE event = 'auth_signup_succeeded' {env_filter} " + _RANGE,
        spark="SELECT {bkt}(timestamp) wk, count() n FROM events WHERE event='auth_signup_succeeded' {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk",
        caveat=""
    ),
    "signups_total": Metric(
        key="signups_total", title="Signups (last 6 months)", unit="", window="last 180 days",
        definition="Total number of new sign-ups over the last 6 months.",
        sql="SELECT count() FROM events WHERE event='auth_signup_succeeded' {env_filter} AND timestamp > now() - INTERVAL 180 DAY",
        spark="SELECT {bkt}(timestamp) wk, count() n FROM events WHERE event='auth_signup_succeeded' {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "active_builders": Metric(
        key="active_builders", title="Active builders", unit="",
        definition="Unique users who did something meaningful — sent an AI request, previewed a project, or created one — in this period. Just visiting doesn't count.",
        sql="SELECT count(DISTINCT person_id) FROM events WHERE event IN ('ai_message_sent','preview_ready','project_created') {env_filter} " + _RANGE,
        spark="SELECT {bkt}(timestamp) wk, count(DISTINCT person_id) n FROM events WHERE event IN ('ai_message_sent','preview_ready','project_created') {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "ai_requests": Metric(
        key="ai_requests", title="AI requests", unit="",
        definition="How many times users asked the AI to build or change something.",
        sql="SELECT count() FROM events WHERE event='ai_message_sent' {env_filter} " + _RANGE,
        spark="SELECT {bkt}(timestamp) wk, count() n FROM events WHERE event='ai_message_sent' {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "median_response": Metric(
        key="median_response", title="Typical response time", unit="s",
        definition="How long a typical AI request takes to finish, in seconds.",
        sql="SELECT round(median(toFloat64OrNull(toString(properties.duration_ms)))/1000,1) FROM events WHERE event='ai_message_completed' {env_filter} " + _RANGE,
        spark="SELECT {bkt}(timestamp) wk, round(median(toFloat64OrNull(toString(properties.duration_ms)))/1000,1) v FROM events WHERE event='ai_message_completed' {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk",
        good_when_up=False
    ),
    "code_produced": Metric(
        key="code_produced", title="Code produced", unit="files",
        definition="Total files the AI changed for users — our best available stand-in for how much work got done.",
        sql="SELECT round(sum(toFloat64OrNull(toString(properties.files_changed)))) FROM events WHERE event='ai_message_completed' {env_filter} " + _RANGE,
        spark="SELECT {bkt}(timestamp) wk, round(sum(toFloat64OrNull(toString(properties.files_changed)))) v FROM events WHERE event='ai_message_completed' {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "activation": Metric(
        key="activation", title="New users who got a result", unit="%",
        definition="Percentage of new sign-ups who successfully got the AI to build something at least once.",
        sql="SELECT round(100.0*countIf(act)/nullIf(count(),0),1) FROM (SELECT person_id, minIf(timestamp, event='auth_signup_succeeded') su, countIf(event='ai_message_completed')>0 act FROM events WHERE event IN ('auth_signup_succeeded','ai_message_completed') {env_filter} GROUP BY person_id HAVING su >= toDateTime('{from}') AND su < toDateTime('{to}'))",
        spark="SELECT toStartOfWeek(su) wk, round(100.0*countIf(act)/nullIf(count(),0),1) v FROM (SELECT person_id, minIf(timestamp,event='auth_signup_succeeded') su, countIf(event='ai_message_completed')>0 act FROM events WHERE event IN ('auth_signup_succeeded','ai_message_completed') {env_filter} AND timestamp > now() - INTERVAL 14 WEEK GROUP BY person_id HAVING su > now() - INTERVAL 10 WEEK) GROUP BY wk ORDER BY wk"
    ),
    "gen_success": Metric(
        key="gen_success", title="AI success rate", unit="%",
        definition="Percentage of AI requests that finished successfully.",
        sql="SELECT round(100.0*countIf(event='ai_message_completed')/nullIf(countIf(event='ai_message_sent'),0),1) FROM events WHERE event IN ('ai_message_sent','ai_message_completed') {env_filter} " + _RANGE
    ),
    "kept_rate": Metric(
        key="kept_rate", title="Work kept (not undone)", unit="%",
        definition="Percentage of AI-generated changes the user did NOT undo afterward.",
        caveat="This is an estimate — a user not undoing a change isn't the same as approving it.",
        sql="SELECT round(100.0*(countIf(event='ai_message_completed')-countIf(event='ai_message_reverted'))/nullIf(countIf(event='ai_message_completed'),0),1) FROM events WHERE event IN ('ai_message_completed','ai_message_reverted') {env_filter} " + _RANGE
    ),
    "preview_reliability": Metric(
        key="preview_reliability", title="Preview reliability", unit="%",
        definition="How often a project preview successfully loads when requested.",
        caveat="Previews warmed up in the background load instantly and can flatter this; based on few events, so read as directional.",
        sql="SELECT round(100.0*countIf(event='preview_ready')/nullIf(countIf(event='preview_start_requested'),0),1) FROM events WHERE event IN ('preview_ready','preview_start_requested') {env_filter} " + _RANGE
    ),
    "churn_risk": Metric(
        key="churn_risk", title="Users who've gone quiet", unit="",
        window="rolling: active 15-60d ago, silent last 14d",
        definition="Users who were active a month or two ago but have had no activity in the last two weeks — a sign they may be leaving.",
        sql="SELECT count(DISTINCT person_id) FROM events WHERE person_id IN (SELECT person_id FROM events WHERE timestamp >= now()-INTERVAL 60 DAY AND timestamp < now()-INTERVAL 15 DAY {env_filter} GROUP BY person_id) AND person_id NOT IN (SELECT person_id FROM events WHERE timestamp > now()-INTERVAL 14 DAY {env_filter} GROUP BY person_id)",
        good_when_up=False
    ),

    # ---- weekly trend series (line / bar) -------------------------------
    "active_weekly": Metric(
        key="active_weekly", title="User growth", shape="series", unit="users", window="",
        definition="Total people who visited or used the product each week — includes casual and one-time visitors, not just engaged users.",
        sql="SELECT {bkt}(timestamp) wk, count(DISTINCT person_id) n FROM events WHERE true {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "gen_success_weekly": Metric(
        key="gen_success_weekly", title="AI success rate over time", shape="series", unit="%", window="",
        definition="Percentage of AI requests that finished successfully, week by week.",
        sql="SELECT {bkt}(timestamp) wk, round(100.0*countIf(event='ai_message_completed')/nullIf(countIf(event='ai_message_sent'),0),1) pct FROM events WHERE event IN ('ai_message_sent','ai_message_completed') {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "preview_reliability_weekly": Metric(
        key="preview_reliability_weekly", title="Preview reliability over time", shape="series", unit="%", window="",
        definition="How often preview requests loaded successfully, week by week.",
        sql="SELECT {bkt}(timestamp) wk, round(100.0*countIf(event='preview_ready')/nullIf(countIf(event='preview_start_requested'),0),1) pct FROM events WHERE event IN ('preview_ready','preview_start_requested') {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),

    "latency_weekly": Metric(
        key="latency_weekly", title="Response time over time", shape="series", unit="s", window="",
        definition="How long a typical AI request takes to finish, tracked week by week.", good_when_up=False,
        sql="SELECT {bkt}(timestamp) wk, round(median(toFloat64OrNull(toString(properties.duration_ms)))/1000,1) v FROM events WHERE event='ai_message_completed' {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "exception_weekly": Metric(
        key="exception_weekly", title="Website errors over time", shape="series", unit="errors", window="",
        definition="Technical errors happening in users' browsers, week by week. Many show no detail due to browser privacy rules, but the count is real.", good_when_up=False,
        sql="SELECT {bkt}(timestamp) wk, count() n FROM events WHERE event='$exception' {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "requests_daily": Metric(
        key="requests_daily", title="AI requests over time", shape="series", unit="requests",
        definition="Number of AI requests, grouped by day, week, or month depending on the date range selected.",
        sql="SELECT {bkt}(timestamp) d, count() n FROM events WHERE event='ai_message_sent' {env_filter} " + _RANGE + " GROUP BY d ORDER BY d"
    ),
    "peak_hours": Metric(
        key="peak_hours", title="Busiest hours of the day", shape="series", unit="requests",
        definition="Number of AI requests during each hour of the day, so you can see when usage peaks. Hours are in world-standard time (UTC), not local time.",
        sql="SELECT toHour(timestamp) h, count() n FROM events WHERE event='ai_message_sent' {env_filter} " + _RANGE + " GROUP BY h ORDER BY h"
    ),
    "daily_ai": Metric(
        key="daily_ai", title="AI usage volume", shape="series", unit="gens",
        definition="Number of completed AI requests over time.",
        sql="SELECT {bkt}(timestamp) d, count() n FROM events WHERE event='ai_message_completed' {env_filter} " + _RANGE + " GROUP BY d ORDER BY d"
    ),

    # ---- more scalars ---------------------------------------------------
    "requests_per_active": Metric(
        key="requests_per_active", title="Requests per user", unit="",
        definition="On average, how many AI requests each active user makes in this period.",
        sql="SELECT round(count() / nullIf(count(DISTINCT person_id), 0), 1) FROM events WHERE event='ai_message_sent' {env_filter} " + _RANGE
    ),
    "prompt_len": Metric(
        key="prompt_len", title="Typical request length", unit="chars",
        definition="The typical length of what a user types when asking the AI for something.",
        sql="SELECT round(median(toFloat64OrNull(toString(properties.prompt_length)))) FROM events WHERE event='ai_message_sent' {env_filter} " + _RANGE
    ),
    "exception_total": Metric(
        key="exception_total", title="Website errors", unit="", good_when_up=False,
        definition="Total technical errors in users' browsers this period. Many show no detail due to browser privacy rules — not itself a sign of a bug.",
        sql="SELECT count() FROM events WHERE event='$exception' {env_filter} " + _RANGE
    ),
    "ai_baseline": Metric(
        key="ai_baseline", title="Normal daily AI usage", unit="gens/day", window="last 30 days",
        definition="Average completed AI requests per day over the last 30 days — a reference for what 'normal' looks like.",
        sql="SELECT round(avg(n)) FROM (SELECT toDate(timestamp) d, count() n FROM events WHERE event='ai_message_completed' {env_filter} AND timestamp > now() - INTERVAL 30 DAY GROUP BY d)"
    ),

    "failure_rate": Metric(
        key="failure_rate", title="AI failure rate", unit="%", good_when_up=False,
        definition="Percentage of AI requests that failed to complete.",
        sql="SELECT round(100.0*countIf(event='ai_message_failed')/nullIf(countIf(event='ai_message_sent'),0),1) FROM events WHERE event IN ('ai_message_sent','ai_message_failed') {env_filter} " + _RANGE
    ),
    "revert_rate": Metric(
        key="revert_rate", title="Undo rate", unit="%", good_when_up=False,
        definition="Percentage of AI-generated changes users undid afterward.",
        caveat="An estimate of quality, not a direct measure — undoing a change can mean many things.",
        sql="SELECT round(100.0*countIf(event='ai_message_reverted')/nullIf(countIf(event='ai_message_completed'),0),1) FROM events WHERE event IN ('ai_message_completed','ai_message_reverted') {env_filter} " + _RANGE
    ),
    "rating_ratio": Metric(
        key="rating_ratio", title="Helpful rate", unit="%",
        definition="Percentage of AI responses users rated as helpful, out of all responses they rated.",
        caveat="This rating feature hasn't launched yet, so it reads empty until it does.",
        sql="SELECT round(100.0*countIf(toString(properties.rating)='up')/nullIf(count(),0),1) FROM events WHERE event='ai_response_rated' {env_filter} " + _RANGE
    ),

    # ---- cost (gated on POSTHOG_PROJECT_TOKEN → ai_generation_metered) ---
    "metered_rows": Metric(
        key="metered_rows", title="Cost-tracked AI runs", unit="", window="last 90 days",
        definition="Number of AI runs with detailed cost data over the last 90 days.",
        sql="SELECT count() FROM events WHERE event='ai_generation_metered' {env_filter} AND timestamp > now() - INTERVAL 90 DAY"
    ),
    "total_spend": Metric(
        key="total_spend", title="Total AI cost", unit="$",
        definition="Total dollars spent on AI usage this period.",
        caveat="Reads $0 until live cost-tracking is fully switched on — not that spend was actually zero.",
        sql="SELECT round(sum(toFloat64OrNull(toString(properties.cost_usd))),2) FROM events WHERE event='ai_generation_metered' {env_filter} " + _RANGE
    ),
    "cost_per_request": Metric(
        key="cost_per_request", title="Cost per AI request", unit="$",
        definition="Average dollar cost of one AI request.",
        caveat="Reads $0 until live cost-tracking is fully switched on.",
        sql="SELECT round(avg(toFloat64OrNull(toString(properties.cost_usd))),4) FROM events WHERE event='ai_generation_metered' {env_filter} " + _RANGE
    ),
    "cost_per_user": Metric(
        key="cost_per_user", title="Cost per active user", unit="$",
        definition="Average dollar cost per user who generated AI usage.",
        caveat="Reads $0 until live cost-tracking is fully switched on.",
        sql="SELECT round(sum(toFloat64OrNull(toString(properties.cost_usd)))/nullIf(count(DISTINCT person_id),0),2) FROM events WHERE event='ai_generation_metered' {env_filter} " + _RANGE
    ),

    # ---- more weekly series ---------------------------------------------
    "revert_weekly": Metric(
        key="revert_weekly", title="Undo rate over time", shape="series", unit="%", window="", good_when_up=False,
        definition="Percentage of AI changes users undid, week by week.",
        sql="SELECT {bkt}(timestamp) wk, round(100.0*countIf(event='ai_message_reverted')/nullIf(countIf(event='ai_message_completed'),0),1) pct FROM events WHERE event IN ('ai_message_completed','ai_message_reverted') {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "kept_weekly": Metric(
        key="kept_weekly", title="Work kept over time", shape="series", unit="%", window="",
        definition="Percentage of AI changes users did NOT undo, tracked over time.",
        caveat="An estimate — not undoing isn't the same as approving.",
        sql="SELECT {bkt}(timestamp) wk, round(100.0*(countIf(event='ai_message_completed')-countIf(event='ai_message_reverted'))/nullIf(countIf(event='ai_message_completed'),0),1) pct FROM events WHERE event IN ('ai_message_completed','ai_message_reverted') {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "files_changed_weekly": Metric(
        key="files_changed_weekly", title="Files changed by AI over time", shape="series", unit="files", window="",
        definition="Total files the AI changed for users, week by week.",
        sql="SELECT {bkt}(timestamp) wk, round(sum(toFloat64OrNull(toString(properties.files_changed)))) v FROM events WHERE event='ai_message_completed' {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "ai_requests_weekly": Metric(
        key="ai_requests_weekly", title="AI usage over time", shape="series", unit="requests", window="",
        definition="AI requests made each week — the main driver of AI costs.",
        sql="SELECT {bkt}(timestamp) wk, count() n FROM events WHERE event='ai_message_sent' {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),

    # ---- more breakdown rows --------------------------------------------
    "model_mix": Metric(
        key="model_mix", title="Which AI model people choose", shape="rows",
        definition="How often users manually switch to each AI model — an estimate of popularity, not a direct usage count.",
        caveat="Counts model switches, not which model ran each request; an exact breakdown comes with detailed cost-tracking.",
        sql="SELECT coalesce(nullIf(toString(properties.to),''),'unknown') model, count() n FROM events WHERE event='ai_model_switched_from_chat' {env_filter} " + _RANGE + " GROUP BY model ORDER BY n DESC LIMIT 8"
    ),
    "issue_categories": Metric(
        key="issue_categories", title="Issues reported by users", shape="rows",
        definition="Breakdown of problems users have reported about the AI, like 'inaccurate', 'incomplete', or 'too slow'.",
        caveat="This feature hasn't launched yet, so it reads empty until users can report issues live.",
        sql="SELECT coalesce(nullIf(toString(properties.category),''),'unknown') category, count() n FROM events WHERE event='ai_issue_reported' {env_filter} " + _RANGE + " GROUP BY category ORDER BY n DESC LIMIT 8"
    ),

    # ---- breakdown rows (hbars / table) ---------------------------------
    "ai_fail_reasons": Metric(
        key="ai_fail_reasons", title="Top failure reasons", shape="rows",
        definition="The most common reasons an AI request fails, such as taking too long and timing out.",
        sql="SELECT coalesce(nullIf(toString(properties.reason),''),'unknown') reason, count() n FROM events WHERE event='ai_message_failed' {env_filter} " + _RANGE + " GROUP BY reason ORDER BY n DESC LIMIT 8"
    ),
    "feature_table": Metric(
        key="feature_table", title="Feature adoption (detail)", shape="rows",
        definition="For each feature, how many users used it and what share of active users that represents.",
        caveat="Share is out of actively-building users. Some features are paid-plan-only, so low numbers may reflect plan limits.",
        sql="SELECT event feature, count(DISTINCT person_id) users, round(100.0*count(DISTINCT person_id)/nullIf((SELECT count(DISTINCT person_id) FROM events WHERE event IN ('ai_message_sent','preview_ready','project_created') {env_filter} " + _RANGE + "),0),1) adoption_pct FROM events WHERE event IN ('ide_opened','project_created','preview_start_requested','ai_message_sent','git_commit_succeeded','github_connect_succeeded','project_shared','export_downloaded','deploy_sandbox_clicked','deploy_production_clicked') {env_filter} " + _RANGE + " GROUP BY feature ORDER BY users DESC LIMIT 15"
    ),

    # ---- breakdown rows (hbars / table) ---------------------------------
    "top_features": Metric(
        key="top_features", title="Most-used features", shape="rows",
        definition="How many unique users used each feature this period.",
        caveat="Some features are paid-plan-only, so low numbers often reflect plan limits, not low interest.",
        sql="SELECT event, count(DISTINCT person_id) users FROM events WHERE event IN ('ide_opened','project_created','preview_start_requested','git_commit_succeeded','github_connect_succeeded','project_shared','export_downloaded','deploy_sandbox_clicked','deploy_production_clicked') {env_filter} " + _RANGE + " GROUP BY event ORDER BY users DESC LIMIT 10"
    ),
    "problem_areas": Metric(
        key="problem_areas", title="Top problem areas", shape="rows",
        definition="Where users hit the most friction: AI requests failing, previews failing to load, or errors in the browser.",
        sql="SELECT multiIf(event='ai_message_failed','AI generation failed', event='preview_start_failed','Preview failed to start', event='$exception','JS error (client)', event) area, count() n FROM events WHERE event IN ('ai_message_failed','preview_start_failed','$exception') {env_filter} " + _RANGE + " GROUP BY area ORDER BY n DESC LIMIT 8"
    ),
    "signup_method": Metric(
        key="signup_method", title="How people sign up", shape="rows",
        definition="How new users create their account — password, Google, or GitHub.",
        caveat="Based on few sign-ups so far; Google and GitHub only show data once people use those options here.",
        sql="SELECT coalesce(nullIf(toString(properties.method),''),'unknown') method, count(DISTINCT person_id) users FROM events WHERE event='auth_signup_succeeded' {env_filter} " + _RANGE + " GROUP BY method ORDER BY users DESC"
    ),
    "returning_weekly": Metric(
        key="returning_weekly", title="Returning users", shape="series", unit="users", window="",
        definition="Users who came back and used the product again in a later week, rather than using it just once.",
        sql="SELECT wk, uniqIf(person_id, wk!=first_wk) returning_users FROM (SELECT person_id, {bkt}(timestamp) wk, min({bkt}(timestamp)) OVER (PARTITION BY person_id) first_wk FROM events WHERE true {env_filter} " + _RANGE + ") GROUP BY wk ORDER BY wk"
    ),

    # ---- funnel ---------------------------------------------------------
    "funnel": Metric(
        key="funnel", title="New-user journey", shape="funnel",
        definition="Of the people who signed up this period, how many went on to create a project, send an AI request, get a result, and preview it.",
        steps=["Signed up", "Created project", "Sent AI msg", "Got a build", "Previewed"],
        sql="WITH s AS (SELECT DISTINCT person_id FROM events WHERE event='auth_signup_succeeded' {env_filter} " + _RANGE + ") SELECT (SELECT count() FROM s) signed_up, countDistinct(if(event='project_created',person_id,NULL)) created_project, countDistinct(if(event='ai_message_sent',person_id,NULL)) sent_ai, countDistinct(if(event='ai_message_completed',person_id,NULL)) got_build, countDistinct(if(event='preview_ready',person_id,NULL)) previewed FROM events WHERE true {env_filter} " + _RANGE + " AND person_id IN (SELECT person_id FROM s)"
    ),

    # ---- deploy ---------------------------------------------------------
    "deploy_intent": Metric(
        key="deploy_intent", title="Deploy attempts", shape="rows",
        definition="How many times users clicked to deploy, split between a test version and the live public version.",
        sql="SELECT multiIf(event='deploy_sandbox_clicked','Sandbox', event='deploy_production_clicked','Production', event) target, count() n FROM events WHERE event IN ('deploy_sandbox_clicked','deploy_production_clicked') {env_filter} " + _RANGE + " GROUP BY target ORDER BY n DESC"
    ),
    "deploy_success": Metric(
        key="deploy_success", title="Deploy success rate", unit="%",
        definition="Percentage of deploy attempts that actually succeeded.",
        caveat="This tracking hasn't launched yet, so it shows 'not available' until it does.",
        sql="SELECT round(100.0*countIf(event IN ('deploy_sandbox_succeeded','deploy_production_succeeded'))/nullIf(countIf(event IN ('deploy_sandbox_succeeded','deploy_production_succeeded','deploy_sandbox_failed','deploy_production_failed')),0),1) FROM events WHERE event LIKE 'deploy_%' {env_filter} " + _RANGE
    ),

    # ---- lifecycle (native LifecycleQuery) ------------------------------
    "lifecycle": Metric(
        key="lifecycle", title="User lifecycle", shape="lifecycle", window="last 8 weeks",
        definition="Each week, how many users are brand new, returning regularly, coming back after a break, or have gone quiet.",
        caveat="Based on few live users so far — read the shape and direction, not exact counts."
    ),

    # ---- retention (native RetentionQuery) ------------------------------
    "retention": Metric(
        key="retention", title="Retention over time", shape="retention", window="signup-week cohorts, 6 weeks",
        definition="Groups users by the week they signed up, then tracks the share still using the AI each following week. The 4-week mark shows who sticks around after a month.",
        caveat="Based on small groups so far — treat the pattern as directional. Groups under 15 people are flagged as too small to trust.",
        good_when_up=True
    )
};

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _fill(sql: str, env: str, dfrom: str, dto: str, bkt: str) -> str {
    out = sql.replace("{env_filter}", env_filter(env));
    out = out.replace("{bkt}", bkt);
    out = out.replace("{from}", dfrom);
    out = out.replace("{to}", dto);
    return out;
}

def _clamp_env(env: str) -> str {
    if env in ["prod", "dev", "preview", "all"] {
        return env;
    }
    return "prod";
}

import re;
def _valid_date(s: str) -> bool {
    return bool(re.match(r"^\d{4}-\d{2}-\d{2}$", s));
}

# Adaptive time bucket for trend series so a chart always has a sensible number of points
# regardless of the selected range: daily for short ranges, weekly for medium, monthly for long.
def _bucket(days: int) -> str {
    if days <= 31 {
        return "toDate";
    }
    if days <= 186 {
        return "toStartOfWeek";
    }
    return "toStartOfMonth";
}

def _series(rows: list) -> list {
    out = [];
    for r in rows {
        out = out + [{"x": r[0], "y": r[1]}];
    }
    return out;
}

def _scalar(rows: list) -> any {
    if rows {
        first = rows[0];
        if first {
            return first[0];
        }
    }
    return None;
}

# % change of current vs previous window; None if either side is missing or prev is 0.
def _delta(cur: any, prev: any) -> any {
    if (cur is None) or (prev is None) {
        return None;
    }
    try {
        c = cur as float;
        p = prev as float;
        if p == 0.0 {
            return None;
        }
        return (c - p) / p * 100.0;
    } except Exception {
        return None;
    }
}

def _shape_retention(env: str) -> dict {
    e = env_expr(env);
    q: dict = {
        "kind": "RetentionQuery",
        "retentionFilter": {
            "period": "Week", "totalIntervals": 6,
            "targetEntity": {"id": "auth_signup_succeeded", "type": "events"},
            "returningEntity": {"id": "ai_message_completed", "type": "events"},
            "retentionType": "retention_first_time"
        },
        "dateRange": {"date_from": "-6w"}
    };
    if e {
        q["properties"] = [{"type": "hogql", "key": e}];
    }
    res = run_query(q);
    if "error" in res {
        return {"error": res["error"]};
    }
    cohorts = res["results"] as list;
    rows = [];
    for coh in cohorts {
        vals = coh["values"] as list;
        base = vals[0]["count"];
        bf = base as float;
        row = [coh["date"], base];
        for v in vals {
            cf = v["count"] as float;
            pct = (100.0 * cf / bf) if bf else 0.0;
            row = row + [pct];
        }
        rows = rows + [row];
    }
    return {"columns": ["cohort", "base", "w0", "w1", "w2", "w3", "w4", "w5"], "rows": rows};
}

def _shape_lifecycle(env: str) -> dict {
    e = env_expr(env);
    q: dict = {
        "kind": "LifecycleQuery",
        "series": [{"kind": "EventsNode", "event": "ai_message_completed", "math": "total"}],
        "interval": "week",
        "dateRange": {"date_from": "-8w"}
    };
    if e {
        q["properties"] = [{"type": "hogql", "key": e}];
    }
    res = run_query(q);
    if "error" in res {
        return {"error": res["error"]};
    }
    series = res["results"] as list;
    bystat = {};
    days = [];
    for s in series {
        st = str(s["status"]);
        bystat[st] = s["data"] as list;
        days = s["days"] as list;
    }
    rows = [];
    i = 0;
    for d in days {
        row = [str(d)[:10]];
        for st in ["new", "returning", "resurrecting", "dormant"] {
            arr = bystat.get(st, []) as list;
            v = arr[i] if (i < len(arr)) else 0;
            row = row + [v];
        }
        rows = rows + [row];
        i = i + 1;
    }
    return {"columns": ["week", "new", "returning", "resurrecting", "dormant"], "rows": rows};
}

# ---------------------------------------------------------------------------
# The one endpoint the client calls
# ---------------------------------------------------------------------------

async def:priv metric(key: str, env: str, date_from: str, date_to: str, refresh: bool) -> dict {
    m = METRICS.get(key);
    if m is None {
        return {"value": None, "error": f"unknown metric '{key}'", "meta": {}};
    }

    env = _clamp_env(env);
    if not (_valid_date(date_from) and _valid_date(date_to)) {
        return {"value": None, "error": "bad date range", "meta": {}};
    }
    dfrom = datetime.strptime(date_from, "%Y-%m-%d");
    dto = datetime.strptime(date_to, "%Y-%m-%d");
    range_days = (dto - dfrom).days;
    if range_days < 1 {
        range_days = 1;
    }
    bkt = _bucket(range_days);

    window_label = m.window if m.window else f"{date_from} → {date_to} ({range_days}d)";
    meta: dict = {
        "definition": m.definition, "window": window_label, "caveat": m.caveat,
        "env": env, "unit": m.unit, "good_when_up": m.good_when_up, "cached": False
    };

    ck = f"metric:{key}:{env}:{date_from}:{date_to}";
    if not refresh {
        cached = _cache_get(ck);
        if cached is not None {
            return cached;
        }
    }

    out: dict = {"value": None, "series": [], "columns": [], "rows": [], "prev": None, "delta": None, "meta": meta};

    return await _run_metric(m, out, env, range_days, date_from, date_to, bkt, ck);
}

# One page fetches ALL its tiles in a single request; queries run concurrently server-side
# (asyncio.gather over threads) so jac-serve's per-request serialization is bypassed.
async def:priv metrics_batch(keys: list, env: str, date_from: str, date_to: str, refresh: bool) -> dict {
    tasks = [];
    for k in keys {
        tasks = tasks + [metric(k as str, env, date_from, date_to, refresh)];
    }
    results = await asyncio.gather(*tasks);
    out: dict = {};
    i = 0;
    for k in keys {
        out[k as str] = results[i];
        i = i + 1;
    }
    return out;
}

# Admin free-form HogQL box (read-only). Rejects anything that isn't a single SELECT/WITH.
# (Gate behind admin auth before shipping externally; the phx_ key is read-only so the blast radius
#  is limited to reading data the dashboard already surfaces.)
# Lightweight authed ping — the client uses this to validate a stored token on load
# (a present-but-invalid token otherwise shows the shell with empty tiles).
def:priv verify_session() -> bool {
    return True;
}

async def:priv run_adhoc(sql: str) -> dict {
    s = sql.strip();
    low = s.lower();
    if not (low.startswith("select") or low.startswith("with")) {
        return {"error": "Only read-only SELECT / WITH queries are allowed.", "columns": [], "rows": []};
    }
    if ";" in s.rstrip(";") {
        return {"error": "One statement only (no ';').", "columns": [], "rows": []};
    }
    res = await asyncio.to_thread(run_hogql, s);
    if "error" in res {
        return {"error": res["error"], "columns": [], "rows": []};
    }
    return {"error": "", "columns": res["columns"], "rows": res["results"]};
}

# ---------------------------------------------------------------------------
# AI insights — an LLM-authored narrative over the already-computed metrics.
# Server-only ANTHROPIC_API_KEY; mirrors billing_sv's honest-degrade pattern.
# ---------------------------------------------------------------------------

def _summarize_context(context: dict) -> str {
    parts = [];
    for k in context.keys() {
        v = context.get(k);
        if not isinstance(v, dict) {
            continue;
        }
        vv = v as dict;
        meta = vv.get("meta", {}) as dict;
        unit = str(meta.get("unit", ""));
        val = vv.get("value");
        rows = vv.get("rows");
        series = vv.get("series");
        if val is not None {
            parts = parts + [str(k) + ": " + str(val) + " " + unit];
        } elif rows and isinstance(rows, list) and len(rows as list) > 0 {
            first = (rows as list)[0] as list;
            parts = parts + [str(k) + ": top = " + str(first)];
        } elif series and isinstance(series, list) and len(series as list) > 0 {
            pts = series as list;
            last = pts[len(pts) - 1] as dict;
            parts = parts + [str(k) + " (latest): " + str(last.get("y")) + " " + unit];
        }
    }
    return "\n".join(parts);
}

# byLLM: the function body IS the LLM call. Model configured via INSIGHT_LLM
# (Anthropic, reads ANTHROPIC_API_KEY from env). The `sem` strings are the prompt.
def _write_insight(metrics: str) -> str by INSIGHT_LLM(max_tokens=400);
sem _write_insight = "You are a product analytics assistant for JacHammer, an AI-powered web IDE. Given current dashboard metrics (server-computed, already filtered to the production environment), write a 3-4 sentence plain-English readout for a decision-maker: what stands out, and the single thing most worth watching next. Cite the specific numbers. No preamble, no bullet points, no restating the list verbatim.";
sem _write_insight.metrics = "The current dashboard metrics, one per line as 'key: value unit' (or top row / latest point for non-scalar tiles).";

async def:priv ai_insights(context: dict) -> dict {
    if not ANTH_KEY {
        return {"available": False, "reason": "ANTHROPIC_API_KEY not set on the server.", "text": ""};
    }
    summary = _summarize_context(context);
    if not summary {
        return {"available": False, "reason": "No metric values to summarize yet.", "text": ""};
    }
    try {
        text = await asyncio.to_thread(_write_insight, summary);
        return {"available": True, "reason": "", "text": str(text).strip()};
    } except Exception as e {
        return {"available": False, "reason": str(e)[:160], "text": ""};
    }
}

# ---------------------------------------------------------------------------
# Event-usage map for the data dictionary — which registry metrics reference
# each event, derived live from METRICS so the dictionary can't silently drift.
# ---------------------------------------------------------------------------

def:priv event_usage(events: list) -> dict {
    out = {};
    for name in events {
        nm = str(name);
        needle = "'" + nm + "'";
        keys = [];
        for k in METRICS.keys() {
            m = METRICS[k];
            if needle in m.sql {
                keys = keys + [k];
            }
        }
        out[nm] = keys;
    }
    return out;
}

async def _run_metric(m: Metric, out: dict, env: str, range_days: int, date_from: str, date_to: str, bkt: str, ck: str) -> dict {
    if m.shape == "retention" {
        r = await asyncio.to_thread(_shape_retention, env);
        if "error" in r {
            out["error"] = r["error"];
            return out;
        }
        out["columns"] = r["columns"];
        out["rows"] = r["rows"];
        _cache_put(ck, out);
        return out;
    }

    if m.shape == "lifecycle" {
        r = await asyncio.to_thread(_shape_lifecycle, env);
        if "error" in r {
            out["error"] = r["error"];
            return out;
        }
        out["columns"] = r["columns"];
        out["rows"] = r["rows"];
        _cache_put(ck, out);
        return out;
    }

    res = await asyncio.to_thread(run_hogql, _fill(m.sql, env, date_from, date_to, bkt));
    if "error" in res {
        out["error"] = res["error"];
        return out;
    }
    cols = res["columns"] as list;
    rows = res["results"] as list;
    out["columns"] = cols;
    out["rows"] = rows;

    if m.shape == "scalar" {
        val = _scalar(rows);
        out["value"] = val;
        # compare-to-previous: same query over the immediately-preceding window of equal length
        if "{from}" in m.sql {
            prev_to = date_from;
            prev_from = (datetime.strptime(date_from, "%Y-%m-%d") - timedelta(days=range_days)).strftime("%Y-%m-%d");
            pres = await asyncio.to_thread(run_hogql, _fill(m.sql, env, prev_from, prev_to, bkt));
            if "error" not in pres {
                pv = _scalar(pres["results"] as list);
                out["prev"] = pv;
                out["delta"] = _delta(val, pv);
            }
        }
        if m.spark {
            sp = await asyncio.to_thread(run_hogql, _fill(m.spark, env, date_from, date_to, bkt));
            if "error" not in sp {
                out["series"] = _series(sp["results"] as list);
            }
        }
    } elif m.shape == "series" {
        out["series"] = _series(rows);
    } elif m.shape == "funnel" {
        steps = m.steps;
        frow = rows[0] if rows else [];
        frows = [];
        i = 0;
        for lab in steps {
            val = frow[i] if (frow and i < len(steps)) else 0;
            frows = frows + [[lab, val]];
            i = i + 1;
        }
        out["rows"] = frows;
        out["columns"] = ["step", "users"];
    }
    # shape == "rows": columns + rows already set

    _cache_put(ck, out);
    return out;
}
