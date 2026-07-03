# JacHammer Burn-Phase Dashboard — Build Spec

> **Audience:** the team building the standalone internal metrics app.
> **Job of the dashboard:** answer *"is the bet compounding?"* in 30 seconds. Almost every tile is a **slope** (this period vs. last), not a snapshot.
> **Data path (decided):** standalone internal app → its **own backend** holds the PostHog `phx_` personal key → calls PostHog **HogQL Query API** (`POST /api/projects/425465/query/`) → frontend requests tiles **by name**, never sends SQL, never sees the key.
> **Status of this doc:** every "✅ powerable" query below was run against live data on 2026-06-24. Live values are inlined so you can sanity-check your wiring against the same numbers.

---

## 0. TL;DR — what the data already tells us

Verified against live PostHog (project `425465`):

| Signal | Reading | Verdict |
|---|---|---|
| **Activation rate** (signup → first successful build) | **60–92%** weekly | 🟢 strong |
| **Time-to-value** (signup → first build, median) | **9 min** (p25 4, p75 27) | 🟢 strong |
| **Generation success rate** (completed/sent) | **~72–91%** | 🟢 healthy |
| **W1 retention** (signup cohort → built again next week) | **9–26%** | 🔴 the leak |
| **W4 retention** | **0–3%** | 🔴 **the fire** |
| **Preview reliability** (ready/requested) | **~50%** most weeks | 🟠 broken half the time |

**The product story this board must tell:** we are *excellent at first impressions and terrible at second dates.* Burn spent on acquisition is filling a leaky bucket. The dashboard's #1 job is to make that impossible to ignore, and to track whether each new cohort's retention slope bends up.

---

## 1. Architecture — the metric registry pattern

The backend owns a registry. One entry per tile. The frontend asks for `{metric, range}` and gets back a clean, already-zipped series.

```
# backend: METRICS registry (pseudocode)
METRICS = {
  "north_star_builders": {
    "source": "posthog_hogql",
    "unit": "builders",
    "color_rule": "slope_up_good",
    "hogql": "SELECT toStartOfWeek(timestamp) wk, count(DISTINCT person_id) v FROM events WHERE event IN ('preview_ready','ai_message_completed') AND {range} GROUP BY wk ORDER BY wk"
  },
  ...
}
```

**Hop 1 (backend → PostHog):** `POST https://us.posthog.com/api/projects/425465/query/`, header `Authorization: Bearer phx_...`, body `{"query":{"kind":"HogQLQuery","query":"<sql>"}}`. Response: read **only** `columns`, `results` (positional arrays!), `types`, `error`. Discard the other ~25 fields.

**Hop 2 (frontend → backend):** request `{ "metric": "north_star_builders", "range_days": 84 }` → response `{ "success": true, "unit": "builders", "series": [{"wk":"...","v":82}, ...], "cached_at": "..." }`. Backend zips `columns`+`results` into named objects and layers a ~60s cache on top of PostHog's own.

**Security:** the `phx_` key is read/write to the entire PostHog project. It lives only in the backend env. The frontend never receives it and never sends raw SQL (no injection surface, SQL is version-controlled in the registry).

---

## 2. Event mapping — spec schema vs. what we actually fire

The idealized event schema in the dashboard brief **does not match our taxonomy.** Reconciliation (verified against the live event catalog, last 30d volume in parens):

| Brief event | Our real event | Status |
|---|---|---|
| `signup` | `auth_signup_succeeded` (663) | ✅ |
| `project_created` | `project_created` (1318) | ✅ |
| `generation_requested` | `ai_message_sent` (1805) | ✅ |
| `generation_succeeded` | `ai_message_completed` (1404) | ✅ |
| `generation_failed {error_type}` | `ai_message_failed` (264) — has `reason`, `at_phase` | ✅ |
| `app_previewed` | `preview_ready` (1623) | ✅ |
| `app_deployed` | `deploy_sandbox_succeeded` | ⚠️ **barely fires** — not in top 60; `deploy_sandbox_clicked`=28, success ~0 |
| `generation_kept` (the "actually-worked" signal) | — | ❌ **GAP** — we only have the *inverse* `ai_message_reverted` (172) |
| `project_abandoned {last_stage}` | — | ❌ **GAP** — abandonment is never evented; must be inferred |
| `subscription_started {mrr}` / `subscription_canceled` | — | ❌ **GAP** — not in PostHog; lives in **Stripe** |
| `tokens_in/out, model` on generations | `ai_generation_metered {cost_usd, model}` 🆕 | ✅ **FIXED (pending deploy)** — backend now emits the real metered **$ cost** per turn to PostHog (`jaccoder_client.jac`). Tokens themselves still not sent — only the computed cost + model. |

