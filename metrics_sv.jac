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
import re;
import json;
import asyncio;
import traceback;
import requests;
import redis;
import from datetime { datetime, timedelta, timezone }
import from jaclang.byllm.lib { Model }

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
        caveat="Counts model switches, not which model ran each request — see 'AI requests by model' (model_usage) for the true run breakdown once properties.model has shipped.",
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
    ),

    # ---- tracking-gaps tiles (consume the newly-added events; each reads
    # empty until its event ships to prod — see TRACKING_GAPS.md) -----------
    "upgrade_conversion": Metric(
        key="upgrade_conversion", title="Upgrade conversion", unit="%",
        definition="Of users who clicked to upgrade, the share who actually completed the paid upgrade.",
        caveat="Empty until upgrade_checkout_succeeded ships to production.",
        sql="SELECT round(100.0*countIf(event='upgrade_checkout_succeeded')/nullIf(countIf(event='upgrade_checkout_clicked'),0),1) FROM events WHERE event IN ('upgrade_checkout_clicked','upgrade_checkout_succeeded') {env_filter} " + _RANGE
    ),
    "paid_upgrades": Metric(
        key="paid_upgrades", title="Completed upgrades", unit="",
        definition="Number of paid subscription upgrades that completed in this period.",
        sql="SELECT count() FROM events WHERE event='upgrade_checkout_succeeded' {env_filter} " + _RANGE,
        spark="SELECT {bkt}(timestamp) wk, count() n FROM events WHERE event='upgrade_checkout_succeeded' {env_filter} " + _RANGE + " GROUP BY wk ORDER BY wk"
    ),
    "mrr_churn": Metric(
        key="mrr_churn", title="MRR lost to churn", unit="$", good_when_up=False,
        definition="Monthly recurring revenue lost from subscription cancellations in this period.",
        caveat="Empty until subscription_canceled ships to production.",
        sql="SELECT round(-1*sum(toFloat64OrNull(toString(properties.mrr_delta))),2) FROM events WHERE event='subscription_canceled' {env_filter} " + _RANGE
    ),
    "first_try_success": Metric(
        key="first_try_success", title="First-try success", unit="%",
        definition="Share of chat threads where the AI got it right on the first turn — turn 1 completed and no follow-up turn was needed.",
        caveat="Empty until conversation_id + turn_number ship to production.",
        sql="SELECT round(100.0*countIf(t1_done AND max_turn=1)/nullIf(count(),0),1) FROM (SELECT toString(properties.conversation_id) cid, max(toFloat64OrNull(toString(properties.turn_number))) max_turn, countIf(event='ai_message_completed' AND toFloat64OrNull(toString(properties.turn_number))=1)>0 t1_done FROM events WHERE event IN ('ai_message_sent','ai_message_completed') {env_filter} " + _RANGE + " GROUP BY cid HAVING cid != '')"
    ),
    "model_latency": Metric(
        key="model_latency", title="Response time by model", shape="rows", unit="s", good_when_up=False,
        definition="Typical AI response time, broken down by the model that actually ran each request.",
        caveat="Empty until model ships on ai_message_completed.",
        sql="SELECT toString(properties.model) model, round(median(toFloat64OrNull(toString(properties.duration_ms)))/1000,1) v FROM events WHERE event='ai_message_completed' AND coalesce(toString(properties.model),'')!='' {env_filter} " + _RANGE + " GROUP BY model ORDER BY v DESC LIMIT 20"
    ),
    "model_usage": Metric(
        key="model_usage", title="AI requests by model", shape="rows", unit="",
        definition="How many AI requests actually ran on each model — the true usage breakdown (distinct from model_mix, which counts manual switches).",
        caveat="Empty until model ships on ai_message_completed.",
        sql="SELECT coalesce(nullIf(toString(properties.model),''),'unknown') model, count() n FROM events WHERE event='ai_message_completed' AND coalesce(toString(properties.model),'')!='' {env_filter} " + _RANGE + " GROUP BY model ORDER BY n DESC LIMIT 8"
    ),
    "acquisition_channel": Metric(
        key="acquisition_channel", title="Signups by channel", shape="rows", unit="",
        definition="Where new signups came from, by first-touch UTM source (no source shows as 'direct').",
        caveat="Empty until first-touch UTM capture ships to production.",
        sql="SELECT if(coalesce(toString(properties.utm_source),'')='','direct',toString(properties.utm_source)) src, count() n FROM events WHERE event='auth_signup_succeeded' {env_filter} " + _RANGE + " GROUP BY src ORDER BY n DESC LIMIT 20"
    ),
    "signup_trigger_breakdown": Metric(
        key="signup_trigger_breakdown", title="Signups by trigger", shape="rows", unit="",
        definition="Which in-app gate or CTA drove each signup (guest locked feature, dashboard prompt, free-credit bonus, or direct).",
        caveat="Empty until signup_trigger ships to production.",
        sql="SELECT coalesce(nullIf(toString(properties.signup_trigger),''),'direct') trigger, count() n FROM events WHERE event='auth_signup_succeeded' {env_filter} " + _RANGE + " GROUP BY trigger ORDER BY n DESC LIMIT 10"
    ),
    "ai_edits": Metric(
        key="ai_edits", title="AI outputs manually edited", unit="", good_when_up=False,
        definition="How many times users manually edited a file the AI had just written — the real 'did they accept it' signal.",
        caveat="Empty until ai_response_edited ships to production.",
        sql="SELECT count() FROM events WHERE event='ai_response_edited' {env_filter} " + _RANGE
    ),
    "session_depth": Metric(
        key="session_depth", title="Typical session length", unit="min",
        definition="Median focused (active-tab) time users spend in the IDE per session.",
        caveat="Empty until ide_session_ended ships to production.",
        sql="SELECT round(median(toFloat64OrNull(toString(properties.duration_active_ms)))/60000,1) FROM events WHERE event='ide_session_ended' {env_filter} " + _RANGE
    ),
    "cold_preview_reliability": Metric(
        key="cold_preview_reliability", title="Preview reliability (cold only)", unit="%",
        definition="Preview success rate counting only cold starts — strips out pre-warmed previews that load instantly and flatter the headline.",
        caveat="Empty until cold_start ships on preview_ready.",
        sql="SELECT round(100.0*countIf(event='preview_ready' AND toString(properties.cold_start)='true')/nullIf(countIf(event='preview_start_requested' AND toString(properties.was_prepared)='false'),0),1) FROM events WHERE event IN ('preview_ready','preview_start_requested') {env_filter} " + _RANGE
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
# AI-first builder (v0, registry-only) — NL question -> which verified metrics
# answer it -> fetch them (reusing metric(): env filter + cache) -> tile specs.
# The LLM only SELECTS from existing keys; it never writes SQL. Hallucinated
# keys are dropped server-side, so a build can only ever run verified queries.
# ---------------------------------------------------------------------------

# Deterministic tile choice per metric. Most fall out of shape + unit; the few
# exceptions (donut/table/vbar) are pinned by key so we don't touch the registry.
glob _TILE_OVERRIDE: dict = {
    "signup_method": "donut", "model_mix": "donut", "feature_table": "table",
    "peak_hours": "vbar", "requests_daily": "vbar"
};

def _tile_for(m: Metric) -> str {
    ov = _TILE_OVERRIDE.get(m.key, "");
    if ov {
        return str(ov);
    }
    if m.shape == "funnel" {
        return "funnel";
    }
    if m.shape == "retention" {
        return "retention";
    }
    if m.shape == "lifecycle" {
        return "stackbar";
    }
    if m.shape == "series" {
        return "line" if (m.unit == "%" or m.unit == "s") else "area";
    }
    if m.shape == "rows" {
        return "bars";
    }
    return "gauge" if (m.unit == "%") else "stat";
}

# The grounding doc: every metric the planner is allowed to pick from.
def _catalog() -> str {
    lines = [];
    for k in METRICS.keys() {
        m = METRICS[k];
        lines = lines + ["- " + m.key + ": " + m.title + " — " + m.definition + " [" + m.shape + "]"];
    }
    return "\n".join(lines);
}

# Schema grounding for the dynamic (mode=query) path — lets the LLM write HogQL
# against real events/columns instead of hallucinating. Curated from EVENT_CATALOG.md.
glob _SCHEMA_DOC: str = "TABLE events — one row per tracked product event.\n"
    + "Columns: event (String), timestamp (DateTime), person_id (String — the user), properties (JSON). EVERY event/person field MUST be written as properties.<name> (e.g. properties.plan, properties.model, properties.provider, properties.cost_usd) — a bare identifier like `plan` or a raw `properties` reference is NOT a column and errors with 'cannot resolve field'.\n"
    + "HogQL idioms: text presence = coalesce(toString(properties.X),'') != '' ; numbers = toFloat64OrNull(toString(properties.X)) ; per-user rows = GROUP BY person_id.\n"
    + "TIME (HogQL, evaluated by ClickHouse — no date math needed): today = toDate(timestamp) = today() ; yesterday = toDate(timestamp) = yesterday() ; this week = timestamp >= toStartOfWeek(now()) ; this month = timestamp >= toStartOfMonth(now()) ; last N days = timestamp >= now() - INTERVAL N DAY ; a specific date = toDate(timestamp) = toDate('YYYY-MM-DD').\n"
    + "ALWAYS put the literal placeholder {env} in the main WHERE, e.g. WHERE {env} AND event='ai_message_sent'. The server replaces {env} with the production environment filter.\n"
    + "CORE events (name — key props):\n"
    + "auth_signup_succeeded (method — password/google/github; signup_trigger — guest_locked_feature/free_signup_bonus/dashboard_prompt/direct; NO 'provider' property) · auth_succeeded (method, is_new_user) · ide_opened · ide_session_ended (duration_active_ms — FOCUSED time not wall-clock; files_touched; previews_run; ended_reason) · project_created (source, project_type, files_count — files_count only on folder_upload)\n"
    + "ai_message_sent (prompt_length, attached_files_count, task_category, model, conversation_id, turn_number) · ai_message_completed (duration_ms, files_changed, response_length, model, conversation_id, turn_number, message_id) · ai_message_failed (reason, at_phase, duration_ms, model, conversation_id, turn_number) · ai_message_reverted (conversation_id, turn_number) · ai_response_rated (rating up/down, message_id) · ai_issue_reported (category, message_id) · ai_response_edited (message_id, time_to_edit_ms, files_changed — a manual edit of AI-written code = the real acceptance signal)\n"
    + "AI THREADING: conversation_id + turn_number link a chat thread — first-try success = turn_number=1 with an ai_message_completed and no later turn in the same conversation_id. properties.model is the model that ACTUALLY ran (now on ai_message_completed, not only ai_generation_metered).\n"
    + "preview_start_requested (was_prepared) · preview_ready (duration_ms, cold_start — true=cold; filter cold_start to de-inflate reliability) · preview_start_failed (reason)\n"
    + "deploy_sandbox_clicked · deploy_sandbox_succeeded (status) · deploy_production_clicked · deploy_production_succeeded (status)\n"
    + "git_commit_succeeded · github_connect_succeeded · project_shared · export_downloaded\n"
    + "ai_generation_metered (cost_usd, model, project_id) · upgrade_checkout_clicked (plan — INTENT only) · upgrade_checkout_succeeded (plan, plan_from, amount_usd, interval, is_first_upgrade, stripe_customer_id — the COMPLETED upgrade; paid conversion = succeeded/clicked) · subscription_canceled (plan_from, mrr_delta, days_active) · subscription_downgraded (plan_from, plan_to, mrr_delta) · topup_checkout_clicked (pack)\n"
    + "REVENUE: MRR-from-events = SUM over upgrade_checkout_succeeded.amount_usd minus churned; but the authoritative live MRR is Stripe (billing summary: mrr, active_subs) — properties.cost_usd is internal COST, never revenue.\n"
    + "SESSIONS: properties.$session_id groups events into one browser session (a rough session-length proxy); ide_session_ended.duration_active_ms is the real focused time per IDE session.\n"
    + "Person/event props for identity: properties.email, properties.display_name, properties.name, properties.plan (free/builder/pro). properties.method on auth_signup_succeeded is the LOGIN method (password/google/github) — NOT a marketing channel. properties.provider / properties.auth_provider do NOT exist.\n"
    + "ACQUISITION CHANNEL: first-touch UTM/referrer are captured. On CLIENT events they ride as super-properties (properties.utm_source/utm_medium/utm_campaign/utm_content/referrer/initial_referring_domain/landing_path); they are ALSO threaded explicitly onto the server-emitted auth_signup_succeeded, so channel attribution for SIGNUPS must read utm_* off auth_signup_succeeded (empty = direct/no campaign). Use these (NOT login method) for channel/campaign attribution.\n"
    + "PRIVACY: prompt/message TEXT is never stored — there is no message-content column; never try to read it.\n"
    + "person_id is the stable user id (email/display_name may be sparse). Use LIMIT for lists (server caps at 200).";

obj QueryPlan {
    # Field order = byLLM generation order. chart/good_up (which decide rendering) come
    # BEFORE the verbose sql so a tight token budget only ever truncates trailing prose,
    # never the tile type. (Fixed the D5/D6 compare→table truncation misfire.)
    has mode: str = "clarify";
    has keys: list[str] = [];
    has chart: str = "table";
    has good_up: bool = True;
    has title: str = "";
    has sql: str = "";
    has reasoning: str = "";
    has reply: str = "";
    has clarify: str = "";
}
sem QueryPlan = "A plan for how to answer the user's question: reuse verified metrics, write a custom query, or ask for clarification.";
sem QueryPlan.good_up = "For stat/compare/gauge charts only: True if a HIGHER number is better (signups, active users, revenue, success rate), False if a LOWER number is better (failures, errors, latency, churn, cost, reverts). Controls whether an increase is shown as good (green) or bad (red).";
sem QueryPlan.reasoning = "One short sentence for a developer debugging this result: why you chose this mode, and any assumption you made about the time window or scope (e.g. 'used the selected date range, not literally today' or 'wrote a per-user query since no metric lists users').";
sem QueryPlan.mode = "'metrics' when one or more CATALOG metrics fully answer the question; 'query' when you must write a custom read-only HogQL SELECT because the catalog lacks the exact cut (a specific list/table, a per-user or per-model breakdown, an ad-hoc filter); 'clarify' when the question is too vague, impossible, or off-topic.";
sem QueryPlan.keys = "mode=metrics ONLY: catalog keys taken VERBATIM from the leading 'key' column, most relevant first, at most 6. Empty otherwise.";
sem QueryPlan.sql = "mode=query ONLY: exactly ONE read-only HogQL SELECT/WITH answering the question, using only events/columns from the SCHEMA. MUST contain the literal {env} in its main WHERE. Never INSERT/ALTER/UPDATE/DELETE/DROP. Add an explicit LIMIT for any list. Empty otherwise.";
sem QueryPlan.chart = "mode=query ONLY: how to display the result — 'stat' (a single number: a count/total/percentage — SELECT exactly one aggregate), 'compare' (a single number VERSUS a comparison period, e.g. 'today vs yesterday' or 'this week vs last week' — SELECT exactly TWO aggregates in ONE row and alias them EXACTLY `current_value` and `previous_value`: current_value = the current / more-recent period the user names, previous_value = the comparison period. Column order does not matter — they are read by alias. E.g. countIf(<current-period predicate>) AS current_value, countIf(<previous-period predicate>) AS previous_value. Renders as a big number with a ±% delta badge), 'table' (multi-column rows, the default for lists/details), 'bars' (exactly 2 cols: text label + number, a ranking), 'line' or 'area' (2 cols: date + number, a trend), 'vbar' (2 cols: category + number, a distribution). The query's SELECT column order must match.";
sem QueryPlan.title = "A short (<= 6 word) title for the result.";
sem QueryPlan.reply = "One or two plain-English sentences telling a decision-maker what this shows. No preamble. Empty for clarify.";
sem QueryPlan.clarify = "mode=clarify ONLY: ONE friendly clarifying question or a short note on what is missing. Empty otherwise.";

def _plan_query(question: str, context: str) -> QueryPlan by INSIGHT_LLM(max_tokens=1400);
sem _plan_query = "You are the planner for JacHammer's product-analytics dashboard (an AI-powered web IDE). Answer the user's question. FIRST prefer mode=metrics with catalog keys when a verified metric fits (never invent a key). If the question needs a cut the catalog does not have — a specific list, a per-user/per-model/per-project table, a custom breakdown or filter — use mode=query and WRITE a safe read-only HogQL SELECT against the SCHEMA, always including the {env} placeholder in the main WHERE and a LIMIT for lists. Use mode=clarify only when the question is genuinely too vague, off-topic, or impossible with the available events. CRITICAL — TIME WORDS: verified catalog metrics follow the dashboard's SELECTED DATE RANGE (given in the context), NOT any period named in the question. So if the question names a specific period (today, yesterday, this week, this month, last N days, a specific date) that is not identical to the selected range, you MUST use mode=query with an explicit HogQL timestamp filter for exactly that period (see the SCHEMA TIME idioms — today()/yesterday()/now()-INTERVAL/toStartOfWeek), and set chart='stat' for a single count. Do NOT answer a 'today'/'this week' question with a picker-range metric — that returns the whole selected range and silently mislabels it. COMPARISONS: for an explicit 'X vs Y' question (today vs yesterday, this week vs last week, this month vs last month), use mode=query with chart='compare' — SELECT two aggregates in one row (current period first, then the comparison period, each via countIf/sumIf with the matching time predicate) — and set good_up to whether higher is better for that metric. HARD RULE: whenever your query SELECTs the aliases current_value and previous_value, chart MUST be 'compare' — NEVER 'table' or 'stat' (only 'compare' renders the ±% delta). For any latency / duration / response-time comparison, or any 'lower is better' metric (failures, errors, churn, cost, reverts), set good_up=False. HONESTY — CONCEPT GAPS: before mapping a question onto any metric or field, verify the SPECIFIC concept asked about is actually measured, not merely similar wording. Distinctions to respect (the mapping now EXISTS for each — use the right field, don't fall back to the wrong one): request/response LATENCY = properties.duration_ms, whereas session length/time-on-task = ide_session_ended.duration_active_ms (do NOT use duration_ms for session length); acquisition CHANNEL = properties.utm_source/utm_medium/utm_campaign/referrer (NOT login method properties.method); FIRST-TRY success = turn_number=1 ai_message_completed with no later turn in the same conversation_id (NOT the overall completion rate gen_success); a COMPLETED upgrade = upgrade_checkout_succeeded (NOT the intent-only upgrade_checkout_clicked); REVENUE = Stripe MRR (billing summary) or SUM(upgrade_checkout_succeeded.amount_usd) (NOT internal properties.cost_usd). Also verify a property lives on the event you query — properties.model is on BOTH ai_generation_metered AND ai_message_completed now. If a concept genuinely has NO matching event/property, do NOT silently substitute a plausible proxy — use mode=clarify: name the closest honest proxy by its TRUE definition AND state what is not tracked. If you proceed with a proxy, the title/reply must describe it in its own honest terms.";
sem _plan_query.question = "The user's natural-language question about their product metrics.";
sem _plan_query.context = "Three sections. SELECTED RANGE: the dashboard's current date window that picker-range metrics use. CATALOG: verified pre-built metrics, one per line as '- key: title — definition [shape]' — for mode=metrics, choose keys only from here. SCHEMA: the events-table columns, available events + props, and HogQL idioms (incl. TIME) — for mode=query, use only what appears here.";

# Prepare an LLM-generated query for safe execution: read-only, single statement,
# and — non-negotiable — inject the env filter (skipping it returns ~80% dev/preview
# noise). Prefer the {env} placeholder; fall back to injecting into the first WHERE.
def _prep_query_sql(sql: str, env: str) -> dict {
    s: str = sql.strip().rstrip(";").strip();
    low = s.lower();
    if not (low.startswith("select") or low.startswith("with")) {
        return {"ok": False, "error": "generated query was not a read-only SELECT/WITH"};
    }
    if ";" in s {
        return {"ok": False, "error": "generated query had more than one statement"};
    }
    envx = env_expr(env);
    if not envx {
        envx = "1=1";
    }
    if "{env}" in s {
        s = s.replace("{env}", envx);
    } elif " where " in (" " + low + " ") {
        idx = low.find(" where ");
        s = s[:idx] + " WHERE " + envx + " AND " + s[idx + 7:];
    } else {
        return {"ok": False, "error": "generated query had no WHERE clause to env-filter"};
    }
    # Whitespace/newline-agnostic: the LLM writes "...DESC\nLIMIT 20", so a literal
    # " limit " check misses it and appends a second LIMIT (ClickHouse honors the last →
    # "top 20" silently becomes 200). Match the keyword itself.
    if not re.search(r"(?i)\blimit\b", s) {
        s = s + " LIMIT 200";
    }
    return {"ok": True, "sql": s};
}

# Shape a raw HogQL result (columns + rows) into a tile-data object the client
# tiles already understand. table/bars read columns+rows; trends need an {x,y} series.
def _col_index(cols: list, name: str) -> int {
    i = 0;
    for c in cols {
        if str(c) == name {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

def _pct_delta(cur: any, prev: any) -> float | None {
    try {
        cf = float(str(cur));
        pf = float(str(prev));
        if pf == 0.0 {
            return None;
        }
        return (cf - pf) / pf * 100.0;
    } except Exception as e {
        return None;
    }
}

def _shape_ai_tile(res: dict, chart: str, date_from: str, date_to: str, env: str, q: str, good_up: bool) -> dict {
    cols = res.get("columns", []);
    rows = res.get("results", []);
    meta = {
        "definition": "Generated from your question: " + q,
        "window": f"{date_from} → {date_to}",
        "caveat": "AI-written query — not one of the verified tiles. Read as directional and check before acting. Env-filtered to the selection.",
        "env": env, "unit": "", "good_when_up": good_up, "cached": False
    };
    out: dict = {"value": None, "series": [], "columns": cols, "rows": rows, "prev": None, "delta": None, "meta": meta};
    rl = rows as list;
    if chart == "stat" or chart == "gauge" {
        if len(rl) > 0 {
            r0 = rl[0] as list;
            if len(r0) > 0 {
                out["value"] = r0[0];
            }
        }
    } elif chart == "compare" {
        if len(rl) > 0 {
            r0c = rl[0] as list;
            colslist = cols as list;
            ci = _col_index(colslist, "current_value");
            pi = _col_index(colslist, "previous_value");
            curv: any = None;
            prevv: any = None;
            if (ci >= 0) and (ci < len(r0c)) {
                curv = r0c[ci];
            } elif len(r0c) > 0 {
                curv = r0c[0];
            }
            if (pi >= 0) and (pi < len(r0c)) {
                prevv = r0c[pi];
            } elif len(r0c) >= 2 {
                prevv = r0c[1];
            }
            out["value"] = curv;
            out["prev"] = prevv;
            if (curv is not None) and (prevv is not None) {
                out["delta"] = _pct_delta(curv, prevv);
            }
        }
    } elif chart == "line" or chart == "area" or chart == "vbar" {
        series = [];
        for r in rl {
            rl2 = r as list;
            if len(rl2) >= 2 {
                series = series + [{"x": rl2[0], "y": rl2[1]}];
            }
        }
        out["series"] = series;
    }
    return out;
}

async def:priv ai_build(question: str, env: str, date_from: str, date_to: str) -> dict {
    if not ANTH_KEY {
        return {"answerable": False, "reply": "", "title": "", "tiles": [], "clarify": "AI planner unavailable — ANTHROPIC_API_KEY is not set on the server."};
    }
    q = question.strip();
    if not q {
        return {"answerable": False, "reply": "", "title": "", "tiles": [], "clarify": "Ask a question about your product metrics to build a view."};
    }
    env = _clamp_env(env);
    context = "SELECTED RANGE (what picker-range metrics use): " + date_from + " → " + date_to + "\n\nCATALOG:\n" + _catalog() + "\n\nSCHEMA:\n" + _SCHEMA_DOC;
    try {
        plan = await asyncio.to_thread(_plan_query, q, context);
    } except Exception as e {
        print("=== ai_build planner error ===");
        print(traceback.format_exc());
        return {"answerable": False, "reply": "", "title": "", "tiles": [], "clarify": "Planner error: " + str(e)[:140]};
    }
    # Observability: log every plan so we can see what byLLM chose and optimize it.
    print("[ai_build] mode=" + str(plan.mode) + " q=" + q[:90] + " keys=" + str(plan.keys) + " sql=" + str(plan.sql)[:200]);

    # ---- mode: metrics — reuse verified registry tiles (env-filter + cache for free) ----
    if plan.mode == "metrics" {
        valid: list[str] = [];
        for k in plan.keys {
            ks = str(k);
            if (ks in METRICS) and (ks not in valid) {
                valid = valid + [ks];
            }
            if len(valid) >= 6 {
                break;
            }
        }
        if len(valid) == 0 {
            return {"answerable": False, "reply": "", "title": str(plan.title), "tiles": [], "clarify": "I couldn't map that to the metrics we track. Try rephrasing, or ask for a specific list/breakdown."};
        }
        tasks = [];
        for ks in valid {
            tasks = tasks + [metric(ks, env, date_from, date_to, False)];
        }
        results = await asyncio.gather(*tasks);
        tiles = [];
        pk = [];
        i = 0;
        for ks in valid {
            m = METRICS[ks];
            ch = _tile_for(m);
            wlabel = m.window if m.window else (date_from + " → " + date_to);
            tiles = tiles + [{"key": ks, "title": m.title, "chart": ch, "data": results[i],
                "recipe": {"kind": "metric", "ref": ks, "title": m.title, "chart": ch, "good_up": m.good_when_up}}];
            pk = pk + [{"key": ks, "title": m.title, "window": wlabel}];
            i = i + 1;
        }
        return {"answerable": True, "reply": str(plan.reply), "title": str(plan.title), "tiles": tiles, "clarify": "",
            "plan": {"mode": "metrics", "reasoning": str(plan.reasoning), "metrics": pk, "sql": ""}};
    }

    # ---- mode: query — run the LLM's custom read-only HogQL (validated + env-injected) ----
    if plan.mode == "query" {
        prep = _prep_query_sql(str(plan.sql), env);
        if not prep["ok"] {
            return {"answerable": False, "reply": "", "title": str(plan.title), "tiles": [], "clarify": "I couldn't build a safe query for that (" + str(prep["error"]) + "). Try rephrasing.",
                "plan": {"mode": "query", "reasoning": str(plan.reasoning), "metrics": [], "sql": str(plan.sql)}};
        }
        res = await asyncio.to_thread(run_hogql, str(prep["sql"]));
        if "error" in res {
            return {"answerable": False, "reply": "", "title": str(plan.title), "tiles": [], "clarify": "The generated query failed to run: " + str(res["error"])[:140] + ". Try rephrasing.",
                "plan": {"mode": "query", "reasoning": str(plan.reasoning), "metrics": [], "sql": str(prep["sql"])}};
        }
        chart = str(plan.chart) if plan.chart else "table";
        data = _shape_ai_tile(res, chart, date_from, date_to, env, q, plan.good_up);
        ttl = str(plan.title) if plan.title else "Result";
        return {"answerable": True, "reply": str(plan.reply), "title": ttl, "clarify": "",
            "tiles": [{"key": "adhoc", "title": ttl, "chart": chart, "data": data,
                "recipe": {"kind": "query", "ref": str(plan.sql), "title": ttl, "chart": chart, "good_up": plan.good_up}}],
            "plan": {"mode": "query", "reasoning": str(plan.reasoning), "metrics": [], "sql": str(prep["sql"])}};
    }

    # ---- mode: clarify (or anything unrecognized) ----
    clar = str(plan.clarify) if plan.clarify else "Could you be more specific about what you'd like to see?";
    return {"answerable": False, "reply": "", "title": str(plan.title), "tiles": [], "clarify": clar,
        "plan": {"mode": "clarify", "reasoning": str(plan.reasoning), "metrics": [], "sql": ""}};
}

# ---------------------------------------------------------------------------
# Pinned dashboard — re-run saved "recipes" (a metric key OR a generated query)
# so a pinned tile always shows LIVE data for the current env/range, not a frozen
# snapshot. Recipes are produced by ai_build (tile.recipe) and stored client-side.
# ---------------------------------------------------------------------------

async def _run_pin(pin: dict, env: str, date_from: str, date_to: str) -> dict {
    kind = str(pin.get("kind", ""));
    title = str(pin.get("title", "Tile"));
    chart = str(pin.get("chart", "stat"));
    ref = str(pin.get("ref", ""));
    good_up = pin.get("good_up", True) as bool;
    if kind == "metric" {
        if ref not in METRICS {
            return {"title": title, "chart": chart, "data": {"value": None, "series": [], "columns": [], "rows": [], "error": "unknown metric '" + ref + "'", "meta": {}}};
        }
        m = METRICS[ref];
        data = await metric(ref, env, date_from, date_to, False);
        return {"title": title, "chart": _tile_for(m), "data": data};
    }
    if kind == "query" {
        prep = _prep_query_sql(ref, env);
        if not prep["ok"] {
            return {"title": title, "chart": chart, "data": {"value": None, "series": [], "columns": [], "rows": [], "error": str(prep["error"]), "meta": {}}};
        }
        res = await asyncio.to_thread(run_hogql, str(prep["sql"]));
        if "error" in res {
            return {"title": title, "chart": chart, "data": {"value": None, "series": [], "columns": [], "rows": [], "error": str(res["error"])[:140], "meta": {}}};
        }
        data = _shape_ai_tile(res, chart, date_from, date_to, env, title, good_up);
        return {"title": title, "chart": chart, "data": data};
    }
    return {"title": title, "chart": chart, "data": {"value": None, "series": [], "columns": [], "rows": [], "error": "unrecognized pin", "meta": {}}};
}

async def:priv run_pinned(pins: list, env: str, date_from: str, date_to: str) -> list {
    env = _clamp_env(env);
    if not (_valid_date(date_from) and _valid_date(date_to)) {
        return [];
    }
    tasks = [];
    for p in pins {
        tasks = tasks + [_run_pin(p as dict, env, date_from, date_to)];
    }
    if not tasks {
        return [];
    }
    results = await asyncio.gather(*tasks);
    return list(results);
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
