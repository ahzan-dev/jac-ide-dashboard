#!/usr/bin/env python3
"""Pull real-data snapshots from PostHog for the multi-page dashboard prototype.

Builds ONE snapshot PER ENVIRONMENT (prod / dev / all) because a single PostHog
project ingests every environment — only prod (jachammer.ai) is real end users.
The dashboard's top-bar switcher flips between them. Writes data.js:
  window.DASHBOARD_DATA = {environments, current, generated_at, data:{env:{...}}}
Re-run any time: `python3 gen_data.py`  (key stays server-side; never in the browser).
"""
import json, os, sys, urllib.request, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
KEY = ""
for line in open(os.path.join(ROOT, ".env")):
    if line.startswith("POSTHOG_API_KEY"):
        KEY = line.split("=", 1)[1].strip(); break
if not KEY:
    print("POSTHOG_API_KEY not found in .env", file=sys.stderr); sys.exit(1)

PROJECT = "425465"
API = f"https://us.posthog.com/api/projects/{PROJECT}/query/"

# One project, many environments. hosts=None → no filter ("all").
ENVIRONMENTS = [
    ("prod", "Production", ["jachammer.ai", "www.jachammer.ai", "jac-builder.jaseci.org"]),
    ("dev",  "Dev",        ["jac-builder-dev.jaseci.org"]),
    ("all",  "All envs",   None),
]
_HOSTS = None  # set per environment in the build loop; read by hog()/build_env()

def run(query_obj):
    body = json.dumps({"query": query_obj}).encode()
    req = urllib.request.Request(API, data=body, method="POST",
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode(errors='ignore')[:160]}", file=sys.stderr)
        return {"results": [], "error": "http"}

def hog(sql):
    # Scope every EVENT scan to the current env by injecting the host filter
    # right after each `FROM events WHERE` (targets real event scans only, never
    # an outer WHERE over a joined subquery). None → no filter.
    if _HOSTS:
        where = "properties.$host IN (%s)" % ", ".join("'%s'" % h for h in _HOSTS)
        sql = sql.replace("FROM events WHERE ", "FROM events WHERE " + where + " AND ")
    d = run({"kind": "HogQLQuery", "query": sql})
    if d.get("error"):
        return []
    return d.get("results", [])