### Property notes found while verifying
1. **`token` property — NOT a bug (corrected).** `properties.token` shows up on *every* event with the public `phc_` token. It's PostHog's standard ingestion field (the project API key every `posthog-js` payload carries), not something our code sets, and the `phc_` token is public-by-design. No leak, no action — just don't mistake it for LLM tokens.
2. **`tool_call_count` — FIXED.** Was always `0.0`: the filter counted `type=="activity"` / `type=="agent_tool_done"`, but real tool calls are stored as `type=="llm_tool_call"`. Corrected in `useChatMode.cl.jac`. `files_changed` remains the primary work-done proxy.

---

## 3. The tiles — per-tile build spec

Legend: **✅ powerable now** (PostHog only) · **⚠️ partial** (works as proxy; full version needs a new event) · **🔒 blocked** (needs Stripe / credit-ledger / new source).

Color rule convention (burn-phase): **green = slope is right, even if the absolute number is ugly.** A bad-but-improving W4 retention is green; a great-but-flattening retention is amber.

---

### SECTION 1 — THE BET

#### 1.1 North Star — Weekly Active Builders who ship ✅
- **Question:** is real value delivered, and growing?
- **Definition:** distinct users who got `preview_ready` OR `ai_message_completed` in the week.
- **HogQL (verified):**
  ```sql
  SELECT toStartOfWeek(timestamp) wk, count(DISTINCT person_id) builders
  FROM events
  WHERE event IN ('preview_ready','ai_message_completed')
    AND timestamp > now() - INTERVAL 12 WEEK
  GROUP BY wk ORDER BY wk
  ```
- **Live:** 11 → 56 → 76 → 82 → 67 → 70 → 24*  (*current week partial)
- **Color:** slope_up_good. **Frontend key:** `north_star_builders`.

