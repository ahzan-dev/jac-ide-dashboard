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
import time;
import secrets;
import asyncio;
import threading;
import traceback;
import requests;
import redis;
import from datetime { datetime, timedelta, timezone }
import from jaclang.byllm.lib { Model }

glob PH_KEY: str = os.environ.get("POSTHOG_API_KEY", "");
glob PH_HOST: str = os.environ.get("POSTHOG_HOST", "https://us.posthog.com");
glob PH_PROJECT: str = os.environ.get("POSTHOG_PROJECT_ID", "425465");
glob REDIS_URL: str = os.environ.get("REDIS_URL", "redis://localhost:6379");
glob CACHE_TTL: int = 600;          # freshness window
glob STALE_TTL: int = 86400;        # stale copies kept 24h — the always-loads fallback

# ---- PostHog API protection (rate limits + burst 504s are real) -------------
# One page load fans out ~20 HogQL calls; unmanaged concurrency 504s ClickHouse
# and unmanaged volume risks the documented per-minute/hour API limits.
glob PH_MAX_CONCURRENCY: int = int(os.environ.get("PH_MAX_CONCURRENCY", "5"));
glob PH_QPM: int = int(os.environ.get("PH_QPM", "60"));
glob _PH_GATE: any = threading.BoundedSemaphore(PH_MAX_CONCURRENCY);
glob _Q_LOCK: any = threading.Lock();
glob _Q_TIMES: list = [];           # sliding 60s window of query timestamps

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

def _cache_read(k: str) -> dict | None {
    if RDS is None {
        return None;
    }
    try {
        raw = RDS.get(k);
        if raw {
            return json.loads(str(raw)) as dict;
        }
    } except Exception {
        return None;
    }
    return None;
}

# Fresh hit only (within CACHE_TTL) — the normal fast path.
def _cache_get(k: str) -> dict | None {
    d = _cache_read(k);
    if d is None {
        return None;
    }
    fu = d.get("_fresh_until", 0.0);
    if time.time() > (fu as float) {
        return None;
    }
    d["meta"]["cached"] = True;
    return d;
}

# Any hit, however old (up to STALE_TTL) — the graphs-always-load fallback when
# PostHog is rate-limited or erroring. Labeled honestly via meta.
def _cache_get_stale(k: str) -> dict | None {
    d = _cache_read(k);
    if d is None {
        return None;
    }
    age_min = int((time.time() - ((d.get("_fresh_until", 0.0) as float) - CACHE_TTL)) / 60.0);
    meta = d.get("meta", {}) as dict;
    meta["cached"] = "stale";
    meta["caveat"] = ("STALE data (~" + str(age_min) + " min old) — PostHog was unavailable or "
        + "rate-limited; refresh to retry. " + str(meta.get("caveat", "")));
    d["meta"] = meta;
    return d;
}

# Stored with the LONG physical TTL; freshness is the embedded timestamp, so an
# expired-but-present entry can still serve as the stale fallback.
def _cache_put(k: str, val: dict) -> None {
    val["_fresh_until"] = time.time() + CACHE_TTL;
    if RDS is None {
        return;
    }
    try {
        RDS.setex(k, STALE_TTL, json.dumps(val));
    } except Exception {
        return;
    }
}

# ---------------------------------------------------------------------------
# Query runner (HogQL string OR native query kind)
# ---------------------------------------------------------------------------

# Sliding-window per-minute budget. Blocks briefly when the window is full
# (smooths a burst into the next seconds); gives up after ~8s so a saturated
# window degrades to the stale-cache path instead of hanging the request.
def _acquire_budget() -> bool {
    waited = 0.0;
    while True {
        _Q_LOCK.acquire();
        now = time.time();
        keep: list = [];
        for t in _Q_TIMES {
            if (now - (t as float)) < 60.0 {
                keep = keep + [t];
            }
        }
        _Q_TIMES.clear();
        for t in keep {
            _Q_TIMES.append(t);
        }
        ok = len(_Q_TIMES) < PH_QPM;
        if ok {
            _Q_TIMES.append(now);
        }
        _Q_LOCK.release();
        if ok {
            return True;
        }
        if waited >= 8.0 {
            return False;
        }
        time.sleep(0.4);
        waited = waited + 0.4;
    }
}

