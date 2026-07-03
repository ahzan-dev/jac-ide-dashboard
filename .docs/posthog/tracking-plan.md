# Tracking Plan — AI App Builder

The instrumentation contract. Fire these events from the builder and every tile on the Bet Monitor becomes computable. Nothing here is optional padding — each event maps to a dashboard number. If an event isn't tied to a decision, it's not in this plan.

**Principle:** instrument the *lifecycle of a project*, not page views. The whole product is "idea → working app → shipped, again." Track that arc and the funnel, retention, and margin all fall out.

---

## 1. The 11 core events

Fire these and you can build 100% of the dashboard. Resist adding more until these are clean.

| # | Event | Fire when | Why it exists (tile it feeds) |
|---|-------|-----------|-------------------------------|
| 1 | `signup` | Account created (first time only) | Funnel top, cohort stamp, activation denominator |
| 2 | `project_created` | User starts a new app/project | Funnel step 2, "where projects die" denominator |
| 3 | `generation_requested` | User submits a prompt to generate/edit | Iterations-per-project, engine volume |
| 4 | `generation_succeeded` | Build pipeline returns runnable output | Cost & margin (carries tokens), funnel step 3 |
| 5 | `generation_failed` | Build pipeline errors out | Mid-generation death, error diagnostics |
| 6 | `app_previewed` | User sees the rendered/running app | Funnel step 4 — the critical "they saw it" moment |
| 7 | `generation_kept` | User accepts/keeps the output (doesn't discard or immediately re-prompt to undo) | **"Actually worked" rate** — the truth metric |
| 8 | `app_deployed` | App is deployed/exported/published | North Star, activation success, funnel bottom |
| 9 | `project_abandoned` | Project goes inactive (see derivation below) | "Where projects die", the leak |
| 10 | `subscription_started` | Paid plan begins | Revenue, margin, conversion |
| 11 | `subscription_canceled` | Paid plan ends | Churn |

### Why `generation_kept` is non-negotiable
`generation_succeeded` means *the code compiled*. `generation_kept` means *the user actually wanted it*. The gap between these two is where the business bleeds and where a naive "success rate" lies to you. The dashboard's "actually worked" tile is `generation_kept / generation_succeeded`. Without event 7 you are blind to the single most important quality signal in an AI builder.

Capture "kept" pragmatically — fire it when the user does any of: clicks deploy, edits the generated code by hand, moves to a next prompt that builds *on* the result (not "no, redo"), or explicitly thumbs-up. Discard / "regenerate from scratch" / immediate undo = **not** kept.

---

## 2. Event properties

Properties are where the leverage is. The events tell you *what happened*; properties let you slice *why* and *what it cost*.

```jsonc
// signup
{
  "acquisition_channel": "organic | paid_search | referral | direct",
  "referrer_user_id": "usr_… | null",
  "signup_source": "landing | template_gallery | shared_app"
}

// project_created
{ "project_id": "prj_abc123", "template_used": "blank | crud | dashboard | …" }

// generation_requested
{
  "project_id": "prj_abc123",
  "prompt_chars": 184,
  "intent": "create | edit | fix | style",      // first generation vs iteration
  "iteration_index": 0                            // 0 = first gen of this project
}

// generation_succeeded   ← carries the cost of the bet
{
  "project_id": "prj_abc123",
  "model": "claude-sonnet-4-6",
  "tokens_in": 4210,
  "tokens_out": 9830,
  "cost_usd": 0.214,            // PRECOMPUTE THIS (see §4) — don't make queries do pricing math
  "latency_ms": 7400,
  "iteration_index": 0
}

// generation_failed
{
  "project_id": "prj_abc123",
  "error_type": "timeout | model_error | invalid_output | build_error | rate_limit",
  "model": "claude-sonnet-4-6",
  "iteration_index": 2
}

// app_previewed
{ "project_id": "prj_abc123", "load_ok": true }

// generation_kept
{ "project_id": "prj_abc123", "kept_via": "deploy | hand_edit | next_prompt | thumbs_up", "iteration_index": 1 }

// app_deployed
{ "project_id": "prj_abc123", "deploy_target": "hosted | export_zip | github", "total_iterations": 3 }

// project_abandoned        ← the leak signal
{
  "project_id": "prj_abc123",
  "last_stage": "at_prompt | mid_generation | after_preview | after_deploy",  // drives "where projects die"
  "total_iterations": 6,
  "minutes_active": 12
}

// subscription_started
{ "plan": "pro | team", "mrr": 29, "billing": "monthly | annual" }

// subscription_canceled
{ "plan": "pro", "mrr_lost": 29, "reason": "too_expensive | quality | left_for_competitor | … | null" }
```

**The two properties that matter most:** `cost_usd` on `generation_succeeded` (every margin/burn tile) and `last_stage` on `project_abandoned` (the entire "where do we lose people" diagnosis). Get those two right before anything else.

---

## 3. Person & group identity (PostHog)

Cohort slopes and per-user economics need stable identity. Set person properties on `identify`, and **stamp the signup cohort once** — never overwrite it.

```js
// On signup — set the cohort stamp ONCE (use $set_once so re-logins don't move it)
posthog.identify(userId, {
  $set_once: {
    signup_date: new Date().toISOString(),
    signup_week: isoWeek(new Date()),     // e.g. "2026-W24" → drives retention-by-cohort
    acquisition_channel: channel
  },
  $set: {
    plan: "free",                          // updated on subscribe/cancel
    is_paying: false
  }
});

// On every subsequent login / app load
posthog.identify(userId);                   // links the session to the person

// On subscribe / cancel — update the mutable props
posthog.capture('subscription_started', { plan: 'pro', mrr: 29 });
posthog.people.set({ plan: 'pro', is_paying: true });
```

If you bill per-org, also set a **group** so you can read team-level economics:

```js
posthog.group('workspace', workspaceId, { plan: 'team', seats: 8 });
```

---

## 4. Cost capture — do it at event time, not query time

The margin and burn tiles are only as good as `cost_usd`. **Compute it on the backend when the generation completes**, from the actual token counts and the model's price, and attach it to `generation_succeeded`. Don't push raw tokens and reconstruct price in HogQL — pricing changes, models get routed, and your historical numbers will rot.

```ts
// backend, on generation complete (NestJS service)
const PRICE = {                                  // USD per 1M tokens — keep in config, version it
  'claude-sonnet-4-6':   { in: 3.00,  out: 15.00 },
  'claude-haiku-4-5':    { in: 0.80,  out: 4.00  },
};
const p = PRICE[model];
const cost_usd = (tokensIn / 1e6) * p.in + (tokensOut / 1e6) * p.out;

posthog.capture({
  distinctId: userId,
  event: 'generation_succeeded',
  properties: { project_id, model, tokens_in: tokensIn, tokens_out: tokensOut,
                cost_usd: round(cost_usd, 4), latency_ms, iteration_index }
});
```

Capture cost server-side regardless — it's the source of truth, it can't be ad-blocked, and it's where you already have the token counts.

---

## 5. Where to fire each event (your stack: React + NestJS)

Split by trust. **Money and pipeline truth fire from the backend** (NestJS, via `posthog-node`) so they can't be blocked or spoofed. **Intent and UI moments fire from the frontend** (React, via `posthog-js`).

| Event | Fire from | Reason |
|-------|-----------|--------|
| `signup`, `subscription_*` | Backend | Must be trustworthy; tied to auth/billing |
| `generation_requested` | Frontend | It's the user's intent/click |
| `generation_succeeded` / `_failed` | **Backend** | Carries cost + token truth; happens in the pipeline |
| `generation_kept` | Frontend | It's a user UI action |
| `app_previewed` | Frontend | UI render moment |
| `app_deployed` | Backend | Tied to the deploy job result |
| `project_created` | Either (pick one) | Just don't double-fire |
| `project_abandoned` | **Backend job** (derived, see below) | Not a user action — it's an *absence* of action |

---

## 6. Deriving `project_abandoned` (it's not a click)

Abandonment is the absence of activity, so a user can't fire it. Run a scheduled job (e.g. nightly cron in NestJS) that finds projects with no activity for N hours (start with 48h), looks at the last meaningful event for that project, and emits `project_abandoned` with `last_stage` derived from it:

- last event was `generation_requested` with no success → `mid_generation`
- last event was `app_previewed` but no `app_deployed` → `after_preview`  ← *this is the one to watch*
- last event was `project_created` with no generation → `at_prompt`
- last event was `app_deployed` then silence → `after_deploy` (often fine — they finished)

Backfill `total_iterations` and `minutes_active` from the project's event history. This single derived event powers the "where projects die" tile that exposed the post-preview leak.

---

## 7. Build order — don't boil the ocean

Ship instrumentation in three waves. Each wave lights up part of the dashboard, so you get value before it's all done.

1. **Wave 1 — the spine (1 day):** `signup`, `project_created`, `generation_succeeded` (+`cost_usd`), `app_deployed`. → North Star, activation, basic funnel, margin all come alive.
2. **Wave 2 — the truth (2–3 days):** `generation_requested`, `generation_failed`, `app_previewed`, `generation_kept`. → "actually worked" rate, full funnel, iterations.
3. **Wave 3 — the leak + money (2–3 days):** `project_abandoned` cron, `subscription_*`, person cohort stamps. → retention slopes, churn, where-projects-die, power-user cost.

---

## 8. Naming discipline (so the data stays usable)

- `snake_case` for events and properties, **past tense** verbs (`app_deployed`, not `deploy`).
- One `project_id` format everywhere (`prj_…`). It's the join key across half the queries.
- `iteration_index` on every generation event — it's what separates "first output was great" from "took six tries."
- Never rename an event in place. If semantics change, version it (`generation_succeeded_v2`) and migrate the queries.
