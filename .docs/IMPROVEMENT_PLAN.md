# Dashboard Improvement Plan — fixes + new features

> **STATUS 2026-07-28: P0 + P1 + P2 SHIPPED** (event-availability-gated: a prod probe
> confirmed upgrade_checkout_succeeded/ratings/issue-reports/session-end/edits/triggers
> are LIVE, so everything except `mrr_churn` was unblocked; `subscription_canceled`,
> `topup_checkout_succeeded`, UTM, and `cold_start` are still absent upstream, so their
> tiles were deliberately NOT built). Verified: 46/46 tests, curl per changed endpoint,
> browser pass on every touched page. **P3 remains open** (decision-gated, not
> event-gated). Deviations: dictionary status is derived via a new `event_liveness`
> endpoint; pin-everywhere landed as a zero-config `meta.key` contract (server stamps
> the registry key; Frame/StatTile show 📌 automatically).

Source: full sidebar walkthrough (live app) + code audit, 2026-07-28. Every item below was
verified against the running app; nothing is speculative. Ordered by trust impact — a
"directional but honest" dashboard dies by a thousand small wrong numbers, so P0 is the
glitches that make correct data look wrong.

Legend: **[fix]** correctness/trust · **[feat]** new capability · **[ux]** polish ·
**[docs]** honesty-layer sync · ⛔ = blocked on something outside this repo.

---

## P0 — Trust fixes (small, do first; ~½ day total)

### 0.1 [fix] Feature adoption shows 108%
`feature_table` (metrics_sv.jac) divides per-feature users by "actively-building users";
`ide_opened` users exceed that denominator → 108%.
**Do:** switch the denominator to `uniq(person_id)` across ALL tracked feature events in
range (superset), or cap at 100% and relabel the column "share of feature users".
**Accept:** no cell > 100%; caveat text matches the actual denominator.

### 0.2 [fix] Funnel reads non-monotonic (Created project 89 → Sent AI msg 110)
Steps are independent event counts, not a strict subset chain — but rendered as a funnel
it reads broken.
**Do (either):** (a) compute each step as users who did step N *and all prior steps*
(true funnel), or (b) keep counts but retitle "Journey milestones (independent counts)"
+ caveat. (a) is the honest fix; PostHog FunnelsQuery gives it for free if we switch
from raw counts.
**Accept:** monotonically non-increasing bars, or explicit independent-counts labeling.
Appears on Overview + Users — one metric (`funnel`), one fix.

### 0.3 [fix] Retention grid shows junk empty cohorts
Cohorts 2026-06-21/06-28 have N=0 (artifact of the hardened jachammer.ai-only prod
filter — pre-cutover signups lived on the dead old domain).
**Do:** drop rows with N=0 in the retention shaping (server), and add a one-line caveat
"cohorts before 2026-07 predate the domain cutover and are excluded".
**Accept:** no all-zero rows; caveat present.

### 0.4 [fix] Deploy outcomes don't reconcile (121 clicks → 56 ok + 12 fail; 53 missing)
**Do:** add a "no outcome recorded" column to `deploy_outcomes` (clicks − ok − fail) so
the gap is visible instead of implicit; AND render the already-defined-but-never-shown
`deploy_success` scalar on System Health with the caveat it already carries.
**Accept:** rows sum; success-% tile visible on Health.

### 0.5 [fix] Raw failure-reason strings (full 504 HTML blob) on 3 pages
`ai_fail_reasons` renders verbatim `properties.reason` — one bar label is an entire 504
HTML page. Shown on AI Requests, AI Quality, Advanced.
**Do:** normalize server-side into failure families (the `issue_log` metric already has
the family mapping — reuse it): 504/gateway-timeout, agent-no-response, turn-in-flight,
redis-connection, fetch-failed, server-restart, model-removed, other(truncated 80 chars).
**Accept:** no HTML in any bar label; families stable across pages; counts unchanged in
total.

### 0.6 [fix] Bottom-of-page orphan tiles
Undo rate (Advanced) and AI failure rate (Health) render below the full-width
Insights/HogQL/banner blocks — they look like accidents.
**Do:** move them up into their pages' KPI rows.
**Accept:** no stat tile below a full-width block on any page.

---

## P1 — Honesty-layer resync (~½ day; the dashboard's brand is honesty, and it has drifted)

