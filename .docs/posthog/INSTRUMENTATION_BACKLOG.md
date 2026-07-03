# Analytics Instrumentation Backlog — ranked

The single source of truth for what's instrumented, what's pending, and what to add next so the
**real** JacHammer dashboard doesn't inherit the prototype's gaps. Incorporates the 2026-07-02
assumption audit. Legend: **[SHIPPED-CODE]** = in code on `dev`, not deployed → produces no data yet ·
**[CONFIG]** = no code, needs a settings/ops change · **[ADD]** = new work.

---

## A. Shipped in code, pending prod deploy (verify once live)

All compile (`jac check` PASSED) but emit **zero data** until deployed. **After deploy, run the harness:**
```bash
python3 .docs/posthog/verify_deploy.py          # last 3 days, all envs
python3 .docs/posthog/verify_deploy.py 3 prod   # prod hosts only
```
It checks every event/property below and prints a green/red checklist ([OK] flowing · [MISSING] not deployed / token missing · [PENDING] needs a user action). The `environment` super-property is the deployment gate; `ai_generation_metered` is the token gate.

| Item | File | Verify |
|---|---|---|
| `deploy_{sandbox,production}_{succeeded,failed}` | `hooks/useIDE.cl.jac` | `deploy_*_succeeded` count > 0 |
| `plan` person property (free/builder/pro) | `hooks/useUserTier.cl.jac` | persons carry `plan` |
| `ai_generation_metered {cost_usd, model, project_id, run_id}` | `services/jaccoder_client.jac` | rows > 0 (also needs §B.1) |
| `tool_call_count` fix (counts `llm_tool_call`) | `hooks/useChatMode.cl.jac` | value > 0 on new completions |
| `task_category` on `ai_message_sent` | `hooks/useChatMode.cl.jac` | prop present, non-"other" mix |
| `response_length` on `ai_message_completed` | `hooks/useChatMode.cl.jac` | prop present |
| `ai_response_rated {rating, message_id, files_changed}` | `components/ide/ChatPanel.cl.jac` | rows > 0 after users rate |
| `environment` super-property (prod/dev/preview/local) | `utils/analytics.cl.jac` | events carry `environment` |

---

## B. Config / ops (no code)

1. **[CONFIG] `POSTHOG_PROJECT_TOKEN` on the prod pod secret** — **highest value-per-effort.** Without it, the already-emitted `ai_generation_metered` no-ops → **no cost data at all**. Unlocks: cost/request, cost/user, cost/model, margin cost-side, per-request model.
2. **[CONFIG] Materialize `$host` in PostHog** (Data management → property) — `$host` is a JSON prop, so every env-filtered query does a full scan (some time out today). Materializing makes the prod filter fast. Needed before the real dashboard queries at any cadence.

---

## C. New instrumentation to add — ranked by value ÷ effort

