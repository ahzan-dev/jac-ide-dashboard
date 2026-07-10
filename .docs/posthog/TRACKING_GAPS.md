# PostHog Tracking Gaps — Engineering Hand-off

> **Source:** a byLLM-planner eval of the dashboard's "Ask (AI Builder)" (41 real-LLM scenarios + gap
> analysis against `EVENT_CATALOG.md`), 2026-07. These are the questions the AI builder — and any
> analyst — **cannot answer honestly today because the event/property does not exist**, not because of a
> prompt. Fire locations are from `EVENT_CATALOG.md`; confirm against current code before implementing.
>
> **Governance reminder (from `EVENT_CATALOG.md`):** don't add an event without a tile that consumes it;
> don't change a CORE event's name/contract without updating that file too.

**Priority order (do these first):**
1. Emit `environment='prod'` from prod (§D-13) — unblocks query timeouts.
2. Ship the two already-built UIs (§C-11, §C-12) — zero tracking work.
3. Add `model` + `conversation_id`/`turn_number` to AI events (§B-6, §B-7).
4. Close the money loop: `upgrade_checkout_succeeded` + UTM capture (§A-1, §A-3).

---

## A. New events to add

### A-1 · `upgrade_checkout_succeeded` — **HIGH**
- **Fires:** server-side, Stripe webhook (`checkout.session.completed` / `invoice.paid`). Mirror the
  `ai_generation_metered` server-capture pattern (POST to `/capture/` with the `phc_` project token;
  `distinct_id = display_name` so it lands on the right person).
- **Props:** `plan` (builder/pro), `amount_usd`, `interval` (month/year), `is_first_upgrade` (bool), `stripe_customer_id`
- **Unlocks:** click→paid **conversion rate**, MRR-from-events, the upgrade funnel.
- **Why:** today only `upgrade_checkout_clicked` (intent) and `upgrade_checkout_failed` exist — **there is no
  completion event at all**, so paid conversion is uncomputable.