#### 1.2 Activated-user retention slope ✅ (data is grim — that's the point)
- **Question:** do people keep coming back, and *more* than last cohort? The line must bend **up**.
- **Tool:** PostHog native **RetentionQuery** (handles cohort math; don't hand-roll).
- **Request body (verified):**
  ```json
  {"query":{"kind":"RetentionQuery","retentionFilter":{
     "period":"Week","totalIntervals":6,
     "targetEntity":{"id":"auth_signup_succeeded","type":"events"},
     "returningEntity":{"id":"ai_message_completed","type":"events"},
     "retentionType":"retention_first_time"},
   "dateRange":{"date_from":"-6w"}}}
  ```
- **Live (W0→W5 by cohort):** `05-17` 100/26/10/3/3/3 · `05-24` 100/13/15/12/3/0 · `05-31` 100/9/7/3/0/0 · `06-07` 100/10/2/0/0/0. **Plot the W4 column across cohorts as the slope tile.**
- **Color:** slope_up_good (currently **flat-to-down → red**). **Frontend key:** `retention_w4_slope`.

#### 1.3 Margin slope (cost-per-active falling vs. revenue-per-active rising) ⚠️ HALF-UNBLOCKED
- **Question:** does this get profitable eventually?
- **Cost side ✅ (pending deploy):** `ai_generation_metered {cost_usd}` now carries the real metered spend into PostHog. Cost-per-active-user = `SUM(cost_usd) / distinct active person_id` — pure HogQL, no ledger join. Populates once shipped.
- **Revenue side 🔒:** still needs MRR (Stripe) — not in PostHog.
- **Frontend key:** `margin_slope` (cost line live after deploy; revenue line still `🔒 needs Stripe`).

---

### SECTION 2 — THE ENGINE

#### 2.1 Activation rate ✅
- **Question:** % of new signups who reach a successful first build.
- **HogQL (verified):**
  ```sql
  SELECT toStartOfWeek(s.ts) wk,
         count(DISTINCT s.person_id) signups,
         count(DISTINCT b.person_id) activated,
         round(100.0*count(DISTINCT b.person_id)/nullIf(count(DISTINCT s.person_id),0),1) pct
  FROM (SELECT person_id, min(timestamp) ts FROM events WHERE event='auth_signup_succeeded' GROUP BY person_id) s
  LEFT JOIN (SELECT DISTINCT person_id FROM events WHERE event='ai_message_completed') b
    ON s.person_id=b.person_id
  WHERE s.ts > now() - INTERVAL 12 WEEK
  GROUP BY wk ORDER BY wk
  ```
- **Live:** 80.6% → 73.1% → 60.8% → 84.0% → 64.7% → 91.7%. **Color:** slope_up_good. **Key:** `activation_rate`.

#### 2.2 Time-to-first-shipped-app (median) ✅
- **Question:** how fast is the aha moment? Should trend **down**.
- **HogQL (verified):**
  ```sql
  SELECT round(median(diff_min),1) median_min,
         round(quantile(0.25)(diff_min),1) p25,
         round(quantile(0.75)(diff_min),1) p75, count() n
  FROM (
    SELECT dateDiff('minute', s.ts, b.ts) diff_min
    FROM (SELECT person_id, min(timestamp) ts FROM events WHERE event='auth_signup_succeeded' GROUP BY person_id) s
    INNER JOIN (SELECT person_id, min(timestamp) ts FROM events WHERE event='ai_message_completed' GROUP BY person_id) b
      ON s.person_id=b.person_id
    WHERE b.ts >= s.ts AND s.ts > now() - INTERVAL 30 DAY)
  ```
- **Live:** median **9 min** (p25 4, p75 27, n=149). **Color:** slope_down_good. **Key:** `ttfv_minutes`.
- **Note:** "shipped" here = first successful *build*, not *deploy* (deploy barely fires — see 1.1/§2 mapping). Rename the tile honestly: **"time-to-first-working-build."**

#### 2.3 Activation funnel with drop-off ✅
- **Question:** *where* do new users die?
- **HogQL (verified, signup cohort = last 30d):**
  ```sql
  WITH s AS (SELECT DISTINCT person_id FROM events WHERE event='auth_signup_succeeded' AND timestamp > now() - INTERVAL 30 DAY)
  SELECT (SELECT count() FROM s) signed_up,
         countDistinct(if(event='project_created',person_id,NULL)) created_project,
         countDistinct(if(event='ai_message_sent',person_id,NULL)) sent_ai,
         countDistinct(if(event='ai_message_completed',person_id,NULL)) got_build,
         countDistinct(if(event='preview_ready',person_id,NULL)) previewed
  FROM events
  WHERE timestamp > now() - INTERVAL 30 DAY AND person_id IN (SELECT person_id FROM s)
  ```
- **Live:** 245 signed_up → 222 created_project → 194 sent_ai → 170 got_build → 190 previewed.
- **Note:** funnel is *shallow* (90% reach project creation) — the drop is NOT in onboarding, it's in **week-2 return** (Section 3). Use PostHog native **FunnelsQuery** if you want ordered step-conversion with time windows. **Color:** per-step drop-off %. **Key:** `activation_funnel`.

#### 2.4 Generation actually-worked rate ⚠️ PARTIAL
- **Question:** % where the user *kept/shipped* the output — not just "code compiled."
- **What we have:** success rate (completed/sent) ✅ **and** revert rate ✅. **Proxy = `1 − reverted/completed`.**
- **HogQL (verified, success rate):**
  ```sql
  SELECT toStartOfWeek(timestamp) wk,
         countIf(event='ai_message_completed') done,
         countIf(event='ai_message_sent') sent,
         round(100.0*countIf(event='ai_message_completed')/nullIf(countIf(event='ai_message_sent'),0),1) pct
  FROM events WHERE event IN ('ai_message_sent','ai_message_completed')
    AND timestamp > now() - INTERVAL 12 WEEK GROUP BY wk ORDER BY wk
  ```
- **Live success:** 75.8 → 74.5 → 76.9 → 90.9 → 72.2 → 80.5%.
- **Full version needs `generation_kept`** (see §4) — revert is a weak inverse (user undid it ≠ user ignored it). **Color:** slope_up_good. **Key:** `gen_worked_rate`.

---

### SECTION 3 — THE LEAK

#### 3.1 Retention curve, current vs. prior cohort ✅
- Same RetentionQuery as 1.2; render **two overlaid cohort curves** (latest vs. prior). **Key:** `retention_curve_overlay`.

#### 3.2 Churn rate (paid) + resurrection rate ⚠️/🔒
- **Resurrection** (came back after going quiet) ✅ — PostHog native **LifecycleQuery** (`new/returning/resurrecting/dormant`) on `ide_opened` or `ai_message_completed`.
- **Paid churn** 🔒 — needs Stripe `subscription_canceled`. Blocked. **Keys:** `lifecycle`, `paid_churn` (🔒).

#### 3.3 Iterations-per-project, split by outcome ⚠️ PARTIAL
- **Question:** high-iterations-then-shipped (healthy) vs. high-iterations-then-abandoned (AI's first output is failing them). **Never merge these two.**
- **What we have:** iterations = count of `ai_message_sent` per project ✅. **Outcome split is blocked** — needs `generation_kept`/`project_abandoned` to label a project shipped vs. abandoned.
- **Interim:** show iterations-per-project distribution **un-split**, labeled "outcome split pending instrumentation." **Key:** `iterations_per_project`.

#### 3.4 Where projects die (abandonment by stage) 🔒 BLOCKED → infer
- **Question:** % abandoned, bucketed by last stage (at prompt / mid-generation / after preview).
- **No `project_abandoned` event.** Two options:
  - **(a) Infer in HogQL:** for each project, find its last event; if no activity for N days, bucket by that last event type. Doable now, approximate.
  - **(b) Add `project_abandoned {last_stage}`** via a server-side sweep job (abandonment is an *absence* — hard to fire client-side reliably). Recommended for accuracy.
- **Key:** `abandonment_by_stage` (ship inferred v1, upgrade to evented).

---

### SECTION 4 — THE COST OF THE BET 🔒 (all blocked on PostHog; powered by ledger + Stripe)

None of these can come from PostHog. They are the "show + label as blocked" tiles — render them in the layout so the CEO sees the full vision, with a `🔒 needs ledger + Stripe` ribbon.

| Tile | Question | Status |
|---|---|---|
| **Total inference spend + cost/generation** | is model-routing/caching bending cost down? | ✅ **FIXED (pending deploy)** — `SUM(cost_usd)` / `avg(cost_usd)` from `ai_generation_metered`, pure HogQL |
| **Cost of top-10% power users** | celebrated by engagement, may be bleeding you | ✅ **FIXED (pending deploy)** — `SUM(cost_usd) GROUP BY person_id`, take the top decile |
| **Burn rate + runway (months)** | the clock everything races | ⚠️ spend ✅ (`ai_generation_metered`); runway still needs revenue (Stripe MRR) |
| **CAC by channel vs. value returned** | buying keepers or tourists? | 🔒 needs ad-spend (marketing) + revenue; PostHog has the denominator (`auth_signup_succeeded` by `provider`) |

The first two tiles are no longer blocked at all — `ai_generation_metered` carries the real metered `cost_usd` per turn, so cost/generation, total spend, cost-per-active-user, and power-user cost are all plain HogQL once the event ships. Only **revenue** (Stripe MRR) and **ad-spend** remain external.

**Partial unblock available now:** signup-by-channel (CAC denominator) and power-user identification are both PostHog-powerable — wire those, leave the $ numerators as `🔒`.

---

## 4. Instrumentation backlog (to fully light up the board)

Priority order for the team:

1. **`generation_kept`** — fire when the user keeps/accepts AI output (the positive of `ai_message_reverted`). Props: `{ project_id, files_changed, message_id }`. Unblocks 2.4 (true "actually-worked") + 3.3 (outcome split).
2. **`project_abandoned { last_stage, idle_days }`** — server-side sweep job; emit when a project has no activity for N days, stamped with its last stage. Unblocks 3.4 (accurate) + 3.3.
3. ~~Real LLM cost on generations~~ — ✅ **DONE (pending deploy):** backend emits `ai_generation_metered {cost_usd, model, project_id, run_id}` per turn (`jaccoder_client.jac`), so cost/gen + margin cost-side + power-user cost are HogQL-native. Only `cost_usd` + `model` are sent (not raw tokens) — enough for all cost/margin tiles. **Prod TODO:** add `POSTHOG_PROJECT_TOKEN` to the backend pod secret or it no-ops.
4. **`tool_call_count`** — ✅ fixed (`useChatMode.cl.jac`, now counts `llm_tool_call`). The `token` prop is PostHog's standard ingestion field, not a leak — no action.
5. **Deploy success** — `deploy_sandbox_succeeded` barely fires; verify the event is wired, since "shipped/deployed" is a Section-1/2 concept.

### The second data source (for Sections 1.3 + 4)
Don't shove dollars into PostHog. The dashboard backend should be a **2-source join**:
- **PostHog** (HogQL) → activity, funnels, retention, active-user counts.
- **App DB / credit ledger** → per-user/per-generation LLM cost.
- **Stripe API** → MRR, subscriptions, churn.

The backend computes margin/CAC/runway by joining active-user counts (PostHog) with cost (ledger) and revenue (Stripe). This keeps each number at its source of truth.

---

## 5. Dashboard rules (encode in the UI)

- **Every tile shows direction** — ▲/▼ vs. last period + % change. A number without a trend gets cut.
- **Color = decision, not vibe** — green only if the *slope* is right, even if the absolute is ugly.
- **Max ~14 tiles.** Anything that doesn't move a Section-1 slope lives in a secondary "diagnostics" view.
- **One "scariest number" callout box**, picked weekly. Right now it writes itself: **W4 retention ≈ 0–3%.** Pair with the experiment being run on it. An all-green board destroys CEO trust; this box builds it.

## 6. What the board can't tell you (pair with qual)
The dashboard shows *what* and *where* people die — never *why.* Bolt on **session replays on abandoned projects** (PostHog has them — already masked per `data-ph-mask`) + **~5 user interviews/week.** Given the retention cliff, interview users who built once and never returned — that's the highest-leverage qual we can run.

---

## 7. Build checklist
- [ ] Standalone app scaffold (own repo, own URL, internal auth/allowlist)
- [ ] Backend: `phx_` key in env (never to client) + HogQL proxy + ~60s cache
- [ ] `METRICS` registry: 7 ✅ tiles wired first (1.1, 1.2, 2.1, 2.2, 2.3, 2.4-proxy, 3.1)
- [ ] Lifecycle + funnel via native PostHog query kinds (RetentionQuery / LifecycleQuery / FunnelsQuery)
- [ ] Render blocked tiles (1.3, Section 4) with `🔒 needs ledger + Stripe` ribbons
- [ ] Scariest-number box (manual weekly pick) + ▲/▼ slope chrome on every tile
- [ ] Instrumentation backlog tickets filed (§4, items 1–5)
- [ ] Phase 2: ledger + Stripe join for margin/burn; `generation_kept` + `project_abandoned`

---

## 8. Appendix — Linjia's direct questions, answered from live data

Verified against PostHog (project 425465). These are the exec's literal asks; each maps to a tile above or exposes a gap.

| # | Question | Answer (live) | Source / gap |
|---|---|---|---|
| 1 | Signups per day/week/month | Weekly peaked **259** (May 24) → **14** (Jun 28), declining. Monthly: May 347, June 455. ~804 all-time. | ✅ `auth_signup_succeeded` |
| 2 | Active signed-in users | **DAU 11 · WAU 59 · MAU 422.** Logins/wk 310→17. | ✅ distinct `person_id` + `auth_succeeded` |
| 3 | Projects created (detail) | **1,726 all-time by 380 creators** (~4.5 each). Source split (30d): template 553, prompt 310, import 13, folder 10. Weekly peaked 533→33. | ✅ `project_created.source` |
| 4 | Sandbox / permanent deployments | ⚠️ **Intent only:** `deploy_production_clicked` 109, `deploy_sandbox_clicked` 30. **No success event fired.** | ✅ **FIXED (pending deploy)** — `deploy_{sandbox,production}_{succeeded,failed}` now fire on rollout settle (`useIDE.cl.jac`); data flows once shipped |
| 5 | Users by package (Pro/Builder) | ⚠️ Only guest(62)/registered(326) known. **No tier on any user.** | ✅ **FIXED (pending deploy)** — `plan` now set as a PostHog person property from `me.billing` (`useUserTier.cl.jac`); backfills historical events |
| 6 | Returning users | **32 returning this week** (of 59 WAU). %returning 7%→48% over 8w — but rising because acquisition fell, not because stickiness improved. Absolute returning flat ~40/wk. | ✅ cross-window distinct persons; pair with retention cliff |
| 7 | Time spent | **Median session 2.5 min**, avg 16 min (power-user tail), **95.5 hrs / 355 sessions** in 14d. | ✅ `$session_id` min/max timestamp |

**Two instrumentation fixes unblocked questions 4 & 5 — DONE (in code, pending prod deploy):**
1. ✅ `deploy_{sandbox,production}_{succeeded,failed}` now fire on rollout settle, gated by a `*DeployPendingRef` flag so they fire **exactly once** even when the backend jumps straight to `running` before the first poll (the old deploying→running transition guard missed that, which is why `deploy_sandbox_succeeded` sat at zero all-time). — `hooks/useIDE.cl.jac`
2. ✅ `plan` (free/builder/pro) set as a PostHog **person property** from `me.billing` on every tier load — `hooks/useUserTier.cl.jac`. PostHog backfills, so historical events gain the slice too.

> Note: neither shows data in PostHog until this ships to prod and users deploy / load a session. Verify post-deploy: `deploy_*_succeeded` count > 0 and persons carry a `plan` property.

**The one-line story:** acquisition cooling, activation excellent (9-min TTFV), retention is the problem — a loyal ~40-person core returns weekly while new users churn out by W4.

---
*All ✅ queries verified against live data. Re-run before relying on the inlined live values — they drift.*
