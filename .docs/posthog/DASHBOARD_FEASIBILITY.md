# JacHammer Dashboard — 11-Page Feasibility Map

What each proposed sidebar page can *actually* show, graded against our real data (PostHog project 425465 + credit ledger + Stripe + jac-scale metrics). Verified live 2026-07-02 by a 6-way parallel audit. Legend:

- ✅ **NOW** — powerable today with existing events/sources
- ⚠️ **PROXY** — approximate only; honest caveat required
- 🔧 **ADD** — needs a small new event/prop/config we can build
- 🔒 **EXTERNAL** — needs a system we don't have (Stripe / infra monitoring / feedback tool / ML)

---

## ⚠️ Reality #0 — ONE PostHog project ingests all environments (filter to prod or every number is wrong)

The same project 425465 receives events from **local dev, the dev deploy, CI/PR previews, AND prod**. Only end users touch prod. Measured 30-day host split:

| Host | Events | |
|---|---|---|
| `localhost` + `127.0.0.1` | ~12,400 | local dev |
| `jac-builder-dev.jaseci.org` | 7,559 | dev |
| `jac-builder-pr-*.jaseci.org` (×15+) | ~5,000 | CI / PR previews |
| **`jachammer.ai`** | 4,748 | ⭐ prod (current) |
| `jac-builder.jaseci.org` | 834 | ⭐ prod (pre-rebrand) |

**Only ~19% of events are real end users.** Unfiltered, MAU reads **409**; prod-only it's **154**. AI requests 1097 → **176**. Signups 804 → **34**. **Every query in the dashboard MUST scope to prod**, two ways:
- **Retroactive (historical data):** filter `properties.$host IN ('jachammer.ai','www.jachammer.ai','jac-builder.jaseci.org')`. Note `$host` is a JSON property (not materialized) → full-table scans; bound heavy join queries by time or **materialize `$host` in PostHog** to speed them up.
- **Forward (clean):** an `environment` super-property (prod/dev/preview/local) is now registered in `initAnalytics()` (`utils/analytics.cl.jac`) — new events carry it, so filter `properties.environment = 'prod'`.

The prototype's `gen_data.py` applies the retroactive host filter to every event scan. **The real Jac-app metric registry must do the same** (inject the prod filter into every HogQL string + native-query `properties`).

## Cross-cutting realities (these gate many items — decide once)

1. **Single-user product — no team / company / enterprise / workspace.** Accounts are individual roots; `project_id` is the only sub-user grain. → Drop every "team/enterprise" tile; reframe "workspace" as project, "segments" as **guest / free / builder / pro**.
2. **JacCoder is ONE general agent.** There are no discrete "features" like code-generation / bug-detection / code-review / refactoring, no per-request **task category**, and no per-request **programming language** (every app is Jac). → The mockup's "AI Requests by Language" donut and per-capability breakdowns are fiction. Drop or reinterpret.
3. **Zero explicit quality/voice signal.** No ratings, thumbs, accept/copy, edit-after-gen, NPS, survey, support tickets, or feature-request board exist. Only behavioral proxies: `ai_message_reverted`, `ai_user_aborted`, `files_changed`, success ratio.
4. **Cost yes, tokens no.** Real per-turn `$` is captured (`UserCostEntry` ledger + the new `ai_generation_metered`), but `tokens_in/out` are computed then discarded. Revenue/MRR/trial/paid live in **Stripe**, not PostHog.
5. **Infra health isn't in PostHog — but the tooling exists.** jac-scale monitoring (Prometheus + metrics-server) is already wired for *users' deployed apps* (`get_prometheus_series`, `get_pod_resource_metrics` in `deploy_manager.jac`) and enabled on the platform (`jac.toml [plugins.scale.monitoring]`). Repointing it at the `jac-builder` namespace unblocks CPU/mem/API-P95/5xx — reuse, not net-new.
6. **Pending-deploy items are empty today:** `ai_generation_metered` (0 rows — needs `POSTHOG_PROJECT_TOKEN` on the prod pod), `plan` person prop (null on all users), `deploy_*_succeeded` (0), `tool_call_count` fix (still 0). All coded; all light up post-deploy/config.

---

## Page readiness at a glance