def build_env():
    """Run every query for the currently-selected environment (_HOSTS)."""
    data = {}
    data["signups_daily"] = hog("SELECT toDate(timestamp) d, count() n FROM events WHERE event='auth_signup_succeeded' AND timestamp > now() - INTERVAL 21 DAY GROUP BY d ORDER BY d")
    data["signups_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, count() n FROM events WHERE event='auth_signup_succeeded' AND timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    data["signups_monthly"] = hog("SELECT toStartOfMonth(timestamp) mo, count() n FROM events WHERE event='auth_signup_succeeded' AND timestamp > now() - INTERVAL 6 MONTH GROUP BY mo ORDER BY mo")
    data["signups_total"] = hog("SELECT count() FROM events WHERE event='auth_signup_succeeded' AND timestamp > now() - INTERVAL 180 DAY")
    # "active" (ANY event, incl. page views/bounces) = reach, NOT usage.
    data["active"] = hog("SELECT count(DISTINCT if(timestamp>now()-INTERVAL 1 DAY,person_id,NULL)) dau, count(DISTINCT if(timestamp>now()-INTERVAL 7 DAY,person_id,NULL)) wau, count(DISTINCT person_id) mau FROM events WHERE timestamp > now() - INTERVAL 30 DAY")
    # "active builders" = did a REAL action (sent AI msg / ran preview / made a project). This is honest usage.
    data["active_builders"] = hog("SELECT count(DISTINCT if(timestamp>now()-INTERVAL 1 DAY,person_id,NULL)) dau, count(DISTINCT if(timestamp>now()-INTERVAL 7 DAY,person_id,NULL)) wau, count(DISTINCT person_id) mau FROM events WHERE event IN ('ai_message_sent','preview_ready','project_created') AND timestamp > now() - INTERVAL 30 DAY")
    data["active_builders_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, count(DISTINCT person_id) n FROM events WHERE event IN ('ai_message_sent','preview_ready','project_created') AND timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    # registered (non-guest) distinct persons active in 30d — for guest/registered split
    data["registered_active"] = hog("SELECT count(DISTINCT person_id) FROM events WHERE person.properties.is_guest != true AND timestamp > now() - INTERVAL 30 DAY")
    data["north_star_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, count(DISTINCT person_id) v FROM events WHERE event IN ('preview_ready','ai_message_completed') AND timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    data["activation_weekly"] = hog("SELECT toStartOfWeek(s.ts) wk, count(DISTINCT s.person_id) signups, count(DISTINCT b.person_id) activated, round(100.0*count(DISTINCT b.person_id)/nullIf(count(DISTINCT s.person_id),0),1) pct FROM (SELECT person_id, min(timestamp) ts FROM events WHERE event='auth_signup_succeeded' AND timestamp > now() - INTERVAL 12 WEEK GROUP BY person_id) s LEFT JOIN (SELECT DISTINCT person_id FROM events WHERE event='ai_message_completed' AND timestamp > now() - INTERVAL 14 WEEK) b ON s.person_id=b.person_id WHERE s.ts > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    data["ttfv"] = hog("SELECT round(median(diff),1), round(quantile(0.25)(diff),1), round(quantile(0.75)(diff),1), count() FROM (SELECT dateDiff('minute', s.ts, b.ts) diff FROM (SELECT person_id, min(timestamp) ts FROM events WHERE event='auth_signup_succeeded' AND timestamp > now() - INTERVAL 14 WEEK GROUP BY person_id) s INNER JOIN (SELECT person_id, min(timestamp) ts FROM events WHERE event='ai_message_completed' AND timestamp > now() - INTERVAL 16 WEEK GROUP BY person_id) b ON s.person_id=b.person_id WHERE b.ts >= s.ts AND s.ts > now() - INTERVAL 30 DAY)")
    data["gen_success_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, round(100.0*countIf(event='ai_message_completed')/nullIf(countIf(event='ai_message_sent'),0),1) pct FROM events WHERE event IN ('ai_message_sent','ai_message_completed') AND timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    data["quality_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, countIf(event='ai_message_completed') done, countIf(event='ai_message_reverted') reverted, countIf(event='ai_user_aborted') aborted FROM events WHERE event IN ('ai_message_completed','ai_message_reverted','ai_user_aborted') AND timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    data["preview_reliability_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, round(100.0*countIf(event='preview_ready')/nullIf(countIf(event='preview_start_requested'),0),1) pct FROM events WHERE event IN ('preview_ready','preview_start_requested') AND timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")

    props = [{"key": "$host", "value": _HOSTS, "operator": "exact", "type": "event"}] if _HOSTS else []
    ret = run({"kind":"RetentionQuery","retentionFilter":{"period":"Week","totalIntervals":6,"targetEntity":{"id":"auth_signup_succeeded","type":"events"},"returningEntity":{"id":"ai_message_completed","type":"events"},"retentionType":"retention_first_time"},"properties":props,"dateRange":{"date_from":"-6w"}})
    rows = []
    for row in ret.get("results", []):
        vals = [c.get("count", 0) for c in row.get("values", [])]
        base = vals[0] if vals else 0
        rows.append({"cohort": str(row.get("date", ""))[:10], "base": base, "pcts": [round(100*v/base) if base else 0 for v in vals]})
    data["retention"] = rows

    data["projects_total"] = hog("SELECT count(), count(DISTINCT person_id) FROM events WHERE event='project_created' AND timestamp > now() - INTERVAL 180 DAY")
    data["projects_by_source"] = hog("SELECT properties.source src, count() n FROM events WHERE event='project_created' AND timestamp > now() - INTERVAL 30 DAY GROUP BY src ORDER BY n DESC")
    data["projects_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, count() n FROM events WHERE event='project_created' AND timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    data["funnel"] = hog("WITH s AS (SELECT DISTINCT person_id FROM events WHERE event='auth_signup_succeeded' AND timestamp > now() - INTERVAL 30 DAY) SELECT (SELECT count() FROM s) signed_up, countDistinct(if(event='project_created',person_id,NULL)) created_project, countDistinct(if(event='ai_message_sent',person_id,NULL)) sent_ai, countDistinct(if(event='ai_message_completed',person_id,NULL)) got_build, countDistinct(if(event='preview_ready',person_id,NULL)) previewed FROM events WHERE timestamp > now() - INTERVAL 30 DAY AND person_id IN (SELECT person_id FROM s)")
    data["returning_weekly"] = hog("SELECT wk, count(DISTINCT if(first_wk=wk, person_id, NULL)) new_u, count(DISTINCT if(first_wk<wk, person_id, NULL)) ret_u FROM (SELECT person_id, toStartOfWeek(timestamp) wk, min(toStartOfWeek(timestamp)) OVER (PARTITION BY person_id) first_wk FROM events WHERE timestamp > now() - INTERVAL 10 WEEK) GROUP BY wk ORDER BY wk")
    data["deploys"] = hog("SELECT event, count() n FROM events WHERE event LIKE 'deploy%' AND timestamp > now() - INTERVAL 180 DAY GROUP BY event ORDER BY n DESC")
    data["time_spent"] = hog("SELECT round(median(dur),1), round(avg(dur),1), round(sum(dur)/60.0,1), count() FROM (SELECT dateDiff('second', min(timestamp), max(timestamp))/60.0 dur FROM events WHERE timestamp > now() - INTERVAL 14 DAY AND $session_id != '' GROUP BY $session_id HAVING dur > 0)")
    data["ai_requests_total"] = hog("SELECT count() FROM events WHERE event='ai_message_sent' AND timestamp > now() - INTERVAL 30 DAY")
    data["ai_requests_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, count() n FROM events WHERE event='ai_message_sent' AND timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    data["response_time"] = hog("SELECT round(median(toFloat64OrNull(toString(properties.duration_ms)))/1000,1), round(avg(toFloat64OrNull(toString(properties.duration_ms)))/1000,1), count() FROM events WHERE event='ai_message_completed' AND timestamp > now() - INTERVAL 30 DAY")
    data["active_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, count(DISTINCT person_id) n FROM events WHERE timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    data["top_features"] = hog("SELECT event, count(DISTINCT person_id) u FROM events WHERE event IN ('preview_ready','ai_message_sent','project_created','deploy_production_clicked','deploy_sandbox_clicked','export_downloaded','github_connect_succeeded','project_shared','git_commit_succeeded','inspector_element_selected') AND timestamp > now() - INTERVAL 30 DAY GROUP BY event ORDER BY u DESC")
    data["problem_areas"] = hog("SELECT multiIf(event='ai_message_failed', concat('AI: ', coalesce(properties.reason,'unknown')), event='preview_start_failed', concat('Preview: ', coalesce(properties.reason,'unknown')), event='$exception','JS crash', event) area, count() n FROM events WHERE event IN ('ai_message_failed','preview_start_failed','$exception','ai_user_aborted') AND timestamp > now() - INTERVAL 30 DAY GROUP BY area ORDER BY n DESC LIMIT 8")
    data["files_changed_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, round(sum(toFloat(properties.files_changed))) n FROM events WHERE event='ai_message_completed' AND timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    data["files_changed_total"] = hog("SELECT round(sum(toFloat(properties.files_changed))) FROM events WHERE event='ai_message_completed' AND timestamp > now() - INTERVAL 30 DAY")
    data["total_users"] = hog("SELECT count(DISTINCT person_id) FROM events WHERE timestamp > now() - INTERVAL 180 DAY")
    # Auth method from the signup EVENT (reliable, incl. SSO post-fix) — not the
    # person.auth_provider prop which is mostly unset. Historically all 'password'
    # (SSO signups were untracked until the server-side fix); splits by provider
    # once that ships.
    data["signup_source"] = hog("SELECT coalesce(nullIf(toString(properties.method),''),'unknown') p, count(DISTINCT person_id) n FROM events WHERE event='auth_signup_succeeded' AND timestamp > now() - INTERVAL 90 DAY GROUP BY p ORDER BY n DESC LIMIT 6")
    # Real acquisition channel — PostHog auto-captures this; mostly $direct/None today.
    data["referrer"] = hog("SELECT coalesce(nullIf(toString(person.properties.$initial_referring_domain),''),'direct/none') d, count(DISTINCT person_id) n FROM events WHERE event='auth_signup_succeeded' AND timestamp > now() - INTERVAL 120 DAY GROUP BY d ORDER BY n DESC LIMIT 6")
    data["churn_risk"] = hog("SELECT count(DISTINCT person_id) FROM events WHERE person_id IN (SELECT DISTINCT person_id FROM events WHERE timestamp < now()-INTERVAL 14 DAY AND timestamp > now()-INTERVAL 60 DAY) AND person_id NOT IN (SELECT DISTINCT person_id FROM events WHERE timestamp > now()-INTERVAL 14 DAY)")
    data["requests_daily"] = hog("SELECT toDate(timestamp) d, count() n FROM events WHERE event='ai_message_sent' AND timestamp > now() - INTERVAL 14 DAY GROUP BY d ORDER BY d")
    data["prompt_len"] = hog("SELECT round(median(toFloat64OrNull(toString(properties.prompt_length))),0), round(avg(toFloat64OrNull(toString(properties.prompt_length))),0), count() FROM events WHERE event='ai_message_sent' AND timestamp > now() - INTERVAL 30 DAY")
    data["ai_fail_reasons"] = hog("SELECT coalesce(nullIf(toString(properties.reason),''),'unknown') r, count() n FROM events WHERE event='ai_message_failed' AND timestamp > now() - INTERVAL 30 DAY GROUP BY r ORDER BY n DESC LIMIT 8")
    data["peak_hours"] = hog("SELECT toHour(timestamp) h, count() n FROM events WHERE event='ai_message_sent' AND timestamp > now() - INTERVAL 30 DAY GROUP BY h ORDER BY h")
    data["model_mix"] = hog("SELECT coalesce(nullIf(toString(properties.to),''),'unknown') m, count() n FROM events WHERE event='ai_model_switched_from_chat' AND timestamp > now() - INTERVAL 90 DAY GROUP BY m ORDER BY n DESC LIMIT 6")
    data["metered_rows"] = hog("SELECT count() FROM events WHERE event='ai_generation_metered' AND timestamp > now() - INTERVAL 90 DAY")
    data["exception_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, count() n FROM events WHERE event='$exception' AND timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    data["latency_weekly"] = hog("SELECT toStartOfWeek(timestamp) wk, round(median(toFloat64OrNull(toString(properties.duration_ms)))/1000,1) s FROM events WHERE event='ai_message_completed' AND timestamp > now() - INTERVAL 10 WEEK GROUP BY wk ORDER BY wk")
    data["daily_ai"] = hog("SELECT toDate(timestamp) d, count() n FROM events WHERE event='ai_message_completed' AND timestamp > now() - INTERVAL 30 DAY GROUP BY d ORDER BY d")
    return data


all_data = {}
for key, label, hosts in ENVIRONMENTS:
    _HOSTS = hosts
    print(f"building env '{key}' ({label}) ...", file=sys.stderr)
    all_data[key] = build_env()

out_obj = {
    "environments": [{"key": k, "label": l} for k, l, _ in ENVIRONMENTS],
    "current": "prod",
    "generated_at": datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"),
    "data": all_data,
}
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data.js")
with open(out, "w") as f:
    f.write("// AUTO-GENERATED by gen_data.py — real snapshots from PostHog project 425465, per environment.\n")
    f.write("// Re-run `python3 gen_data.py` to refresh.\n")
    f.write("window.DASHBOARD_DATA = " + json.dumps(out_obj, indent=1) + ";\n")
print("wrote", out, "-", len(json.dumps(out_obj)), "bytes")
