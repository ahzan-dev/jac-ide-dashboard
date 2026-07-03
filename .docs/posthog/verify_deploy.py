#!/usr/bin/env python3
"""Post-deploy verification for the analytics instrumentation (PR #607).

Run this AFTER merging + deploying (and after POSTHOG_PROJECT_TOKEN is on the
pod). It confirms every new event / property is actually flowing — turning
"did it work?" into a green/red checklist, and telling you exactly which one
isn't and why.

  python3 verify_deploy.py            # last 3 days, all environments
  python3 verify_deploy.py 7          # last 7 days
  python3 verify_deploy.py 3 prod     # last 3 days, prod hosts only

Reads POSTHOG_API_KEY (the phx_ personal key) from the repo .env — stays local,
never printed. Queries PostHog project 425465.

Legend:
  [OK]      flowing — data present
  [MISSING] no data — see the note (not deployed? token missing? no traffic?)
  [PENDING] needs a user to do the action (rating/deploy/signup) — 0 is fine yet
  [WARN]    present but looks off
"""
import json, os, sys, urllib.request, datetime

# ---- config -----------------------------------------------------------------
here = os.path.dirname(os.path.abspath(__file__))
root = here
for _ in range(6):
    if os.path.exists(os.path.join(root, ".env")):
        break
    root = os.path.dirname(root)
KEY = ""
for line in open(os.path.join(root, ".env")):
    if line.startswith("POSTHOG_API_KEY"):
        KEY = line.split("=", 1)[1].strip(); break
if not KEY:
    print("POSTHOG_API_KEY not found in .env", file=sys.stderr); sys.exit(1)

API = "https://us.posthog.com/api/projects/425465/query/"
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 3
ENV = sys.argv[2] if len(sys.argv) > 2 else "all"
PROD_HOSTS = ["jachammer.ai", "www.jachammer.ai", "jac-builder.jaseci.org"]
SINCE = "now() - INTERVAL %d DAY" % DAYS
# host filter injected into every WHERE (prod-only) or empty (all envs)
HOSTF = ""
if ENV == "prod":
    HOSTF = " AND properties.$host IN (%s)" % ", ".join("'%s'" % h for h in PROD_HOSTS)