# All PostHog traffic goes through here: budget -> concurrency gate -> up to 3
# attempts with backoff on 429/5xx (honoring Retry-After when present).
def run_query(query_obj: dict) -> dict {
    if not PH_KEY {
        return {"error": "POSTHOG_API_KEY not set (server env)"};
    }
    if not _acquire_budget() {
        return {"error": "posthog query budget exhausted (>" + str(PH_QPM) + "/min) — stale cache shown where available"};
    }
    url = f"{PH_HOST}/api/projects/{PH_PROJECT}/query/";
    attempt = 0;
    last_err = "";
    while attempt < 3 {
        _PH_GATE.acquire();
        status = 0;
        body = "";
        try {
            resp = requests.post(
                url,
                headers={"Authorization": f"Bearer {PH_KEY}", "Content-Type": "application/json"},
                data=json.dumps({"query": query_obj}),
                timeout=20
            );
            status = resp.status_code;
            if status == 200 {
                d = resp.json();
                _PH_GATE.release();
                if d.get("error") {
                    return {"error": str(d.get("error"))};
                }
                return {"columns": d.get("columns", []), "results": d.get("results", [])};
            }
            body = str(resp.text)[:160];
            retry_after = 0.0;
            try {
                retry_after = float(resp.headers.get("Retry-After", "0"));
            } except Exception {
                retry_after = 0.0;
            }
        } except Exception as e {
            _PH_GATE.release();
            last_err = str(e);
            attempt = attempt + 1;
            if attempt < 3 {
                time.sleep(1.0 * attempt);
            }
            continue;
        }
        _PH_GATE.release();
        last_err = f"posthog http {status}: {body}";
        # retry only what can heal: rate-limit + server-side blips
        if (status == 429) or (status >= 500) {
            attempt = attempt + 1;
            if attempt < 3 {
                backoff = retry_after if retry_after > 0.0 else (1.5 * attempt);
                if backoff > 6.0 {
                    backoff = 6.0;
                }
                time.sleep(backoff);
            }
            continue;
        }
        return {"error": last_err};
    }
    return {"error": last_err};
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
        caveat="Live, but low-volume so far — most users never click 👍/👎, so read as directional.",
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
        
        sql="SELECT round(sum(toFloat64OrNull(toString(properties.cost_usd))),2) FROM events WHERE event='ai_generation_metered' {env_filter} " + _RANGE
    ),
    "cost_per_request": Metric(
        key="cost_per_request", title="Cost per AI request", unit="$",
        definition="Average dollar cost of one AI request.",
        
        sql="SELECT round(avg(toFloat64OrNull(toString(properties.cost_usd))),4) FROM events WHERE event='ai_generation_metered' {env_filter} " + _RANGE
    ),
    "cost_per_user": Metric(
        key="cost_per_user", title="Cost per active user", unit="$",
        definition="Average dollar cost per user who generated AI usage.",
        
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
        caveat="Live, but very few users use the in-app report button — see the Issues & friction log for the full picture.",
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
        caveat="Counts deploy outcome events (succeeded vs failed); clicks that never produce an outcome are not in the denominator.",
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
        
        sql="SELECT round(100.0*countIf(t1_done AND max_turn=1)/nullIf(count(),0),1) FROM (SELECT toString(properties.conversation_id) cid, max(toFloat64OrNull(toString(properties.turn_number))) max_turn, countIf(event='ai_message_completed' AND toFloat64OrNull(toString(properties.turn_number))=1)>0 t1_done FROM events WHERE event IN ('ai_message_sent','ai_message_completed') {env_filter} " + _RANGE + " GROUP BY cid HAVING cid != '')"
    ),
    "model_latency": Metric(
        key="model_latency", title="Response time by model", shape="rows", unit="s", good_when_up=False,
        definition="Typical AI response time, broken down by the model that actually ran each request.",
        
        sql="SELECT toString(properties.model) model, round(median(toFloat64OrNull(toString(properties.duration_ms)))/1000,1) v FROM events WHERE event='ai_message_completed' AND coalesce(toString(properties.model),'')!='' {env_filter} " + _RANGE + " GROUP BY model ORDER BY v DESC LIMIT 20"
    ),
    "model_usage": Metric(
        key="model_usage", title="AI requests by model", shape="rows", unit="",
        definition="How many AI requests actually ran on each model — the true usage breakdown (distinct from model_mix, which counts manual switches).",
        
        sql="SELECT coalesce(nullIf(toString(properties.model),''),'unknown') model, count() n FROM events WHERE event='ai_message_completed' AND coalesce(toString(properties.model),'')!='' {env_filter} " + _RANGE + " GROUP BY model ORDER BY n DESC LIMIT 8"
    ),
    "acquisition_channel": Metric(
        key="acquisition_channel", title="Signups by channel", shape="rows", unit="",
        definition="Where new signups came from, by first-touch UTM source (no source shows as 'direct').",
        caveat="First-touch attribution; empty source = direct/no campaign.",
        sql="SELECT if(coalesce(toString(properties.utm_source),'')='','direct',toString(properties.utm_source)) src, count() n FROM events WHERE event='auth_signup_succeeded' {env_filter} " + _RANGE + " GROUP BY src ORDER BY n DESC LIMIT 20"
    ),
    "signup_trigger_breakdown": Metric(
        key="signup_trigger_breakdown", title="Signups by trigger", shape="rows", unit="",
        definition="Which in-app gate or CTA drove each signup (guest locked feature, dashboard prompt, free-credit bonus, or direct).",
        
        sql="SELECT coalesce(nullIf(toString(properties.signup_trigger),''),'direct') trigger, count() n FROM events WHERE event='auth_signup_succeeded' {env_filter} " + _RANGE + " GROUP BY trigger ORDER BY n DESC LIMIT 10"
    ),
    "ai_edits": Metric(
        key="ai_edits", title="AI outputs manually edited", unit="", good_when_up=False,
        definition="How many times users manually edited a file the AI had just written — the real 'did they accept it' signal.",
        caveat="A manual edit of AI-written code — the honest acceptance signal.",
        sql="SELECT count() FROM events WHERE event='ai_response_edited' {env_filter} " + _RANGE
    ),
    "session_depth": Metric(
        key="session_depth", title="Typical session length", unit="min",
        definition="Median focused (active-tab) time users spend in the IDE per session.",
        caveat="Focused (active-tab) time, not wall-clock.",
        sql="SELECT round(median(toFloat64OrNull(toString(properties.duration_active_ms)))/60000,1) FROM events WHERE event='ide_session_ended' {env_filter} " + _RANGE
    ),

    # ---- entity drill-downs (promoted from the 2026-07-26 hackathon report;
    # spec §4 G2 — the report/Ask layer reuses these instead of hand-written SQL).
    # Identity rule: person-merged (person_id), email with an 'anon:' fallback.
    "user_rollup": Metric(
        key="user_rollup", title="Per-user activity", shape="rows",
        definition="One row per active user: signups, projects, AI turns, failures, metered cost, previews, deploys, GitHub, upgrades — the who-did-what table.",
        caveat="'anon:' rows are devices that never signed in. Cost is platform-metered $ (BYOK runs bill the user's own key).",
        sql="SELECT coalesce(nullIf(toString(any(person.properties.email)),''), nullIf(toString(any(person.properties.display_name)),''), nullIf(toString(any(person.properties.name)),''), concat('anon:', substring(toString(person_id),1,8))) user, countIf(event='auth_signup_succeeded') signed_up, countIf(event='project_created') projects, countIf(event='ai_message_sent') ai_turns, countIf(event='ai_message_failed') ai_failed, round(sumIf(toFloat64OrNull(toString(properties.cost_usd)), event='ai_generation_metered'),2) cost_usd, countIf(event='ai_generation_metered' AND toString(properties.byok)='true') byok_runs, countIf(event='preview_ready') previews, countIf(event='deploy_sandbox_succeeded') sbx_ok, countIf(event='deploy_sandbox_failed') sbx_fail, countIf(event='deploy_production_succeeded') prod_ok, countIf(event='github_connect_succeeded') gh_ok, countIf(event='upgrade_checkout_succeeded') upgraded FROM events WHERE event IN ('auth_signup_succeeded','project_created','ai_message_sent','ai_message_failed','ai_generation_metered','preview_ready','deploy_sandbox_succeeded','deploy_sandbox_failed','deploy_production_succeeded','github_connect_succeeded','upgrade_checkout_succeeded') {env_filter} " + _RANGE + " GROUP BY person_id ORDER BY ai_turns DESC, cost_usd DESC LIMIT 200"
    ),
    "signups_detail": Metric(
        key="signups_detail", title="Signups (row level)", shape="rows",
        definition="Every signup in the window: time, email, method, in-app trigger, and UTM source.",
        caveat="Signups fire server-side (auth_signup_succeeded) — do NOT count logins (auth_succeeded) as signups; its is_new_user flag is unreliable (TRACKING_GAPS D-17).",
        sql="SELECT substring(toString(timestamp),1,16) ts, coalesce(nullIf(toString(person.properties.email),''), nullIf(toString(person.properties.display_name),''), nullIf(toString(person.properties.name),''), concat('anon:', substring(toString(person_id),1,8))) user, coalesce(toString(properties.method),'') method, coalesce(toString(properties.signup_trigger),'') trigger, coalesce(toString(properties.utm_source),'') utm_source FROM events WHERE event='auth_signup_succeeded' {env_filter} " + _RANGE + " ORDER BY timestamp LIMIT 300"
    ),
    "cost_per_turn": Metric(
        key="cost_per_turn", title="AI cost per run", shape="rows",
        definition="Every metered AI generation run: time, user, model, dollar cost, key type (platform vs BYOK), and project.",
        caveat="Per-entity sums of this table MUST reconcile to total_spend to the cent — a mismatch means rows were dropped, not a rounding issue.",
        sql="SELECT substring(toString(timestamp),1,16) ts, coalesce(nullIf(toString(person.properties.email),''), nullIf(toString(person.properties.display_name),''), nullIf(toString(person.properties.name),''), concat('anon:', substring(toString(person_id),1,8))) user, coalesce(nullIf(toString(properties.model),''),'(blank)') model, round(toFloat64OrNull(toString(properties.cost_usd)),4) cost_usd, if(toString(properties.byok)='true','byok','platform') key_type, coalesce(toString(properties.project_id),'') project_id FROM events WHERE event='ai_generation_metered' {env_filter} " + _RANGE + " ORDER BY timestamp LIMIT 500"
    ),
    "cost_by_model": Metric(
        key="cost_by_model", title="Cost by model", shape="rows",
        definition="Metered AI spend broken down by the model that ran: runs, users, total/avg/max dollars, and the BYOK share.",
        caveat="A '(blank)' model row is real spend with a missing model property — an instrumentation gap, not a rounding artifact.",
        sql="SELECT coalesce(nullIf(toString(properties.model),''),'(blank)') model, count() runs, uniq(person_id) users, round(sum(toFloat64OrNull(toString(properties.cost_usd))),2) total_usd, round(avg(toFloat64OrNull(toString(properties.cost_usd))),4) avg_usd, round(max(toFloat64OrNull(toString(properties.cost_usd))),2) max_usd, countIf(toString(properties.byok)='true') byok_runs FROM events WHERE event='ai_generation_metered' {env_filter} " + _RANGE + " GROUP BY model ORDER BY total_usd DESC LIMIT 20"
    ),
    "project_cost_rollup": Metric(
        key="project_cost_rollup", title="Cost by project", shape="rows",
        definition="Metered AI spend per project: owner, runs, total dollars, and which models ran.",
        caveat="Joins on the project_id stamped on AI events — projects with zero AI runs don't appear (project_created carries no project_id).",
        sql="SELECT coalesce(nullIf(toString(properties.project_id),''),'(none)') project_id, coalesce(nullIf(toString(any(person.properties.email)),''), nullIf(toString(any(person.properties.display_name)),''), nullIf(toString(any(person.properties.name)),''), concat('anon:', substring(toString(any(person_id)),1,8))) owner, count() runs, round(sum(toFloat64OrNull(toString(properties.cost_usd))),2) total_usd, arrayStringConcat(groupUniqArray(coalesce(nullIf(toString(properties.model),''),'(blank)')), ', ') models FROM events WHERE event='ai_generation_metered' {env_filter} " + _RANGE + " GROUP BY project_id ORDER BY total_usd DESC LIMIT 100"
    ),
    "byok_split": Metric(
        key="byok_split", title="BYOK vs platform keys", shape="rows",
        definition="Metered AI runs split by key type: platform-billed vs the user's own key (BYOK), with runs, users, and dollars each.",
        caveat="BYOK dollar figures are what the USER'S key was billed, not platform spend.",
        sql="SELECT if(toString(properties.byok)='true','BYOK (user key)','Platform key') key_type, count() runs, uniq(person_id) users, round(sum(toFloat64OrNull(toString(properties.cost_usd))),2) total_usd FROM events WHERE event='ai_generation_metered' {env_filter} " + _RANGE + " GROUP BY key_type ORDER BY runs DESC"
    ),
    "upgrades_detail": Metric(
        key="upgrades_detail", title="Completed upgrades (row level)", shape="rows",
        definition="Every completed paid upgrade: time, user, from→to plan, interval, and the actual checkout amount.",
        caveat="amount_usd is the real checkout value — compute revenue from it, never from list prices.",
        sql="SELECT substring(toString(timestamp),1,16) ts, coalesce(nullIf(toString(person.properties.email),''), nullIf(toString(person.properties.display_name),''), nullIf(toString(person.properties.name),''), concat('anon:', substring(toString(person_id),1,8))) user, coalesce(toString(properties.plan_from),'') plan_from, coalesce(toString(properties.plan),'') plan, coalesce(toString(properties.interval),'') billing_interval, round(toFloat64OrNull(toString(properties.amount_usd)),2) amount_usd, toString(properties.is_first_upgrade) first_upgrade FROM events WHERE event='upgrade_checkout_succeeded' {env_filter} " + _RANGE + " ORDER BY timestamp LIMIT 200"
    ),
    "deploy_outcomes": Metric(
        key="deploy_outcomes", title="Deploy outcomes", shape="rows",
        definition="Sandbox vs production deploys: clicks, successes, and failures — each as both event counts and unique users.",
        caveat="Events and users differ (one user can retry many times) — read the users columns for adoption, the counts for friction.",
        sql="SELECT if(event LIKE 'deploy_sandbox%','Sandbox','Production') kind, countIf(event IN ('deploy_sandbox_clicked','deploy_production_clicked')) clicks, uniqIf(person_id, event IN ('deploy_sandbox_clicked','deploy_production_clicked')) users_clicked, countIf(event IN ('deploy_sandbox_succeeded','deploy_production_succeeded')) succeeded, uniqIf(person_id, event IN ('deploy_sandbox_succeeded','deploy_production_succeeded')) users_ok, countIf(event IN ('deploy_sandbox_failed','deploy_production_failed')) failed, uniqIf(person_id, event IN ('deploy_sandbox_failed','deploy_production_failed')) users_failed FROM events WHERE event IN ('deploy_sandbox_clicked','deploy_sandbox_succeeded','deploy_sandbox_failed','deploy_production_clicked','deploy_production_succeeded','deploy_production_failed') {env_filter} " + _RANGE + " GROUP BY kind ORDER BY clicks DESC"
    ),
    "user_model_cost_matrix": Metric(
        key="user_model_cost_matrix", title="Cost per user × model", shape="composite",
        definition="Each user's metered AI spend broken down by model — one column per model, ranked by total spend.",
        caveat="Pivot of the per-run cost rows; row totals reconcile to total_spend. Blank cells = the user never ran that model.",
        sql="COMPOSITE:cost_per_turn"
    ),
    "project_sources": Metric(
        key="project_sources", title="How projects start", shape="rows",
        definition="How users started their projects: from a prompt, a template, a GitHub import, or a folder upload.",
        caveat="Reads properties.source — template_id is a scaffold artifact ('empty' even on prompt-started projects) and must never be used for this breakdown.",
        sql="SELECT coalesce(nullIf(toString(properties.source),''),'unknown') source, count() n FROM events WHERE event='project_created' {env_filter} " + _RANGE + " GROUP BY source ORDER BY n DESC"
    ),
    "issue_log": Metric(
        key="issue_log", title="Issues & friction log", shape="rows", good_when_up=False,
        definition="Everything that went wrong, across all failure families: AI failures, quota blocks, preview/deploy/GitHub/checkout failures, and user-aborted turns — with who hit each.",
        caveat="This is the honest issues source — ai_issue_reported alone (the in-app report button) massively undercounts friction.",
        sql="SELECT multiIf(event='ai_message_failed','AI generation failed', event='ai_message_blocked_quota','Blocked by quota', event='preview_start_failed','Preview failed', event='deploy_sandbox_failed','Sandbox deploy failed', event='deploy_production_failed','Production deploy failed', event='github_connect_failed','GitHub connect failed', event='upgrade_checkout_failed','Upgrade checkout failed', event='ai_user_aborted','User aborted AI turn', event='ai_issue_reported','Issue reported in-app', event) issue, count() n, uniq(person_id) users, arrayStringConcat(arraySlice(groupUniqArray(coalesce(nullIf(toString(person.properties.email),''), nullIf(toString(person.properties.display_name),''), nullIf(toString(person.properties.name),''), concat('anon:', substring(toString(person_id),1,8)))),1,6), ', ') who FROM events WHERE event IN ('ai_message_failed','ai_message_blocked_quota','preview_start_failed','deploy_sandbox_failed','deploy_production_failed','github_connect_failed','upgrade_checkout_failed','ai_user_aborted','ai_issue_reported') {env_filter} " + _RANGE + " GROUP BY issue ORDER BY n DESC"
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

# Accept a bare date OR a datetime ("YYYY-MM-DD[ T]HH:MM[:SS]") so sub-day windows
# (a hackathon, an incident, a launch hour) are first-class. Returns None if invalid.
def _parse_dt(s: str) -> datetime | None {
    t = s.strip().replace("T", " ");
    for fmt in ["%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"] {
        try {
            return datetime.strptime(t, fmt);
        } except Exception {
            continue;
        }
    }
    return None;
}

# Canonical form injected into toDateTime('{from}') — always full seconds precision.
def _norm_dt(d: datetime) -> str {
    return d.strftime("%Y-%m-%d %H:%M:%S");
}

# Adaptive time bucket for trend series so a chart always has a sensible number of points
# regardless of the selected range: 15-min/hourly for sub-day windows, daily for short
# ranges, weekly for medium, monthly for long. (Single-arg functions only — the SQL
# templates apply the bucket as `{bkt}(timestamp)`.)
def _bucket_span(seconds: float) -> str {
    if seconds <= 12 * 3600 {
        return "toStartOfFifteenMinutes";
    }
    if seconds <= 3 * 86400 {
        return "toStartOfHour";
    }
    if seconds <= 31 * 86400 {
        return "toDate";
    }
    if seconds <= 186 * 86400 {
        return "toStartOfWeek";
    }
    return "toStartOfMonth";
}

def _bucket(days: int) -> str {
    return _bucket_span(days * 86400.0);
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
    dfrom = _parse_dt(date_from);
    dto = _parse_dt(date_to);
    if (dfrom is None) or (dto is None) or (dto <= dfrom) {
        return {"value": None, "error": "bad date range", "meta": {}};
    }
    span_s = (dto - dfrom).total_seconds();
    range_days = int(span_s / 86400.0);
    if range_days < 1 {
        range_days = 1;
    }
    bkt = _bucket_span(span_s);
    date_from = _norm_dt(dfrom);
    date_to = _norm_dt(dto);

    sub_day = span_s < 86400.0;
    span_label = f"{round(span_s / 3600.0, 1)}h" if sub_day else f"{range_days}d";
    window_label = m.window if m.window else f"{date_from} → {date_to} ({span_label})";
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

    res = await _run_metric(m, out, env, range_days, date_from, date_to, bkt, ck);
    # Graphs must always load: on any PostHog failure, fall back to the last
    # known result (up to 24h old) with an honest STALE label.
    if res.get("error") {
        stale = _cache_get_stale(ck);
        if stale is not None {
            return stale;
        }
    }
    return res;
}

# Live "N events in scope" for the sticky filter bar — makes the active
# env + range slice tangible (redesign plan P3).
async def:priv scope_count(env: str, date_from: str, date_to: str) -> dict {
    env = _clamp_env(env);
    df = _parse_dt(date_from);
    dt_ = _parse_dt(date_to);
    if (df is None) or (dt_ is None) {
        return {"n": None};
    }
    sql = ("SELECT count() FROM events WHERE true " + env_filter(env)
        + " AND timestamp >= toDateTime('" + _norm_dt(df) + "')"
        + " AND timestamp < toDateTime('" + _norm_dt(dt_) + "')");
    res = await asyncio.to_thread(run_hogql, sql);
    if "error" in res {
        return {"n": None};
    }
    return {"n": _scalar(res["results"] as list)};
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
    "peak_hours": "vbar", "requests_daily": "vbar",
    # entity drill-downs are multi-column tables, never hbars
    "user_rollup": "table", "signups_detail": "table", "cost_per_turn": "table",
    "cost_by_model": "table", "project_cost_rollup": "table", "byok_split": "table",
    "upgrades_detail": "table", "deploy_outcomes": "table", "issue_log": "table",
    "user_model_cost_matrix": "table"
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
    + "AGGREGATION — the #1 cause of failed queries is a CASE without ELSE. RULES: (a) NEVER write 'CASE WHEN cond THEN x END' without an ELSE (HogQL compiles it to a multiIf that PostHog rejects). (b) For a CONDITIONAL or per-category count/sum, use countIf(cond) / sumIf(cond, x) — e.g. to split deploys by type: SELECT person_id, countIf(event='deploy_production_succeeded') AS prod, countIf(event='deploy_sandbox_succeeded') AS sandbox FROM events WHERE {env} AND event IN ('deploy_production_succeeded','deploy_sandbox_succeeded') GROUP BY person_id. Use CASE ONLY to bucket a value into named ranges, and then it MUST end with 'ELSE <fallback>' (e.g. CASE WHEN n=0 THEN '0' WHEN n<=5 THEN '1-5' ELSE '6+' END). (c) For 'how many events per user' after GROUP BY person_id use count() — NEVER COUNT(DISTINCT person_id) (always 1 within a person's group). Count distinct USERS only WITHOUT grouping by person_id: count(DISTINCT person_id). So 'list users who did X' = SELECT person_id, count() AS n FROM events WHERE {env} AND event IN (...) GROUP BY person_id ORDER BY n DESC.\n"
    + "TIME (HogQL, evaluated by ClickHouse — no date math needed): today = toDate(timestamp) = today() ; yesterday = toDate(timestamp) = yesterday() ; this week = timestamp >= toStartOfWeek(now()) ; this month = timestamp >= toStartOfMonth(now()) ; last N days = timestamp >= now() - INTERVAL N DAY ; a specific date = toDate(timestamp) = toDate('YYYY-MM-DD') ; weekday = toDayOfWeek(timestamp) (1=Mon..7=Sun — do NOT use formatDateTime('%A')) ; hour of day = toHour(timestamp) ; day bucket for trends = toDate(timestamp).\n"
    + "ALWAYS put the literal placeholder {env} in the main WHERE, e.g. WHERE {env} AND event='ai_message_sent'. The server replaces {env} with the production environment filter.\n"
    + "CORE events (name — key props):\n"
    + "auth_signup_succeeded (method — password/google/github; signup_trigger — guest_locked_feature/free_signup_bonus/dashboard_prompt/direct; NO 'provider' property) · auth_succeeded (method, is_new_user) · ide_opened · ide_session_ended (duration_active_ms — FOCUSED time not wall-clock; files_touched; previews_run; ended_reason) · project_created (source)\n"
    + "ai_message_sent (prompt_length, attached_files_count, task_category, model, conversation_id, turn_number) · ai_message_completed (duration_ms, files_changed, response_length, model, conversation_id, turn_number, message_id) · ai_message_failed (reason, at_phase, duration_ms, model, conversation_id, turn_number) · ai_message_reverted (conversation_id, turn_number) · ai_response_rated (rating up/down, message_id) · ai_issue_reported (category, message_id) · ai_response_edited (message_id, time_to_edit_ms, files_changed — a manual edit of AI-written code = the real acceptance signal)\n"
    + "AI THREADING: conversation_id + turn_number link a chat thread — first-try success = turn_number=1 with an ai_message_completed and no later turn in the same conversation_id. properties.model is the model that ACTUALLY ran (now on ai_message_completed, not only ai_generation_metered).\n"
    + "preview_start_requested (was_prepared) · preview_ready (duration_ms) · preview_start_failed (reason)\n"
    + "deploy_sandbox_clicked · deploy_sandbox_succeeded (status) · deploy_production_clicked · deploy_production_succeeded (status)\n"
    + "git_commit_succeeded · github_connect_succeeded · project_shared · export_downloaded\n"
    + "ai_generation_metered (cost_usd, model, project_id) · upgrade_checkout_clicked (plan — INTENT only) · upgrade_checkout_succeeded (plan, plan_from, amount_usd, interval, is_first_upgrade, stripe_customer_id — the COMPLETED upgrade; paid conversion = succeeded/clicked) · subscription_canceled (plan_from, mrr_delta, days_active) · subscription_downgraded (plan_from, plan_to, mrr_delta) · topup_checkout_clicked (pack)\n"
    + "REVENUE: MRR-from-events = SUM over upgrade_checkout_succeeded.amount_usd minus churned; but the authoritative live MRR is Stripe (billing summary: mrr, active_subs) — properties.cost_usd is internal COST, never revenue.\n"
    + "SESSIONS: properties.$session_id groups events into one browser session (a rough session-length proxy); ide_session_ended.duration_active_ms is the real focused time per IDE session.\n"
    + "Person/event props for identity: properties.email, properties.display_name, properties.name, properties.plan (free/builder/pro). properties.method on auth_signup_succeeded is the LOGIN method (password/google/github) — NOT a marketing channel. properties.provider / properties.auth_provider do NOT exist.\n"
    + "ACQUISITION CHANNEL: first-touch UTM/referrer are captured. On CLIENT events they ride as super-properties (properties.utm_source/utm_medium/utm_campaign/utm_content/referrer/initial_referring_domain/landing_path); they are ALSO threaded explicitly onto the server-emitted auth_signup_succeeded, so channel attribution for SIGNUPS must read utm_* off auth_signup_succeeded (empty = direct/no campaign). Use these (NOT login method) for channel/campaign attribution.\n"
    + "PRIVACY: by default prompt/message TEXT is NOT stored on the core events. EXCEPTION: when transcript capture is enabled, the ai_turn_transcript event carries properties.prompt (user's message) + properties.response (AI's final reply) + message_id (joins to ai_message_completed) — the raw material for per-user satisfaction analysis. It stores ONLY prompt+reply, never the intermediate steps. Do not expect content on any other event.\n"
    + "CONVERSATIONS: ai_turn_transcript ALSO carries properties.conversation_id (groups a user's turns into one chat thread), properties.turn_number (1-based order within that thread), properties.model, properties.project_id, properties.files_changed (a COUNT) and properties.is_error. So conversation shape is answerable from this event alone — e.g. turns per conversation = count() GROUP BY conversation_id; no join to ai_message_completed needed. conversation_id/turn_number/model are on ai_message_sent + ai_message_completed too. CAVEAT: ai_turn_transcript is opt-in (JAC_STORE_AI_TRANSCRIPTS) and currently returns ZERO rows in every environment — if a question needs it, say so rather than reporting 0 as an answer.\n"
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

# ---------------------------------------------------------------------------
# Search history — per-user (def:priv runs against the caller's root, so each
# user's searches are isolated). Every answered question is upserted with its
# headline value + timestamp, so a re-run can show "what changed", and recent
# questions drive the dynamic suggestion chips.
# ---------------------------------------------------------------------------

node SearchEntry {
    has question: str;
    has last_value: float | None = None;   # comparable headline of the last result
    has last_kind: str = "none";           # "value" (scalar) | "rows" (row count) | "none"
    has last_ts: str = "";                 # "YYYY-MM-DD HH:MM" UTC
    has run_count: int = 0;
}

# The single comparable number for a result: first scalar value, else row count.
def _result_headline(tiles: list) -> dict {
    if not tiles {
        return {"value": None, "kind": "none"};
    }
    t0 = (tiles as list)[0] as dict;
    d = t0.get("data", {}) as dict;
    v = d.get("value");
    if v is not None {
        try {
            return {"value": float(str(v)), "kind": "value"};
        } except Exception as e {
            return {"value": None, "kind": "none"};
        }
    }
    rows = d.get("rows", []);
    if rows and isinstance(rows, list) {
        return {"value": float(len(rows as list)), "kind": "rows"};
    }
    return {"value": None, "kind": "none"};
}

# Upsert this question's entry; return the PREVIOUS headline (+ the new one) so the
# client can render "was X → now Y".
def _save_search(question: str, value: any, kind: str) -> dict {
    q = question.strip();
    fval: float | None = None;
    if value is not None {
        try {
            fval = float(str(value));
        } except Exception as e {
            fval = None;
        }
    }
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M");
    for e in [root -->][?:SearchEntry] {
        if e.question == q {
            prev_v = e.last_value;
            prev_ts = e.last_ts;
            e.last_value = fval;
            e.last_kind = kind;
            e.last_ts = now;
            e.run_count = e.run_count + 1;
            return {"prev_value": prev_v, "prev_ts": prev_ts, "new_value": fval, "kind": kind, "is_new": False, "run_count": e.run_count};
        }
    }
    root ++> SearchEntry(question=q, last_value=fval, last_kind=kind, last_ts=now, run_count=1);
    return {"prev_value": None, "prev_ts": "", "new_value": fval, "kind": kind, "is_new": True, "run_count": 1};
}

# The user's saved searches, newest first — drives the "Recent" chips + history list.
def:priv search_history() -> list {
    out: list[dict] = [];
    for e in [root -->][?:SearchEntry] {
        out = out + [{"question": e.question, "last_value": e.last_value, "last_kind": e.last_kind, "last_ts": e.last_ts, "run_count": e.run_count}];
    }
    out.sort(key=lambda (r: dict) { str(r["last_ts"]); }, reverse=True);
    return out;
}

# "What to explore next", tiered like a product owner thinks — drill into what they
# see AND surface blind spots. From a 'signups' search: ~25% deeper, ~25% adjacent,
# ~50% entirely different product areas they haven't touched. (byLLM, ≤2 params.)
obj Suggestions {
    has deeper: list[str] = [];
    has related: list[str] = [];
    has different: list[str] = [];
}
sem Suggestions = "Next analytics questions to explore, tiered from drill-down to blind-spot discovery.";
sem Suggestions.deeper = "Exactly 3 drill-downs / close variants of the user's MOST RECENT topic — a breakdown, a comparison, or a time-scoped version of the same thing.";
sem Suggestions.related = "Exactly 3 questions one step ADJACENT to that topic — a neighboring metric that adds context (e.g. from signups → activation, retention).";
sem Suggestions.different = "Exactly 6 questions about COMPLETELY DIFFERENT areas of the product the user has NOT asked about — deliberate blind-spot coverage. If they only looked at signups, span AI quality, response latency, cost/spend, feature adoption, preview reliability, deploys, revenue, etc.";

def _suggest_next(recent: str, catalog: str) -> Suggestions by INSIGHT_LLM(max_tokens=650);
sem _suggest_next = "You are an analytics guide for a PRODUCT OWNER of an AI web-IDE. Given their RECENT questions and the metrics CATALOG, propose what to explore next in THREE tiers so they both go deep and discover blind spots: deeper = 3 drill-downs on their most recent topic; related = 3 adjacent metrics one step away; different = 6 questions about ENTIRELY DIFFERENT product areas they have NOT asked about (the biggest tier on purpose — a good product owner needs reminding of the areas they're neglecting, not just more of what they're already looking at). Each question <= 8 words, natural (as a user would type), answerable from the catalog/events, and NEVER a repeat of their recent questions. Spread 'different' across distinct areas — don't cluster.";
sem _suggest_next.recent = "The user's recent questions, newest first, one per line.";
sem _suggest_next.catalog = "Available metrics, one per line.";

async def:priv suggest_next() -> dict {
    empty = {"deeper": [], "related": [], "different": []};
    if not ANTH_KEY {
        return empty;
    }
    recents: list[dict] = [];
    for e in [root -->][?:SearchEntry] {
        recents = recents + [{"q": e.question, "ts": e.last_ts}];
    }
    if len(recents) == 0 {
        return empty;
    }
    recents.sort(key=lambda (r: dict) { str(r["ts"]); }, reverse=True);
    lines = [];
    i = 0;
    for r in recents {
        if i < 8 {
            lines = lines + [str(r["q"])];
            i = i + 1;
        }
    }
    try {
        s = await asyncio.to_thread(_suggest_next, "\n".join(lines), _catalog());
        return {"deeper": list(s.deeper), "related": list(s.related), "different": list(s.different)};
    } except Exception as e {
        return empty;
    }
}

# ---------------------------------------------------------------------------
# Conversation threads — per-user (def:priv → caller's root). Each thread stores
# the RENDERED messages as a snapshot (frozen numbers, like a chat log), so
# reopening shows exactly what was said, not a live re-run.
# ---------------------------------------------------------------------------

node Thread {
    has title: str = "New chat";
    has created_at: str = "";
    has updated_at: str = "";
    has messages: list = [];       # the client's message dicts (role/text/tiles/plan/changed)
}

def:priv thread_list() -> list {
    out: list[dict] = [];
    for t in [root -->][?:Thread] {
        out = out + [{"id": jid(t), "title": t.title, "updated_at": t.updated_at, "count": len(t.messages)}];
    }
    out.sort(key=lambda (r: dict) { str(r["updated_at"]); }, reverse=True);
    return out;
}

def:priv thread_get(thread_id: str) -> dict {
    for t in [root -->][?:Thread] {
        if jid(t) == thread_id {
            return {"id": jid(t), "title": t.title, "messages": t.messages};
        }
    }
    return {"id": "", "title": "", "messages": []};
}

# Upsert: create when thread_id is empty (returns the new id), else update in place.
def:priv thread_save(thread_id: str, title: str, messages: list) -> dict {
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M");
    ttl = title if title else "New chat";
    if thread_id {
        for t in [root -->][?:Thread] {
            if jid(t) == thread_id {
                t.messages = messages;
                t.updated_at = now;
                t.title = ttl;
                return {"id": jid(t)};
            }
        }
    }
    nt = Thread(title=ttl, created_at=now, updated_at=now, messages=messages);
    root ++> nt;
    return {"id": jid(nt)};
}

def:priv thread_delete(thread_id: str) -> bool {
    for t in [root -->][?:Thread] {
        if jid(t) == thread_id {
            del t;
            return True;
        }
    }
    return False;
}

# ---- pinned tiles + saved views: per-user graph (was browser localStorage) --
# A Pin stores a RECIPE ({id, kind, ref, title, chart, good_up} — a metric key or
# generated SQL), re-run live by run_pinned; a SavedView stores a {page, env, date
# range} bookmark. Both hang off the user's root (def:priv) so they persist per
# account across browsers, exactly like Thread.
node Pin {
    has data: dict = {};
}
node SavedView {
    has data: dict = {};
}

def:priv pin_list() -> list {
    out: list[dict] = [];
    for p in [root -->][?:Pin] {
        out = out + [p.data];
    }
    return out;
}

# Add a recipe (deduped by kind+ref). Returns the full list.
def:priv pin_add(recipe: dict) -> list {
    kind = str(recipe["kind"]);
    ref = str(recipe["ref"]);
    for p in [root -->][?:Pin] {
        d = p.data;
        if (str(d["kind"]) == kind) and (str(d["ref"]) == ref) {
            return pin_list();
        }
    }
    gu = True;
    if "good_up" in recipe {
        gu = recipe["good_up"] as bool;
    }
    item = {"id": kind + "::" + ref, "kind": kind, "ref": ref,
            "title": str(recipe["title"]), "chart": str(recipe["chart"]), "good_up": gu};
    root ++> Pin(data=item);
    return pin_list();
}

def:priv pin_remove(pin_id: str) -> list {
    victims: list = [];
    for p in [root -->][?:Pin] {
        if str((p.data)["id"]) == pin_id {
            victims = victims + [p];
        }
    }
    for v in victims {
        del v;
    }
    return pin_list();
}

def:priv view_list() -> list {
    out: list[dict] = [];
    for v in [root -->][?:SavedView] {
        d = v.data;
        out = out + [{"id": jid(v), "name": str(d["name"]), "page": str(d["page"]),
                      "env": str(d["env"]), "from": str(d["from"]), "to": str(d["to"])}];
    }
    return out;
}

def:priv view_add(view: dict) -> list {
    item = {"name": str(view["name"]), "page": str(view["page"]), "env": str(view["env"]),
            "from": str(view["from"]), "to": str(view["to"])};
    root ++> SavedView(data=item);
    return view_list();
}

def:priv view_remove(view_id: str) -> list {
    victims: list = [];
    for v in [root -->][?:SavedView] {
        if jid(v) == view_id {
            victims = victims + [v];
        }
    }
    for vv in victims {
        del vv;
    }
    return view_list();
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
        hl = _result_headline(tiles);
        chg = _save_search(q, hl["value"], str(hl["kind"]));
        return {"answerable": True, "reply": str(plan.reply), "title": str(plan.title), "tiles": tiles, "clarify": "",
            "changed": chg,
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
        qtiles = [{"key": "adhoc", "title": ttl, "chart": chart, "data": data,
            "recipe": {"kind": "query", "ref": str(plan.sql), "title": ttl, "chart": chart, "good_up": plan.good_up}}];
        hl = _result_headline(qtiles);
        chg = _save_search(q, hl["value"], str(hl["kind"]));
        return {"answerable": True, "reply": str(plan.reply), "title": ttl, "clarify": "",
            "tiles": qtiles, "changed": chg,
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
    if (_parse_dt(date_from) is None) or (_parse_dt(date_to) is None) {
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
# Report Studio (R1, spec: .docs/posthog/REPORTS_FEATURE_SPEC.md).
# A Report = ordered sections; tile/table sections carry the SAME recipe dict a
# Pin does ({kind, ref, title, chart, good_up}) and are executed by _run_pin.
# mode=snapshot: report_build freezes each section's result into `snapshot`
# keyed by section id, so a submitted report's numbers never drift.
# ---------------------------------------------------------------------------

node Report {
    has title: str = "Report";
    has from_dt: str = "";
    has to_dt: str = "";
    has env: str = "prod";
    has mode: str = "snapshot";     # snapshot | live (live lands in R4)
    has template: str = "";
    has sections: list = [];        # [{id, type: header|tile|table|text, title, recipe, md}]
    has snapshot: dict = {};        # section id -> frozen {title, chart, data}
    has built_at: str = "";
    has created_at: str = "";
    has share_token: str = "";      # "" = private; else the public copy's token (R3)
    has share_masked: bool = True;  # emails masked on the public copy
}

node NamedWindow {
    has data: dict = {};            # {name, from_dt, to_dt}
}

# A tile/table section for a registry metric — derived from METRICS at create
# time so titles/charts can't drift from the registry.
def _sec_metric(sid: str, key: str) -> dict {
    m = METRICS[key];
    ch = _tile_for(m);
    kind = "table" if ch == "table" else "tile";
    return {"id": sid, "type": kind, "title": m.title, "md": "",
            "recipe": {"kind": "metric", "ref": key, "title": m.title, "chart": ch, "good_up": m.good_when_up}};
}

def _sec_header(sid: str, title: str) -> dict {
    return {"id": sid, "type": "header", "title": title, "md": "", "recipe": {}};
}

def _sec_text(sid: str, title: str, md: str) -> dict {
    return {"id": sid, "type": "text", "title": title, "md": md, "recipe": {}};
}

glob _METHOD_MD: str = "Every number on this report is env-filtered (production = host allowlist ∪ "
    + "environment='prod') and scoped to the report window shown above. Cost = server-metered "
    + "ai_generation_metered dollars. Signups = auth_signup_succeeded (server-side; never login "
    + "events). Project start method reads properties.source. Users vs events are reported "
    + "separately wherever retries exist. 'anon:' rows are devices that never identified.";

def _report_template(template: str) -> list {
    if template == "event-report" {
        return [
            _sec_header("s01", "Executive summary"),
            _sec_text("s02", "Summary", "_Write your summary here — AI generation lands in R2._"),
            _sec_metric("s03", "new_signups"),
            _sec_metric("s04", "total_spend"),
            _sec_metric("s05", "paid_upgrades"),
            _sec_metric("s06", "preview_reliability"),
            _sec_header("s07", "Participants"),
            _sec_metric("s08", "signup_method"),
            _sec_metric("s09", "signups_detail"),
            _sec_metric("s10", "user_rollup"),
            _sec_header("s11", "Projects & activation"),
            _sec_metric("s12", "project_sources"),
            _sec_metric("s13", "funnel"),
            _sec_header("s14", "AI usage & cost"),
            _sec_metric("s15", "requests_daily"),
            _sec_metric("s16", "cost_by_model"),
            _sec_metric("s16b", "user_model_cost_matrix"),
            _sec_metric("s17", "byok_split"),
            _sec_metric("s18", "project_cost_rollup"),
            _sec_metric("s19", "cost_per_turn"),
            _sec_header("s20", "Deploys"),
            _sec_metric("s21", "deploy_outcomes"),
            _sec_header("s22", "Monetization"),
            _sec_metric("s23", "upgrades_detail"),
            _sec_header("s24", "Issues & friction"),
            _sec_metric("s25", "issue_log"),
            _sec_text("s26", "Method & caveats", _METHOD_MD)
        ];
    }
    return [_sec_header("s01", "Untitled section"),
            _sec_text("s02", "Notes", "_Add sections from any tile's 'Add to report'._")];
}

def _report_meta(r: Report) -> dict {
    return {"id": jid(r), "title": r.title, "from_dt": r.from_dt, "to_dt": r.to_dt,
            "env": r.env, "mode": r.mode, "template": r.template,
            "sections_count": len(r.sections), "built_at": r.built_at, "created_at": r.created_at,
            "share_token": r.share_token, "share_masked": r.share_masked};
}

def:priv report_create(title: str, from_dt: str, to_dt: str, env: str, template: str) -> dict {
    df = _parse_dt(from_dt);
    dt_ = _parse_dt(to_dt);
    if (df is None) or (dt_ is None) or (dt_ <= df) {
        return {"id": "", "error": "bad window — from must be before to"};
    }
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M");
    r = Report(title=(title.strip() if title.strip() else "Report"),
               from_dt=_norm_dt(df), to_dt=_norm_dt(dt_), env=_clamp_env(env),
               template=template, sections=_report_template(template), created_at=now);
    root ++> r;
    out = _report_meta(r);
    out["error"] = "";
    return out;
}

def:priv report_list() -> list {
    out: list[dict] = [];
    for r in [root -->][?:Report] {
        out = out + [_report_meta(r)];
    }
    out.sort(key=lambda (x: dict) { str(x["created_at"]); }, reverse=True);
    return out;
}

def:priv report_get(report_id: str) -> dict {
    for r in [root -->][?:Report] {
        if jid(r) == report_id {
            out = _report_meta(r);
            out["sections"] = r.sections;
            out["snapshot"] = r.snapshot;
            out["checks"] = _report_checks(r);
            return out;
        }
    }
    return {"id": "", "sections": [], "snapshot": {}};
}

# Title / sections edit (text sections, reorder, delete). Snapshot entries for
# section ids that survive are kept; orphaned ids are dropped.
def:priv report_update(report_id: str, title: str, sections: list) -> dict {
    for r in [root -->][?:Report] {
        if jid(r) == report_id {
            if title.strip() {
                r.title = title.strip();
            }
            if sections {
                r.sections = sections;
                keep = {};
                for s in sections {
                    sd = s as dict;
                    sid = str(sd.get("id", ""));
                    if sid in r.snapshot {
                        keep[sid] = r.snapshot[sid];
                    }
                }
                r.snapshot = keep;
            }
            out = _report_meta(r);
            out["sections"] = r.sections;
            out["snapshot"] = r.snapshot;
            return out;
        }
    }
    return {"id": "", "sections": [], "snapshot": {}};
}

def:priv report_delete(report_id: str) -> bool {
    for r in [root -->][?:Report] {
        if jid(r) == report_id {
            del r;
            return True;
        }
    }
    return False;
}

# Cross-section sanity checks (spec §10.3): per-entity cost tables must
# reconcile with the scalar total — surface a mismatch, never a plug row.
def _report_checks(r: Report) -> list {
    checks: list[dict] = [];
    total = 0.0;
    has_total = False;
    turns_sum = 0.0;
    has_turns = False;
    for s in r.sections {
        sd = s as dict;
        rec = sd.get("recipe", {}) as dict;
        snap = r.snapshot.get(str(sd.get("id", "")), {}) as dict;
        data = snap.get("data", {}) as dict;
        if rec.get("ref") == "total_spend" {
            v = data.get("value");
            if v is not None {
                try {
                    total = float(str(v));
                    has_total = True;
                } except Exception {
                    has_total = False;
                }
            }
        }
        if rec.get("ref") == "cost_per_turn" {
            cols = data.get("columns", []) as list;
            ci = _col_index(cols, "cost_usd");
            if ci >= 0 {
                turns_sum = 0.0;
                for row in data.get("rows", []) as list {
                    rr = row as list;
                    if (ci < len(rr)) and (rr[ci] is not None) {
                        try {
                            turns_sum = turns_sum + float(str(rr[ci]));
                        } except Exception {
                            continue;
                        }
                    }
                }
                has_turns = True;
            }
        }
    }
    if has_total and has_turns {
        diff = total - turns_sum;
        if diff < 0.0 {
            diff = -diff;
        }
        ok = diff < 0.05;
        checks = checks + [{"name": "cost reconciliation",
            "ok": ok,
            "detail": f"per-turn rows sum ${round(turns_sum, 2)} vs total ${round(total, 2)}"
                + ("" if ok else " — rows were dropped (row cap?) or the window drifted")}];
    }
    return checks;
}

async def _do_report_build(target: Report) -> dict {
    runnable: list[dict] = [];
    for s in target.sections {
        sd = s as dict;
        rec = sd.get("recipe", {}) as dict;
        if rec.get("kind") {
            runnable = runnable + [sd];
        }
    }
    snap = {};
    if runnable {
        tasks = [];
        for sd in runnable {
            tasks = tasks + [_run_pin(sd["recipe"] as dict, target.env, target.from_dt, target.to_dt)];
        }
        results = await asyncio.gather(*tasks);
        i = 0;
        for sd in runnable {
            snap[str(sd["id"])] = results[i];
            i = i + 1;
        }
    }
    target.snapshot = snap;
    target.built_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M");
    out = _report_meta(target);
    out["sections"] = target.sections;
    out["snapshot"] = target.snapshot;
    out["checks"] = _report_checks(target);
    out["error"] = "";
    return out;
}

async def:priv report_build(report_id: str, refresh: bool) -> dict {
    for r in [root -->][?:Report] {
        if jid(r) == report_id {
            return await _do_report_build(r);
        }
    }
    return {"id": "", "sections": [], "snapshot": {}, "error": "report not found"};
}

# ---- R2: AI synthesis — summary / findings / caveats over the FROZEN snapshot.
# Mirrors ai_insights' honest-degrade pattern; only ai-flagged sections are ever
# replaced, human-written text sections are never touched.

obj ReportInsights {
    has summary: str = "";
    has findings: list[str] = [];
    has caveats: list[str] = [];
}
sem ReportInsights = "A decision-maker's readout of a metrics report: what happened, what stands out, what to distrust.";
sem ReportInsights.summary = "3-5 plain-English sentences summarizing the report window for a decision-maker. Cite the concrete numbers (counts, dollars, percentages) from the context. No preamble, no bullet points.";
sem ReportInsights.findings = "3-6 short bullet findings, each citing a specific number and saying why it matters or what action it suggests. Most important first.";
sem ReportInsights.caveats = "2-4 short honesty caveats a reader must know before acting: data gaps named in the context (blank model rows, proxy metrics, small samples), users-vs-events distinctions, anything that could mislead.";

def _write_report_insights(context: str) -> ReportInsights by INSIGHT_LLM(max_tokens=900);
sem _write_report_insights = "You are the analytics writer for JacHammer (an AI-powered web IDE). Given a report's frozen, environment-filtered metrics for a specific time window, write the executive readout. Use ONLY numbers present in the context — never invent or extrapolate. HARD RULE: table rows are TRUNCATED SAMPLES — never sum, count, or extrapolate a total from them; totals you may cite are the scalar lines and the 'FULL-TABLE sums' lines only. Findings must each cite a number. Caveats must reflect real limitations visible in the context (e.g. a '(blank)' model row means unattributed spend; users vs events differ where retries exist).";
sem _write_report_insights.context = "The report: title, window, then one line per section — scalars as 'title: value (delta% vs previous window)', tables as their columns and top rows.";

# Compact snapshot -> prompt context. Scalars one line; tables top-5 rows.
def _report_context(r: Report) -> str {
    parts = ["REPORT: " + r.title,
             "WINDOW: " + r.from_dt + " -> " + r.to_dt + " UTC (env " + r.env + ")"];
    for s in r.sections {
        sd = s as dict;
        rec = sd.get("recipe", {}) as dict;
        if not rec.get("kind") {
            continue;
        }
        snap = r.snapshot.get(str(sd.get("id", "")), {}) as dict;
        data = snap.get("data", {}) as dict;
        ttl = str(sd.get("title", ""));
        v = data.get("value");
        if v is not None {
            line = ttl + ": " + str(v);
            d = data.get("delta");
            if d is not None {
                line = line + " (" + str(round(d as float)) + "% vs previous window)";
            }
            parts = parts + [line];
        } else {
            cols = data.get("columns", []) as list;
            rows = data.get("rows", []) as list;
            if rows {
                colnames = [];
                for c in cols {
                    colnames = colnames + [str(c)];
                }
                parts = parts + [ttl + " [" + ", ".join(colnames) + "] top rows:"];
                n = 0;
                for row in rows {
                    if n >= 5 {
                        break;
                    }
                    parts = parts + ["  " + str(row)];
                    n = n + 1;
                }
                if len(rows) > 5 {
                    parts = parts + ["  ... (" + str(len(rows)) + " rows total — the rows above are a SAMPLE)"];
                }
                # Full-table sums for numeric columns, so totals never have to be
                # (wrongly) extrapolated from the sampled rows above.
                sums: list = [];
                ci2 = 0;
                for cn in colnames {
                    total = 0.0;
                    seen = False;
                    for row2 in rows {
                        rl2 = row2 as list;
                        if ci2 < len(rl2) {
                            cv = rl2[ci2];
                            if isinstance(cv, (int, float)) {
                                total = total + (cv as float);
                                seen = True;
                            }
                        }
                    }
                    if seen and (cn not in ["ts"]) {
                        sums = sums + [cn + "=" + str(round(total, 2))];
                    }
                    ci2 = ci2 + 1;
                }
                if sums {
                    parts = parts + ["  FULL-TABLE sums (all " + str(len(rows)) + " rows): " + ", ".join(sums)];
                }
            }
        }
    }
    txt = "\n".join(parts);
    return txt[:6000];
}

def _strip_ai_sections(sections: list) -> list {
    out: list = [];
    for s in sections {
        sd = s as dict;
        if not (sd.get("ai", False) as bool) {
            out = out + [sd];
        }
    }
    return out;
}

# Replace ai-flagged sections: summary+findings go up top (after a leading
# header if present), caveats at the end. Human sections keep their order.
def _merge_ai_sections(sections: list, summary: str, findings: list, caveats: list) -> list {
    base = _strip_ai_sections(sections);
    fnd_md = "";
    for f in findings {
        fnd_md = fnd_md + "• " + str(f) + "\n";
    }
    cav_md = "";
    for c in caveats {
        cav_md = cav_md + "• " + str(c) + "\n";
    }
    sum_sec = {"id": "ai1", "type": "text", "title": "AI summary", "md": summary, "recipe": {}, "ai": True};
    fnd_sec = {"id": "ai2", "type": "text", "title": "Findings (AI)", "md": fnd_md.strip(), "recipe": {}, "ai": True};
    cav_sec = {"id": "ai3", "type": "text", "title": "Caveats (AI)", "md": cav_md.strip(), "recipe": {}, "ai": True};
    pos = 0;
    if base {
        first = base[0] as dict;
        if str(first.get("type", "")) == "header" {
            pos = 1;
        }
    }
    return base[:pos] + [sum_sec, fnd_sec] + base[pos:] + [cav_sec];
}

async def _do_report_generate(r: Report) -> dict {
    if not r.snapshot {
        await _do_report_build(r);
    }
    ctx = _report_context(r);
    if not ctx {
        return {"ok": False, "reason": "nothing to summarize — build the report first"};
    }
    try {
        ins = await asyncio.to_thread(_write_report_insights, ctx);
    } except Exception as e {
        return {"ok": False, "reason": str(e)[:160]};
    }
    r.sections = _merge_ai_sections(r.sections, str(ins.summary).strip(), list(ins.findings), list(ins.caveats));
    return {"ok": True, "reason": ""};
}

async def:priv report_generate(report_id: str) -> dict {
    if not ANTH_KEY {
        return {"ok": False, "reason": "ANTHROPIC_API_KEY not set on the server."};
    }
    for r in [root -->][?:Report] {
        if jid(r) == report_id {
            return await _do_report_generate(r);
        }
    }
    return {"ok": False, "reason": "report not found"};
}

# ---- R2: compile an Ask thread into a report — the investigation you already
# did becomes the document (questions/answers as text, tiles as live recipes).

def _thread_to_report(t: Thread, title: str, env: str, from_dt: str, to_dt: str) -> dict {
    df = _parse_dt(from_dt);
    dt_ = _parse_dt(to_dt);
    if (df is None) or (dt_ is None) or (dt_ <= df) {
        return {"id": "", "error": "bad window"};
    }
    secs: list = [];
    n = 0;
    for m in t.messages {
        md = m as dict;
        role = str(md.get("role", ""));
        if role == "user" {
            n = n + 1;
            secs = secs + [_sec_text("t" + str(n), "Question", "❓ " + str(md.get("text", "")))];
        } elif role == "assistant" {
            txt = str(md.get("text", ""));
            if txt {
                n = n + 1;
                secs = secs + [_sec_text("t" + str(n), "Answer", txt)];
            }
            for tl in (md.get("tiles", []) as list) {
                tld = tl as dict;
                rec = tld.get("recipe", {}) as dict;
                if rec.get("kind") {
                    n = n + 1;
                    ch = str(rec.get("chart", "table"));
                    kind = "table" if ch == "table" else "tile";
                    secs = secs + [{"id": "t" + str(n), "type": kind, "title": str(rec.get("title", "Tile")), "md": "", "recipe": rec}];
                }
            }
        }
    }
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M");
    ttl = title.strip() if title.strip() else ("Ask: " + t.title);
    r = Report(title=ttl, from_dt=_norm_dt(df), to_dt=_norm_dt(dt_), env=_clamp_env(env),
               template="from-thread", sections=secs, created_at=now);
    root ++> r;
    out = _report_meta(r);
    out["error"] = "";
    return out;
}

def:priv report_from_thread(thread_id: str, title: str, env: str, from_dt: str, to_dt: str) -> dict {
    for t in [root -->][?:Thread] {
        if jid(t) == thread_id {
            return _thread_to_report(t, title, env, from_dt, to_dt);
        }
    }
    return {"id": "", "error": "thread not found"};
}

# ---- R3: public sharing — a FROZEN copy on the root.shared commons -----------
# Security invariants (spec §8): the public endpoint serves stored snapshot JSON
# only — it never executes SQL and never touches the owner's root. A leaked
# token exposes exactly one frozen document. Emails masked by default.

node SharedReport {
    has token: str = "";
    has data: dict = {};    # frozen {title, window, env, built_at, masked, sections, snapshot}
}

def _mask_str(s: str) -> str {
    return re.sub(r"([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+)", r"\1***@\2", s);
}

# Recursively mask email local-parts everywhere in the payload (rows, who-lists,
# AI prose — the findings can cite emails too).
def _mask_obj(o: any) -> any {
    if isinstance(o, str) {
        return _mask_str(o);
    }
    if isinstance(o, list) {
        out: list = [];
        for x in (o as list) {
            out = out + [_mask_obj(x)];
        }
        return out;
    }
    if isinstance(o, dict) {
        od = o as dict;
        out2 = {};
        for k in od.keys() {
            out2[k] = _mask_obj(od[k]);
        }
        return out2;
    }
    return o;
}

def _shared_payload(r: Report, masked: bool) -> dict {
    p = {"title": r.title, "from_dt": r.from_dt, "to_dt": r.to_dt, "env": r.env,
         "built_at": r.built_at, "masked": masked,
         "sections": r.sections, "snapshot": r.snapshot};
    if masked {
        return _mask_obj(p) as dict;
    }
    return p;
}

def _publish_shared(r: Report, masked: bool) -> str {
    tok = r.share_token if r.share_token else secrets.token_urlsafe(24);
    payload = _shared_payload(r, masked);
    found = False;
    for s in [root.shared -->][?:SharedReport] {
        if s.token == tok {
            s.data = payload;
            found = True;
        }
    }
    if not found {
        sn = SharedReport(token=tok, data=payload);
        root.shared ++> sn;
        grant(sn, level=ReadPerm);
    }
    r.share_token = tok;
    r.share_masked = masked;
    return tok;
}

def:priv report_share(report_id: str, masked: bool) -> dict {
    for r in [root -->][?:Report] {
        if jid(r) == report_id {
            if not r.snapshot {
                return {"token": "", "error": "build the report before sharing"};
            }
            tok = _publish_shared(r, masked);
            return {"token": tok, "error": ""};
        }
    }
    return {"token": "", "error": "report not found"};
}

def:priv report_unshare(report_id: str) -> dict {
    for r in [root -->][?:Report] {
        if jid(r) == report_id {
            tok = r.share_token;
            victims: list = [];
            for s in [root.shared -->][?:SharedReport] {
                if s.token == tok {
                    victims = victims + [s];
                }
            }
            for v in victims {
                del v;
            }
            r.share_token = "";
            return {"token": "", "error": ""};
        }
    }
    return {"token": "", "error": "report not found"};
}

# PUBLIC: anonymous read of one shared frozen document by token.
def:pub report_public(token: str) -> dict {
    t = token.strip();
    if not t {
        return {"found": False, "report": {}};
    }
    for s in [root.shared -->][?:SharedReport] {
        if s.token == t {
            return {"found": True, "report": s.data};
        }
    }
    return {"found": False, "report": {}};
}

# ---- R3: Markdown export ----------------------------------------------------

def _md_table(cols: list, rows: list) -> str {
    heads: list = [];
    for c in cols {
        heads = heads + [str(c)];
    }
    dashes: list = [];
    for h in heads {
        dashes = dashes + ["---"];
    }
    lines = ["| " + " | ".join(heads) + " |",
             "|" + "|".join(dashes) + "|"];
    n = 0;
    for r in rows {
        if n >= 300 {
            lines = lines + ["| … " + str(len(rows) - 300) + " more rows … |"];
            break;
        }
        cells: list = [];
        for cell in (r as list) {
            cells = cells + ["" if cell is None else str(cell)];
        }
        lines = lines + ["| " + " | ".join(cells) + " |"];
        n = n + 1;
    }
    return "\n".join(lines);
}

def _report_markdown(r: Report) -> str {
    parts = ["# " + r.title, "",
             "**Window:** " + r.from_dt + " → " + r.to_dt + " UTC · **Env:** " + r.env
             + (" · built " + r.built_at + " UTC" if r.built_at else ""), ""];
    for s in r.sections {
        sd = s as dict;
        typ = str(sd.get("type", ""));
        ttl = str(sd.get("title", ""));
        if typ == "header" {
            parts = parts + ["## " + ttl, ""];
            continue;
        }
        if typ == "text" {
            parts = parts + ["### " + ttl, "", str(sd.get("md", "")), ""];
            continue;
        }
        snap = r.snapshot.get(str(sd.get("id", "")), {}) as dict;
        data = snap.get("data", {}) as dict;
        v = data.get("value");
        if v is not None {
            line = "**" + ttl + ":** " + str(v);
            d = data.get("delta");
            if d is not None {
                line = line + " (" + str(round(d as float)) + "% vs previous window)";
            }
            parts = parts + [line, ""];
        } else {
            cols = data.get("columns", []) as list;
            rows = data.get("rows", []) as list;
            if rows {
                parts = parts + ["### " + ttl, "", _md_table(cols, rows), ""];
            }
        }
    }
    parts = parts + ["---", "_Generated by JacHammer Analytics — env-filtered, snapshot-frozen._"];
    return "\n".join(parts);
}

def:priv report_export_md(report_id: str) -> dict {
    for r in [root -->][?:Report] {
        if jid(r) == report_id {
            return {"md": _report_markdown(r), "title": r.title, "error": ""};
        }
    }
    return {"md": "", "title": "", "error": "report not found"};
}

# ---- named windows (G9) — "during the hackathon" as a first-class range ------

def:priv window_list() -> list {
    out: list[dict] = [];
    for w in [root -->][?:NamedWindow] {
        out = out + [w.data];
    }
    out.sort(key=lambda (x: dict) { str(x["from_dt"]); }, reverse=True);
    return out;
}

def:priv window_add(name: str, from_dt: str, to_dt: str) -> list {
    df = _parse_dt(from_dt);
    dt_ = _parse_dt(to_dt);
    nm = name.strip();
    if (df is None) or (dt_ is None) or (dt_ <= df) or (not nm) {
        return window_list();
    }
    for w in [root -->][?:NamedWindow] {
        d = w.data;
        if str(d["name"]) == nm {
            w.data = {"name": nm, "from_dt": _norm_dt(df), "to_dt": _norm_dt(dt_)};
            return window_list();
        }
    }
    root ++> NamedWindow(data={"name": nm, "from_dt": _norm_dt(df), "to_dt": _norm_dt(dt_)});
    return window_list();
}

def:priv window_remove(name: str) -> list {
    victims: list = [];
    for w in [root -->][?:NamedWindow] {
        d = w.data;
        if str(d["name"]) == name {
            victims = victims + [w];
        }
    }
    for v in victims {
        del v;
    }
    return window_list();
}

# ---------------------------------------------------------------------------
# User 360 (Phase 1 of USER_360_BUILD_SPEC — PostHog-only, zero product-backend
# coupling). Drill-down target for every clickable user cell: profile, window
# counters, cost by model, projects, recent activity timeline — one request.
# ---------------------------------------------------------------------------

# The identity shown in tables is email OR display_name OR name OR 'anon:<pid8>'.
# Build a WHERE predicate that finds that person again. Values are quote-stripped
# (identity strings never legitimately contain quotes/backslashes).
def _who_predicate(user: str) -> str {
    u = re.sub(r"['\\\\]", "", user.strip());
    if u.startswith("anon:") {
        return "startsWith(toString(person_id), '" + re.sub(r"[^0-9a-f-]", "", u[5:]) + "')";
    }
    return ("(coalesce(toString(person.properties.email),'') = '" + u + "'"
        + " OR coalesce(toString(person.properties.display_name),'') = '" + u + "'"
        + " OR coalesce(toString(person.properties.name),'') = '" + u + "')");
}

async def:priv user_360(user: str, env: str) -> dict {
    env = _clamp_env(env);
    ef = env_filter(env);
    win = "AND timestamp > now() - INTERVAL 30 DAY";
    # Two-step: resolve the person_id once (identity predicates need the persons
    # join — fine for one windowed lookup), then run every panel against the bare
    # person_id. Person-prop predicates in 5 parallel queries 504 ClickHouse.
    q_pid = ("SELECT toString(person_id) pid FROM events WHERE " + _who_predicate(user)
        + " " + ef + " " + win + " LIMIT 1");
    pres = await asyncio.to_thread(run_hogql, q_pid);
    if ("error" in pres) or (not (pres.get("results") or [])) {
        return {"user": user, "window": "last 30 days",
                "error": "user not found in the last 30 days" if "error" not in pres else str(pres["error"])[:120],
                "profile": {"columns": [], "rows": []}, "summary": {"columns": [], "rows": []},
                "models": {"columns": [], "rows": []}, "projects": {"columns": [], "rows": []},
                "timeline": {"columns": [], "rows": []}};
    }
    pid = re.sub(r"[^0-9a-f-]", "", str(((pres["results"] as list)[0] as list)[0]));
    who = "toString(person_id) = '" + pid + "'";
    # Same 30d window as every other panel — a wider min/max over the person-join
    # predicate 504s ClickHouse (aggregates can't short-circuit like ORDER BY LIMIT).
    q_profile = ("SELECT coalesce(toString(any(person.properties.email)),'') email,"
        + " coalesce(toString(any(person.properties.display_name)),'') display_name,"
        + " coalesce(toString(any(person.properties.name)),'') person_name,"
        + " coalesce(toString(any(person.properties.plan)),'') plan,"
        + " coalesce(toString(any(person.properties.auth_provider)),'') auth_provider,"
        + " substring(toString(min(timestamp)),1,16) first_seen,"
        + " substring(toString(max(timestamp)),1,16) last_seen, count() events"
        + " FROM events WHERE " + who + " " + ef + " " + win);
    q_summary = ("SELECT countIf(event='auth_signup_succeeded') signed_up,"
        + " countIf(event='project_created') projects, countIf(event='ai_message_sent') ai_turns,"
        + " countIf(event='ai_message_completed') ai_done, countIf(event='ai_message_failed') ai_failed,"
        + " round(sumIf(toFloat64OrNull(toString(properties.cost_usd)), event='ai_generation_metered'),2) cost_usd,"
        + " countIf(event='preview_ready') previews,"
        + " countIf(event IN ('deploy_sandbox_succeeded','deploy_production_succeeded')) deploys_ok,"
        + " countIf(event IN ('deploy_sandbox_failed','deploy_production_failed')) deploys_failed,"
        + " countIf(event='github_connect_succeeded') gh_ok,"
        + " countIf(event='upgrade_checkout_succeeded') upgrades"
        + " FROM events WHERE " + who + " " + ef + " " + win);
    q_models = ("SELECT coalesce(nullIf(toString(properties.model),''),'(blank)') model, count() runs,"
        + " round(sum(toFloat64OrNull(toString(properties.cost_usd))),2) total_usd"
        + " FROM events WHERE event='ai_generation_metered' AND " + who + " " + ef + " " + win
        + " GROUP BY model ORDER BY total_usd DESC LIMIT 10");
    q_projects = ("SELECT coalesce(nullIf(toString(properties.project_id),''),'(none)') project_id,"
        + " count() runs, round(sum(toFloat64OrNull(toString(properties.cost_usd))),2) cost_usd,"
        + " substring(toString(max(timestamp)),1,16) last_activity"
        + " FROM events WHERE event='ai_generation_metered' AND " + who + " " + ef + " " + win
        + " GROUP BY project_id ORDER BY cost_usd DESC LIMIT 20");
    q_timeline = ("SELECT substring(toString(timestamp),1,16) ts, event,"
        + " coalesce(nullIf(toString(properties.model),''), nullIf(toString(properties.reason),''),"
        + " nullIf(toString(properties.plan),''), nullIf(toString(properties.source),''), '') detail"
        + " FROM events WHERE " + who + " " + ef + " " + win
        + " AND event NOT IN ('$pageview','$pageleave','$web_vitals','$set','$identify','app_loaded')"
        + " ORDER BY timestamp DESC LIMIT 40");
    results = await asyncio.gather(
        asyncio.to_thread(run_hogql, q_profile),
        asyncio.to_thread(run_hogql, q_summary),
        asyncio.to_thread(run_hogql, q_models),
        asyncio.to_thread(run_hogql, q_projects),
        asyncio.to_thread(run_hogql, q_timeline)
    );
    out: dict = {"user": user, "window": "last 30 days", "error": ""};
    labels = ["profile", "summary", "models", "projects", "timeline"];
    i = 0;
    for res in results {
        rd = res as dict;
        if "error" in rd {
            out[labels[i]] = {"columns": [], "rows": []};
            out["error"] = str(rd["error"])[:120];
        } else {
            out[labels[i]] = {"columns": rd["columns"], "rows": rd["results"]};
        }
        i = i + 1;
    }
    return out;
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

# ---- composite metrics (G3): N queries + a Python combine step -------------
# Pivot per-turn cost rows into user × model dollar columns. Pure — tested.
def _pivot_user_model(cols: list, rows: list) -> dict {
    ui = _col_index(cols, "user");
    mi = _col_index(cols, "model");
    ci = _col_index(cols, "cost_usd");
    if (ui < 0) or (mi < 0) or (ci < 0) {
        return {"error": "pivot input missing user/model/cost_usd columns"};
    }
    per_user: dict = {};      # user -> {model -> usd}
    user_runs: dict = {};
    model_tot: dict = {};
    order: list = [];
    for r in rows {
        rl = r as list;
        u = str(rl[ui]);
        mdl = str(rl[mi]);
        c = rl[ci];
        cv = 0.0;
        if c is not None {
            cv = c as float;
        }
        if u not in per_user {
            per_user[u] = {};
            user_runs[u] = 0;
            order = order + [u];
        }
        um = per_user[u] as dict;
        um[mdl] = (um.get(mdl, 0.0) as float) + cv;
        user_runs[u] = (user_runs[u] as int) + 1;
        model_tot[mdl] = (model_tot.get(mdl, 0.0) as float) + cv;
    }
    models: list = [];
    for k in model_tot.keys() {
        models = models + [[model_tot[k], k]];
    }
    models.sort(key=lambda (p: list) { p[0] as float; }, reverse=True);
    mcols: list = [];
    for p in models {
        mcols = mcols + [str((p as list)[1])];
    }
    totals: list = [];
    for u in order {
        um2 = per_user[u] as dict;
        tot = 0.0;
        for mk in um2.keys() {
            tot = tot + (um2[mk] as float);
        }
        totals = totals + [[tot, u]];
    }
    totals.sort(key=lambda (p: list) { p[0] as float; }, reverse=True);
    out_rows: list = [];
    for p in totals {
        pu = str((p as list)[1]);
        um3 = per_user[pu] as dict;
        row: list = [pu, user_runs[pu], round((p as list)[0] as float, 2)];
        for mc in mcols {
            mv = um3.get(mc);
            row = row + [round(mv as float, 2) if mv is not None else None];
        }
        out_rows = out_rows + [row];
    }
    return {"columns": ["user", "runs", "total_usd"] + mcols, "rows": out_rows};
}

async def _cx_user_model_matrix(env: str, date_from: str, date_to: str) -> dict {
    src = METRICS["cost_per_turn"];
    res = await asyncio.to_thread(run_hogql, _fill(src.sql, env, date_from, date_to, "toDate"));
    if "error" in res {
        return {"error": res["error"]};
    }
    return _pivot_user_model(res["columns"] as list, res["results"] as list);
}

async def _run_metric(m: Metric, out: dict, env: str, range_days: int, date_from: str, date_to: str, bkt: str, ck: str) -> dict {
    if m.shape == "composite" {
        r = await _cx_user_model_matrix(env, date_from, date_to);
        if "error" in r {
            out["error"] = r["error"];
            return out;
        }
        out["columns"] = r["columns"];
        out["rows"] = r["rows"];
        _cache_put(ck, out);
        return out;
    }

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
        # compare-to-previous: same query over the immediately-preceding window of EXACT
        # equal length (span-based, so a 7.5h window compares against the prior 7.5h).
        if "{from}" in m.sql {
            # date_from/date_to were normalized by metric() — parse is infallible here.
            wf = datetime.strptime(date_from, "%Y-%m-%d %H:%M:%S");
            wt = datetime.strptime(date_to, "%Y-%m-%d %H:%M:%S");
            prev_to = date_from;
            prev_from = _norm_dt(wf - (wt - wf));
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