| # | Page | Readiness | One-line verdict |
|---|---|---|---|
| 1 | **Overview** | 🟢 Ready | KPI row + usage/problem panels live; token/satisfaction/uptime = stubs |
| 2 | **Users & Adoption** | 🟢 Strongest | ~10/13 live; cut team/enterprise; signup-source & churn need adds/Stripe |
| 3 | **Feature Usage** | 🟡 Half | adoption/usage/trend live for our ~12 real features; completion/error only for 3 |
| 4 | **AI Requests** | 🟢 Ready | 8/11 live; language=N/A; task-category+response-length trivial adds |
| 5 | **AI Quality** | 🔴 Blocked | only failure+latency live; needs 1 rating event to unlock ~6 items |
| 6 | **Developer Impact** | 🟡 Thin | 2 honest tiles (accept-rate, code-produced); rest estimation/instrumentation |
| 7 | **Cost & Usage** | 🟢 Ready (cost) | cost/user/model/heavy/abnormal live; tokens dropped; revenue=Stripe |
| 8 | **System Health** | 🟡 Split | app-level live from PostHog; infra strip = repoint jac-scale metrics 🔧 |
| 9 | **Feedback & Roadmap** | 🔴 External | no feedback system; PostHog Surveys for NPS + failure-proxy for "complaints" |
| 10 | **Advanced Analytics** | 🟢 (as heuristics) | churn/failure/anomaly/journey ship as honest rules; prompt-clustering blocked |
| 11 | **Settings & Data** | 🟡 Split | PostHog controls already configured; app RBAC doesn't exist (allowlist only) |

---

## Per-page detail (key items)

### 1 · Overview
✅ Active users (DAU 10/WAU 55/MAU 409) · Total AI requests (1,097/30d) · Median response time (**132s**, use median) · Top feature (preview + AI dominate) · Top problem (`ai_message_failed.reason` → mostly **504/timeout**) · Growth (signups 259→14, declining).
⚠️ AI-quality score (1−revert/completed ≈ 80%) · System-health tile (preview reliability ~64%).
🔧/🔒 Token usage (cost-only, post-deploy) · **User satisfaction** (🔒 feedback system) · **True uptime** (🔒 infra monitor). Alerts = backend threshold rules over the ✅ queries.

### 2 · Users & Adoption
✅ Total/new users · DAU/WAU/MAU · new-vs-returning (native **LifecycleQuery**) · activation (60–92%) · retention heatmap (native **RetentionQuery**, W4≈0–3%) · onboarding funnel (245→222→194→170→190).
⚠️ churn-risk (dormant + export cohort) · segment table (by **plan** only, pending deploy).
🔧 signup-source — only **auth-method** today; real UTM/referrer capture = add to posthog init (M).
🔒 trial-vs-paid, paid churn (Stripe). ❌ team/enterprise segments — don't exist.