### 1.1 [fix→feat] Data dictionary: derive 🟢/🟡/🔴 from live data, not hardcoded strings
Settings' dictionary marks `ai_response_rated`/`ai_issue_reported` 🔴 and
`ai_generation_metered` 🟡 — while Feedback shows a live 73.3% helpful rate and Cost
shows 755 metered runs. Hardcoded status is guaranteed to rot.
**Do:** extend `event_usage()` to also return per-event prod counts (last 14d, one cheap
grouped HogQL query) → status becomes computed: 🟢 events seen, 🔴 zero events, 🟡 only
when a config flag is known-unset (transcripts). Keep the hand-written rows as the event
LIST, compute the STATUS.
**Accept:** dictionary status agrees with what other pages display, permanently.

### 1.2 [docs] Add the ~10 missing events to the dictionary
`ai_response_edited`, `ide_session_ended`, `upgrade_checkout_succeeded`,
`subscription_canceled`, `subscription_downgraded`, `ai_turn_transcript`,
`topup_checkout_succeeded`, plus properties `model`, `conversation_id`/`turn_number`,
UTM set. Sync with EVENT_CATALOG.md (source of truth).

### 1.3 [docs] Update stale banners + docs to match shipped reality
- TRACKING_GAPS.md §C-12/§C-13 still say ratings/issue UI "not launched" — they are live.
- Advanced page privacy banner: "we never store what users type" → qualify with the
  `ai_turn_transcript` path existing but disabled in prod (`JAC_STORE_AI_TRANSCRIPTS`
  unset).
- Settings Access card: "Admin email allowlist gates the app" is not what the code does —
  say "single admin account, JWT-gated; no RBAC".
**Accept:** zero contradictions between banners, dictionary, TRACKING_GAPS, and live tiles.

### 1.4 [fix] Overview gets an honesty banner (only Explore page without one)
One line: what "prod" means (jachammer.ai-only filter + env tag), and that KPI deltas
compare to the previous equal-length window.

---

## P2 — Missing surfaces (new features; ~1–2 days)

### 2.1 [feat] NEW PAGE: Revenue / Monetization  ← biggest structural hole
The money loop has no sidebar home: `upgrade_conversion` + `mrr_churn` exist in the
registry with ZERO UI; `paid_upgrades`/`upgrades_detail` are only inside the Reports
template; the friction log shows "Upgrade checkout failed ×21" with no page to follow up.
**Build:** `components/pages/RevenuePage.cl.jac`, sidebar under Explore ("Revenue"),
one metrics_batch call. Tiles:
- KPI row: MRR (from `billing_summary()` — already live), Paid upgrades (`paid_upgrades`),
  Upgrade conversion % (`upgrade_conversion`), MRR churn (`mrr_churn` — honest-empty until
  `subscription_canceled` ships ⛔ upstream).
- `upgrades_detail` table (who upgraded, plan, when).
- Checkout funnel: `upgrade_checkout_clicked` → succeeded → (fail count from friction
  families) — new small metric `checkout_outcomes`.
- Margin tile reused from Cost (same computation, one source function).
**Accept:** page live with ≥5 tiles; empty tiles carry "awaiting event X" caveats, not
blanks.