### A-2 · `ai_response_edited` — **HIGH**
- **Fires:** client, when a user manually edits code the AI generated (diff against the AI's last output for that file).
- **Props:** `message_id` (→ links to `ai_message_completed`, see B-8), `edit_distance` (chars changed),
  `lines_changed`, `time_to_edit_ms`, `files_changed`
- **Unlocks:** the **real acceptance signal** — how much of what the AI wrote actually survived.
- **Why:** replaces `kept_rate` / `revert_rate`, which the codebase itself flags as weak proxies
  ("not undoing a change ≠ approving it").

### A-3 · UTM / referrer capture — **HIGH**
- **Fires:** client, on first landing (before auth); persist to the person and/or attach to `auth_signup_succeeded`.
  (Either a `landing_page_viewed` event or first-touch person properties registered via `identify`.)
- **Props:** `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `referrer`, `initial_referring_domain`, `landing_path`
- **Unlocks:** **acquisition-channel attribution** — which channel/campaign brings retained & paying users.
- **Why:** **zero UTM/referrer capture exists anywhere today.** Login provider (Google/GitHub/password) is *not*
  a marketing channel — the planner currently substitutes it and mislabels the answer.

### A-4 · `ide_session_ended` — **MED**
- **Fires:** client, on IDE close / idle timeout / navigation-away (debounced).
- **Props:** `duration_active_ms` (focused time, not wall-clock), `ai_requests_in_session`, `files_touched`,
  `previews_run`, `ended_reason` (close/idle/nav)
- **Unlocks:** session depth / time-on-task.
- **Why:** today only `$pageview` / `$pageleave` counts exist — no real session duration.
  **Cheap first step:** expose PostHog's auto `$session_id` to the analytics/query layer.

### A-5 · `subscription_canceled` / `subscription_downgraded` — **MED**
- **Fires:** server-side, Stripe webhook (`customer.subscription.deleted` / `.updated`).
- **Props:** `plan_from`, `plan_to`, `reason` (if collected), `days_active`, `mrr_delta`
- **Unlocks:** revenue churn & downgrade drivers (mirror of A-1 — churn is invisible today; only upgrade *intent* is tracked).

---

## B. Property additions to existing events

### B-6 · `model` on `ai_message_sent` + `ai_message_completed` — **HIGH**
- **Change:** add `model` (the model that actually ran) in `useChatMode.cl.jac`.
- **Why:** `model` currently lives **only** on `ai_generation_metered` (the cost event, gated on
  `POSTHOG_PROJECT_TOKEN`). Adding it to the timing events unlocks **per-model latency / success rate**
  immediately, without waiting on the cost pipeline. Today `model_mix` only counts *manual model switches*,
  not the model that ran each request.

### B-7 · `conversation_id` + `turn_number` on the AI event group — **HIGH**
- **Change:** add a stable `conversation_id` (per chat thread) + `turn_number` (1, 2, 3…) to
  `ai_message_sent` / `ai_message_completed` / `ai_message_failed` / `ai_message_reverted`.
- **Unlocks:** **first-try success** (turn 1 completed, no follow-up) and **retry-loop detection** — the
  strongest AI-quality signal available.
- **Why:** the AI events aren't linked into a thread today, so "does the AI get it right on the first try"
  is unanswerable (the planner falls back to completion rate and mislabels it).

### B-8 · stable `message_id` on `ai_message_completed` — **HIGH (enabler)**
- **Change:** ensure a stable per-generation id, so edits (A-2), ratings (C-11), and reverts can reference the
  exact generation. Prerequisite for A-2 and quality-by-message analysis.

### B-9 · `cold_start: bool` on `preview_ready` — **MED**
- **Change:** on the existing event (`useIDE.cl.jac`), flag pre-warmed vs cold-started.
- **Unlocks:** de-inflates preview reliability.
- **Why:** the `preview_reliability` metric caveat already admits warmed-up previews load instantly and flatter the number.

### B-10 · `signup_trigger` on `auth_signup_succeeded` — **MED**
- **Props:** `guest_locked_feature` / `free_signup_bonus` / `dashboard_prompt` / `direct`
- **Unlocks:** which gates/CTAs actually convert.
- **Why:** `guest_locked_feature_clicked` / `signup_gate_opened` exist but aren't linked to the resulting signup.

### B-11 · `files_count` / `project_type` on `project_created` — **LOW-MED**
- **Change:** add project complexity/depth props (today only `source`).
- **Unlocks:** feature-depth / project-complexity analysis (are people building real apps or toys?).

---

## C. Already built — just launch the UI (zero tracking work)

### C-12 · `ai_response_rated` (thumbs up/down) — **HIGH · ship**
- Event + code exist (`ChatPanel.cl.jac`); the UI is **not launched**. The `rating_ratio` metric reads empty
  **by design** until it ships. Unlocks helpful-rate, avg rating, quality-by-model.

### C-13 · `ai_issue_reported` — **HIGH · ship**
- Event exists; UI **not launched**. The `issue_categories` metric reads empty until it ships. Unlocks the
  issue-category breakdown tile.

---

## D. Infra / non-event (reliability & correctness)

### D-14 · Emit `environment='prod'` from production — **HIGH (infra)**
- Prod isn't tagged by the `environment` super-property, so every prod query falls back to a `$host`
  allowlist. `$host` is **unmaterialized**, so host-filtered time queries **full-scan → 20s query timeouts** —
  this breaks the AI builder under load and slows every tile.
- **Real fix:** emit `environment='prod'` from production (then the allowlist fallback *and* the full scan
  disappear). **Stopgap:** materialize `$host` in PostHog.

### D-15 · Verify pending-deploy events fire in prod — **MED**
- Confirm each is >0 in prod after deploy: `tool_call_count` (was always 0, code-fixed), the deploy outcome
  events (`deploy_*_succeeded` / `deploy_*_failed`), and the `plan` person-property.

### D-16 · Grounding fixes (not new tracking) — **MED**
- Expose to the Ask planner's schema doc: **Stripe MRR** (already in `billing_sv.jac`, so "revenue" stops
  mapping to cost) and PostHog **`$session_id`** (a rough session-length proxy until A-4 ships).

---

*Generated from the AI-builder planner eval. See the eval report artifact for the full scorecard and the
bugs fixed on the dashboard side. Cross-reference: `EVENT_CATALOG.md` (event contracts),
`POSTHOG_INTEGRATION_AUDIT.md` (known reliability issues).*