### 3 · Feature Usage
**Real feature set** (replace mockup's fictional rows): AI build/chat · live preview · project creation · deploy · git · github · export · community share · templates · folder upload · inspector · model-switch · tab-nav.
✅ most/least-used, adoption rate (% of MAU), usage-over-time — all `count(DISTINCT person_id)`/week HogQL.
⚠️ completion & error rate exist **only** for AI, preview, deploy (paired start/end). Render **n/a** for single-shot features; don't fake. deploy-success=0 until pending fix; git/share/inspector near-zero volume.

### 4 · AI Requests
✅ total · per-day · per-user · prompt-length (avg 432 chars) · success/failure + reason breakdown · peak times (09–12 UTC).
🔧 response-length (add `.length` in `useChatMode._handleDone`, ~10 min) · task-category (keyword heuristic prop, ~1–2h — **not** a synchronous LLM classifier).
⚠️→✅ model & token/cost — via `ai_generation_metered` once `POSTHOG_PROJECT_TOKEN` is set (config). ❌ programming language — N/A, Jac-only.

### 5 · AI Quality  — *the biggest gap*
✅ failure rate (+ "slow" from `duration_ms` p95).
⚠️ weak proxies: revert-rate, abort-rate, files_changed>0.
🔧 **Everything else needs one event.** `ai_response_rated {rating, message_id, model, task_category}` (thumbs up/down in `ChatPanel`, ~2–3h) unlocks helpful/not-helpful/avg-rating/low-rated/quality-by-model at once. `ai_issue_reported {category}` (down-vote picker, folds into same UI) unlocks hallucination + issue categories. `generation_kept` = true acceptance.

### 6 · Developer Impact
✅→⚠️ **code acceptance rate** = (completed−reverted)/completed ≈ **91%** (best real tile) · **code produced** = `sum(files_changed)`.
🔧/estimation: hours-saved & ROI (documented constant × accepted-turns — label "estimated") · bugs/tests/docs (need per-file **path list** on completion, not just count) · team impact (no team dim → per-user/per-project only). Be blunt: most of this page is estimation until a per-file accept/reject event exists.

### 7 · Cost & Usage
✅ cost/request · cost/user · cost/model · heavy users · abnormal usage · high-cost alerts — from `UserCostEntry` ledger **now** and `ai_generation_metered` post-deploy.
⚠️ cost/workspace (=project_id) · free-trial cost (join distinct_id→tier).
🔒 revenue/account, gross margin, usage-vs-revenue (Stripe offline join — cost side ✓). ❌ token tiles — not captured; drop or defer (byLLM has counts; ~2-field add if ever needed, low priority).

### 8 · System Health
✅ app-level from PostHog: error rate (`$exception` + failure ratios) · AI latency (`duration_ms` P50/P95) · preview latency/reliability (~64%) · failed-request breakdowns (`ai_message_failed`, `preview_start_failed`, `auth_failed`).
🔧 infra (cheap — reuse existing code): API-P95 + 5xx (`get_prometheus_series`) · CPU/mem (`get_pod_resource_metrics`) — repoint at `jac-builder` namespace.
🔒 uptime (external probe) · timeout rate · queue depth · DB perf · third-party status · incidents. Service-status table = hybrid degraded-heuristic (app rows ⚠️, infra rows 🔒).

### 9 · Feedback & Roadmap
🔒 support tickets, feature requests, roadmap status/kanban, impact-vs-effort, customer priority — **external tools** (Zendesk/Canny/Linear); embed, don't fake.
🔧 **NPS/CSAT/user-feedback → PostHog Surveys** (posthog-js already loaded — lowest-lift real add).
⚠️ "common complaints / top problem area" = cluster `$exception` + `*_failed.reason` + `reverted`/`aborted` (one HogQL union; blank `$exception` msgs = "unknown").

### 10 · Advanced Analytics (as honest heuristics, not ML)
✅ churn-risk / accounts-at-risk (existing cohort: `export_downloaded` + 7d-silence, rank by recency) · failure-pattern detection (group `reason`/`phase`) · anomaly detection (daily vs 7d ±Nσ + native PostHog alerts) · user-journey flow (native **Funnels/Paths**).
⚠️ forecasting (naive trend) · behavior clustering (named rule-segments) · AI insights & recommended-actions (byLLM one-shot over the tile numbers — label "generated").
🔒 **prompt clustering** — prompt text is never captured (masked); needs new instrumentation + privacy review + embeddings.

### 11 · Settings & Data Controls
✅ (PostHog-side, mostly already configured in `utils/analytics.cl.jac`): privacy/masking (`maskAllInputs`, code/editor mask, `identified_only`, `optOut()`) · data retention · export · alerts · event-tracking allowlist — surface as **read-only status + deep links**.
🔧 **admin access** = env-var email allowlist / shared-password gate (mirrors `chat_view.jac`) — the dashboard-viewer control.
🔒 user roles, team permissions, RBAC matrix — **no role model exists**; only honest table is "admin vs everyone." Don't render a fake permissions matrix.

---

## Highest-leverage additions (ranked by value ÷ effort)

1. **Set `POSTHOG_PROJECT_TOKEN` on the prod pod** — *config, 0 code.* Turns on `ai_generation_metered` → real cost + per-request model across Overview / AI Requests / Cost / Quality-by-model. **Do this first.**
2. **`ai_response_rated {rating, message_id, model, task_category}`** — thumbs up/down in `ChatPanel` (~2–3h). Single biggest gap-closer: unlocks ~6 AI-Quality items.
3. **`ai_issue_reported {category}`** — down-vote category picker, same UI (~2–3h). Unlocks hallucination + issue-category taxonomy.
4. **Repoint jac-scale metrics** (`get_prometheus_series` / `get_pod_resource_metrics`) at the `jac-builder` namespace — unlocks System-Health infra strip (API-P95, 5xx, CPU/mem) from existing code.
5. **`generation_kept {message_id, files_changed}`** — the true "actually-worked"/acceptance signal (also burn-spec backlog #1) (~½ day). Powers Dev-Impact accept + AI-Quality acceptance.
6. **Enable PostHog Surveys** — NPS + post-completion CSAT targeted at the Power-users cohort (config). The one real Feedback-page add.
7. **Three cheap props in one `useChatMode` pass** (~2–3h): `response_length`, `task_category` (keyword heuristic), `is_regeneration` flag from `resendMessage` → unlocks response length, task distribution, regeneration rate.
8. **UTM/referrer capture** in posthog init (M) → real acquisition-channel signup source.
9. **Ship the already-coded pending fixes** — `deploy_*_succeeded`, `plan` person prop, `tool_call_count` — to populate their zero-row tiles.

---

## Recommended v1 build order

**Tier 1 — ship now, mostly live data:** Overview · Users & Adoption · AI Requests · Cost & Usage · Advanced Analytics (labeled heuristics).
**Tier 2 — ship after 1–2 small adds:** Feature Usage (real feature list) · System Health (app-level now + infra repoint) · AI Quality (after `ai_response_rated`).
**Tier 3 — mostly external / estimation, ship last:** Developer Impact (2 honest tiles + labeled estimates) · Feedback (Surveys + failure-proxy) · Settings (status + viewer allowlist).

**Guiding rule everywhere:** where data doesn't exist, render an honest "needs X" stub — never a fabricated number. The exec-trust win is the same one from the burn board: a labeled gap beats a confident lie.