def hog(sql):
    body = json.dumps({"query": {"kind": "HogQLQuery", "query": sql}}).encode()
    req = urllib.request.Request(API, data=body, method="POST",
        headers={"Authorization": "Bearer %s" % KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            d = json.load(r)
        return [] if d.get("error") else d.get("results", [])
    except Exception as e:
        print("  query error:", str(e)[:120], file=sys.stderr)
        return []


PASS = FAIL = PEND = 0
def line(status, label, detail):
    global PASS, FAIL, PEND
    tag = {"ok": "\033[92m[OK]     \033[0m", "missing": "\033[91m[MISSING]\033[0m",
           "pending": "\033[93m[PENDING]\033[0m", "warn": "\033[93m[WARN]   \033[0m"}[status]
    if status == "ok": PASS += 1
    elif status == "pending": PEND += 1
    else: FAIL += 1
    print("  %s %-34s %s" % (tag, label, detail))


def one(sql):  # scalar count
    r = hog(sql)
    return (r[0][0] if r and r[0] else 0) or 0


print("\n=== Analytics deploy verification — last %d days · env=%s ===" % (DAYS, ENV))

# 0. THE deployment gate: environment super-property present on recent events?
env_rows = hog("SELECT coalesce(nullIf(toString(properties.environment),''),'(unset)') e, count() n FROM events WHERE timestamp > %s%s GROUP BY e ORDER BY n DESC LIMIT 8" % (SINCE, HOSTF))
env_map = {r[0]: r[1] for r in env_rows}
deployed = any(k != "(unset)" for k in env_map)
print("\n-- Deployment gate --")
line("ok" if deployed else "missing", "environment super-property",
     (", ".join("%s=%s" % (k, v) for k, v in env_map.items()) if env_map else "no events")
     + ("" if deployed else "  <- if all (unset): frontend build NOT deployed yet"))

# 1. Auto props on ai_message_* (appear on any AI traffic)
print("\n-- Auto (should have data on any traffic since deploy) --")
tc = hog("SELECT coalesce(nullIf(toString(properties.task_category),''),'(unset)') t, count() n FROM events WHERE event='ai_message_sent' AND timestamp > %s%s GROUP BY t ORDER BY n DESC LIMIT 8" % (SINCE, HOSTF))
tcmap = {r[0]: r[1] for r in tc}
line("ok" if any(k != "(unset)" for k in tcmap) else ("missing" if tcmap else "pending"),
     "task_category on ai_message_sent", ", ".join("%s=%s" % (k, v) for k, v in tcmap.items()) or "no ai_message_sent")

rlr = hog("SELECT countIf(coalesce(toString(properties.response_length),'') != '') w, count() t FROM events WHERE event='ai_message_completed' AND timestamp > %s%s" % (SINCE, HOSTF))
rw = (rlr[0][0] if rlr and rlr[0] else 0) or 0
rt = (rlr[0][1] if rlr and rlr[0] else 0) or 0
line("ok" if rw > 0 else ("pending" if rt == 0 else "missing"), "response_length on ai_message_completed", "%d/%d carry it" % (rw, rt))

tcc = hog("SELECT round(avg(toFloat64OrNull(toString(properties.tool_call_count))),2), max(toFloat64OrNull(toString(properties.tool_call_count))), count() FROM events WHERE event='ai_message_completed' AND timestamp > %s%s" % (SINCE, HOSTF))
avg_tcc = (tcc[0][0] if tcc and tcc[0] else 0) or 0
max_tcc = (tcc[0][1] if tcc and tcc[0] else 0) or 0
line("ok" if max_tcc and max_tcc > 0 else "warn", "tool_call_count fix (was always 0)",
     "avg=%s max=%s  %s" % (avg_tcc, max_tcc, "(>0 = fixed)" if max_tcc else "still 0 — check the fix shipped"))

pid = hog("SELECT event, countIf(coalesce(toString(properties.project_id),'') != '') w, count() t FROM events WHERE event IN ('ai_message_sent','ai_message_completed','preview_start_requested') AND timestamp > %s%s GROUP BY event" % (SINCE, HOSTF))
for ev, w, t in pid:
    line("ok" if t and w == t else ("warn" if w else "missing"), "project_id on %s" % ev, "%d/%d carry it" % (w, t))
if not pid:
    line("pending", "project_id on core events", "no ai/preview traffic yet")

# 2. plan person property (needs users to load useUserTier)
plan = hog("SELECT coalesce(nullIf(toString(person.properties.plan),''),'(unset)') p, count(DISTINCT person_id) n FROM events WHERE timestamp > %s%s GROUP BY p ORDER BY n DESC LIMIT 6" % (SINCE, HOSTF))
pmap = {r[0]: r[1] for r in plan}
line("ok" if any(k != "(unset)" for k in pmap) else "pending", "plan person property",
     ", ".join("%s=%s" % (k, v) for k, v in pmap.items()) or "no data")

# 3. Server-side cost event (THE token-dependent one)
print("\n-- Server-side / config-dependent --")
cost = hog("SELECT count() n, round(sum(toFloat64OrNull(toString(properties.cost_usd))),4) usd, uniq(properties.model) models FROM events WHERE event='ai_generation_metered' AND timestamp > %s%s" % (SINCE, HOSTF))
cn = (cost[0][0] if cost and cost[0] else 0) or 0
cusd = (cost[0][1] if cost and cost[0] else 0) or 0
line("ok" if cn > 0 else "missing", "ai_generation_metered (cost)",
     "%d rows · $%s · %s models" % (cn, cusd, (cost[0][2] if cost and cost[0] else 0)) if cn else "0 rows — POSTHOG_PROJECT_TOKEN not on the pod, or no AI turns")

# 4. Server-side signup with method (SSO now counted!)
sm = hog("SELECT coalesce(nullIf(toString(properties.method),''),'(unset)') m, coalesce(nullIf(toString(properties.source),''),'client') s, count() n FROM events WHERE event='auth_signup_succeeded' AND timestamp > %s%s GROUP BY m, s ORDER BY n DESC LIMIT 8" % (SINCE, HOSTF))
has_server = any(r[1] == "server" for r in sm)
has_sso = any(r[0] in ("google", "github") for r in sm)
detail = ", ".join("%s/%s=%s" % (r[0], r[1], r[2]) for r in sm) or "no signups yet"
line("ok" if has_server else ("pending" if not sm else "warn"), "auth_signup_succeeded server-side",
     detail + ("" if has_server else "  <- want source=server"))
line("ok" if has_sso else "pending", "  └ SSO signups counted (google/github)",
     "yes" if has_sso else "none yet — needs a NEW google/github signup")

# 5. User-action events (0 is fine until someone does it)
print("\n-- Needs a user action (0 is OK until exercised) --")
for ev, label in [("ai_response_rated", "ai_response_rated (thumbs)"),
                  ("ai_issue_reported", "ai_issue_reported (down-vote picker)"),
                  ("generation_kept", "generation_kept (follow-up = kept)")]:
    n = one("SELECT count() FROM events WHERE event='%s' AND timestamp > %s%s" % (ev, SINCE, HOSTF))
    line("ok" if n > 0 else "pending", label, "%d rows" % n)

dep = hog("SELECT event, count() FROM events WHERE event IN ('deploy_sandbox_succeeded','deploy_sandbox_failed','deploy_production_succeeded','deploy_production_failed') AND timestamp > %s%s GROUP BY event ORDER BY 2 DESC" % (SINCE, HOSTF))
line("ok" if dep else "pending", "deploy_*_succeeded/_failed",
     ", ".join("%s=%s" % (e, n) for e, n in dep) or "0 — needs a deploy to complete (sandbox success was 0 before)")

# summary
print("\n=== %d flowing · %d pending-user-action · %d MISSING ===" % (PASS, PEND, FAIL))
if FAIL:
    print("Investigate MISSING: (1) is the frontend build deployed? (environment gate above)")
    print("                     (2) ai_generation_metered=0 -> POSTHOG_PROJECT_TOKEN on the pod?")
    print("                     (3) give it real traffic in the window, then re-run.")
else:
    print("All auto/server checks green. PENDING items just need a user to exercise them.")
print("Note: run against the env you deployed to first (dev deploys on merge to dev; prod on merge to main).\n")