### 2.2 [feat] Pin from every tile (make "My Dashboard" a real dashboard)
Pin infra (`pin_add`/`run_pinned`) is server-complete but only Ask exposes 📌.
**Do:** add a pin affordance to StatTile + the ChartTiles header (recipe =
`{mode:"metrics", keys:[key]}` — verify `run_pinned` replays registry-key recipes; extend
if it's SQL-only). Grey-out/toast when already pinned.
**Accept:** any registry-backed tile on any static page can be pinned and re-runs live on
My Dashboard.

### 2.3 [feat] AI Quality gets its flagship metrics
- Add Helpful rate (`rating_ratio`) tile to QualityPage (banner already promises it).
- NEW metric `rating_weekly` (thumbs series) → LineTile on Quality AND Feedback ("no
  ratings trend" gap).
**Accept:** Quality shows rate + trend; Feedback shows trend; small-N caveat carried.

### 2.4 [feat] Feature Usage: per-feature trend + stickiness
- NEW metric `feature_weekly` (top-6 features × `{bkt}` series) → multi-line chart,
  categorical palette (dataviz rules).
- Optional stickiness = DAU/MAU per feature (defer if noisy at current volume).
**Accept:** page has ≥3 tiles incl. a trend; no >100% anywhere (depends on 0.1).

### 2.5 [fix] Users directory honors the global date picker
Server hardcodes `INTERVAL 30 DAY`; the header picker silently no-ops.
**Do:** thread `date_from`/`date_to` through `user_list` (+ UserPeek panels), or —
cheaper — visually disable the picker on this page with a "fixed 30d" chip. Prefer
threading; the SQL change is mechanical.
**Accept:** changing the range changes the table (or the picker is visibly inert here).

### 2.6 [ux] Directory replay-fetch error surfaced
`_fetch_recordings` swallows non-200s → empty list looks like "no replays".
**Do:** return `{error}` like every other panel; UserPeek renders the reason.

---

## P3 — Capability tier (bigger; decision-gated)

### 3.1 [feat] Alerts / scheduled digest (Reports R4)
Everything today is pull; nobody finds out failure-rate spiked unless they look.
Blockers are known: APScheduler not in runtime (fix: `jac install apscheduler`),
no SMTP/Slack config ⛔ (needs a webhook URL or `[scale.emailer]` decision), viewer-role
accounts ⛔ (product decision).
**Minimal viable slice (not blocked):** a `check_alerts()` scheduled server job +
in-app "Alerts" bell in AppShell reading a per-user Alert node; thresholds on
failure_rate / total_spend / exception_total vs previous window. Delivery to
Slack/email only after the config decision.
**Accept:** threshold breach visible in-app within one schedule tick.

### 3.2 [feat] Reports R4 remainder — scheduled rebuild + `mode="live"`
After 3.1's scheduler exists: cron-rebuild flagged reports; implement the documented
`mode="live"` (auto re-run on open). Share-viewer role stays ⛔ product decision.

### 3.3 [feat] Cache prewarm (kill the 15–25s cold loads)
Cold first-visit per page is 15–25s (uncached batch + PostHog rate-gate); warm is
instant.
**Do:** on boot + every N minutes (piggyback 3.1's scheduler), server-side warm the
per-page key lists for `prod` + current default range. Optionally an AppShell
"warming cache…" hint instead of bare skeletons.
**Accept:** first paint of every page < 3s after a warm cycle.

### 3.4 [feat] Infra health on System Health
Explicit permanent gap today. Cheapest real slice: uptime probe of jachammer.ai
(scheduled HEAD + latency history via 3.1's scheduler) + link-out card to the internal
monitoring system. Full jac-scale Prometheus (CPU/mem/pods) only if wanted ⛔ infra
access.

### 3.5 [fix] HogQL box admin gate
Code comment says "gate behind admin auth before shipping externally" — currently any
logged-in user. Check jac-scale role == `admin` in `run_adhoc` (login already returns
`role`).

### 3.6 [chore] Registry + code hygiene
- Remove or wire orphaned metrics: `model_mix`, `issue_categories` (superseded),
  `signups_total`, `preview_reliability_weekly`, `revert_weekly`,
  `signup_trigger_breakdown` (gets a home on Users once the event ships ⛔).
- Dead `RetentionTile` import (Overview); blank `caveat=` params on
  `total_spend`/`cost_per_request`/`cost_per_user` — write real caveats.
- AppShell: scope-count stuck "counting events in scope…" on persistent failure →
  show "n/a (PostHog unreachable)"; tz switch does a full reload (known, low priority).

---

## ⛔ Upstream (jac-ide repo / prod config — not fixable here, track in TRACKING_GAPS)
- `model` missing on ~48% of AI requests and 21% of tracked spend "(blank)" — property
  must be stamped on every `ai_message_*` / `ai_generation_metered` emit path.
- UTM/referrer capture (`acquisition_channel` reads all-"direct").
- `subscription_canceled`/`subscription_downgraded` (unblocks `mrr_churn`).
- `cold_start` on `preview_ready` (un-flatters preview reliability).
- `ide_session_ended` coverage (session_depth confidence).
- `JAC_STORE_AI_TRANSCRIPTS` decision (transcript analytics vs privacy banner).

## Suggested execution order
1. **P0 (all)** — one sitting, pure trust recovery.
2. **P1** — dictionary liveness derivation is the only real code; rest is text.
3. **2.1 Revenue page** → **2.2 pin-everywhere** → **2.3/2.4** → **2.5/2.6**.
4. **P3**: 3.3 prewarm and 3.5 admin-gate are unblocked quick wins; 3.1 minimal alerts
   next; 3.2/3.4 after their decisions.

Verification bar for every item: `jac start` compiles, `jac test metrics_sv.jac` green
(add tests for changed shapers: funnel monotonicity, failure-family mapping, adoption
denominator), and a browser pass of the touched page — same standard as everything else
in PROGRESS.md.