### 1. ~~Fix `auth_provider` + capture acquisition channel~~  ·  ✅ RESOLVED (verified — mostly NOT a code task)
**Auth method:** solved by the SSO signup fix (PR #607) — `auth_signup_succeeded {method}` now carries password/google/github reliably (server-side). Dashboard should read the EVENT's `method`, not the unreliable `auth_provider` person prop. (Prototype updated.)
**Acquisition channel:** **verified — PostHog already auto-captures `$initial_referring_domain`** (shows `$direct` etc.); no instrumentation needed. `$initial_utm_source` is empty only because **marketing links don't carry `utm_*` params** — a marketing/ops task (add UTM to campaign links), NOT code. PostHog captures them automatically when present.
**Net:** nothing to build. Use `auth_signup_succeeded.method` (auth split) + `$initial_referring_domain` (channel) in the real dashboard.

### 2. ~~`ai_response_rated` down-vote → `ai_issue_reported {category, message_id}`~~  ·  ✅ DONE (PR #607)
Down-vote in `ChatPanel.cl.jac` now opens a category picker (inaccurate / incomplete / too slow / irrelevant / unsafe / repeated) → `ai_issue_reported`. Unlocks issue-category + hallucination tiles (AI Quality). Pending prod deploy for data.

### 3. ~~`generation_kept`~~  ·  ✅ DONE (PR #607, option A)
`generation_kept {message_id, project_id}` fires in `useChatMode.sendMessage` when the user sends a follow-up while a completed assistant turn is the latest state (built forward, not reverted). Client-side by design: the signal + identity live there; the backend persist/revert path is data-loss-fragile. Replaces the weak revert-rate proxy on AI Quality / Dev Impact. Pending prod deploy for data.

### 4. ~~Clean preview outcome event~~  ·  ✅ NOT NEEDED (verified — audit overstated it)
Re-verified the code: each preview start fires `preview_start_requested` once, then `preview_ready` OR `preview_start_failed` once — `preview_ready` is **guarded by `previewReadyFiredRef`** (reset per start, `useIDE.cl.jac:1455`), so it does NOT fire from multiple paths. `ready ÷ requested` is therefore a **real per-start success rate**, not a muddy ratio. Only real caveats: warm/pre-prepared previews (`was_prepared`) succeed instantly and inflate it, and small-N noise. No new event needed; the tooltips were corrected to stop overstating "rough proxy".

### 5. ~~`project_abandoned` (sweep)~~  ·  ✅ DONE differently — query-based, no sweep (PR #607)
Verified the core events did NOT carry `project_id` (only `ide_opened` did), which is why abandonment looked un-inferable. Instead of a fragile all-users periodic sweep + cross-root traversal, **added `project_id` to `ai_message_sent` / `ai_message_completed` / `preview_start_requested`**. Abandonment is now a **query**: per `project_id`, take the last event → if silent N days, bucket by the last event type (= last stage). Also unlocks per-project analysis broadly (iterations-per-project, per-project funnel). Follow-up (optional): add `project_id` to the remaining preview/deploy events for finer stage granularity.

### 6. `tokens_in / tokens_out` on `ai_generation_metered`  ·  effort **S**  ·  *low priority*
Cost ($) is already captured; tokens are computed then discarded. Only worth it for context-window / caching-efficiency analysis. Defer unless asked.

---

## D. Real-app dashboard requirements (not events — build into the metric layer)

These are the prototype's shortcuts that the real Jac app must NOT inherit:

1. **Prod/environment filter in every query.** The metric-registry backend must inject `environment = 'prod'` (or the `$host` allowlist for pre-super-property history) into **every** HogQL string + native-query `properties`. One project ingests all envs — unfiltered = ~80% dev/CI noise.
2. **Real date-range + compare, not hardcoded windows.** Metrics take a `date_range` param; the UI has a working range control + honest "compare to previous." No more per-tile hardcoded 30d/90d/180d with a decorative label.
3. **Honest definitions baked in:** "active" = did a core action (not any event); reach vs users kept distinct; small-N tiles flagged; every tile carries its window.
4. **Segment filters** (plan, provider) once `plan`/`auth_provider` are reliable.

---

## E. Reality checks to keep (from the audit — don't re-assume)
- **No guest access** — everyone signs up; "guest*" in code = the logged-out landing page. `is_guest` in PostHog is historical/removed; don't filter on it.
- **Single-user product** — no team/org entity. Any "team" tile is per-user or per-project.
- **JacCoder is one agent** — no discrete features / task types / per-request language (Jac-only). Task category is a client heuristic (`_taskCategory`), not model-native.
- **Several low-usage features are tier-gated** (Free: 0 deploys, no folder-upload/community) — low numbers ≠ low interest.
- **Tier `$` prices live in Stripe**, not code; `TIER_LIMITS` has spend caps + project/deploy limits only.
- **jac-scale infra metrics exist** (`get_pod_resource_metrics`, `get_prometheus_series` in `deploy_manager.jac`) — repoint at `jac-builder` namespace for real System Health infra.
