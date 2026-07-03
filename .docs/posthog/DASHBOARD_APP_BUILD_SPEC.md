# JacHammer Analytics Dashboard — Build Spec

**Status:** ready to build · **Owner:** analytics · **Last updated:** 2026-07-02
**Audience:** whoever builds this (human or AI page-builder) + Linjia/leadership as the end users.

This is the definitive spec for the **real** dashboard app that replaces the throwaway
prototype in `.docs/posthog/prototype/`. It is grounded in the instrumentation we shipped
and **verified firing live** (PR #607) this session. Read it top-to-bottom before writing code.

Companion docs (read these too):
- `EVENT_CATALOG.md` — every event + its properties (the data contract).
- `INSTRUMENTATION_BACKLOG.md` — what's instrumented, §D "real-app requirements", §E "reality checks".
- `DASHBOARD_FEASIBILITY.md` — the data-access options that were evaluated.
- `verify_deploy.py` — run it to confirm which events are flowing before trusting a tile.
- `prototype/` — the 11-page visual reference (structure to reuse; NOT the data layer).

---

## 1. What this is and why

**The problem:** leadership needs to make decisions (are people signing up? coming back? what's
it costing? is the AI any good?) but the answers live in raw PostHog, which is not a decision surface.

**The app:** a small, branded, **internal** analytics dashboard — a curated set of pages, each tile
backed by a **server-side HogQL query** against PostHog, with honest definitions and an environment
filter baked in. Not a PostHog embed; a purpose-built read-only cockpit.

**Non-goals:** it does not write events, does not replace PostHog for ad-hoc exploration, is not
customer-facing, and is not a general BI tool. Keep it small and opinionated.

---

## 2. Architecture

**Standalone Jac fullstack app, own repo, own deployment** (decision "Option B"). The whole company
stack is Jac; `jac start` works locally now, so build it the same way as jac-ide but far simpler.

```
Browser (internal users, admin-gated)
   │  jac-client sv-import → walker spawn
   ▼
Gateway (jac start main.jac --scale)
   │
   ├── metrics_sv.jac      walkers that run HogQL against PostHog, cache, env-filter
   └── main.jac (client)   .cl.jac pages, jac-shadcn + recharts charts
                              │
                              ▼
                       PostHog HogQL Query API
                       POST https://us.posthog.com/api/projects/425465/query/
                       Authorization: Bearer <POSTHOG_API_KEY>   (phx_… personal key, SERVER-ONLY)
```

**Critical secret hygiene** (this is the #1 way to get it wrong):
- `POSTHOG_API_KEY` (`phx_…`) is a **read** personal key. It is **SERVER-ONLY** — it lives in the
  pod env, is used only inside `metrics_sv.jac` walkers, and is **NEVER** shipped to the client or
  put in a `.cl.jac` file / Vite `define`. The browser never sees it.
- The client calls **walkers**, which call PostHog. The client never calls PostHog directly.
- Project id is `425465`. Host `https://us.posthog.com` for the Query API (note: capture uses
  `https://us.i.posthog.com`, the Query API uses `us.posthog.com` — different subdomain).

**Deployment:** jac-scale to an internal URL (e.g. `metrics.jaseci.internal` or a private route),
behind auth. Do not expose publicly — it shows revenue/cost.

---

## 3. The metric layer (the heart of the app)

Every tile is a **metric**: a named query + a transform + a definition + a window. Define them in a
registry so pages are declarative and the four non-negotiable rules below are enforced in ONE place.

### 3.1 Non-negotiable rules (enforced in the metric layer, not per-tile)

1. **Environment filter in EVERY query.** One PostHog project ingests prod + dev + preview + local
   (we measured `local=112, preview=73, (unset)=226` in a single day). Unfiltered numbers are
   ~80% noise. Inject into every query:
   - Preferred: `AND properties.environment = {env}` (the super-property we added; values
     `prod|dev|preview|local`).
   - Fallback for **historical** rows predating the super-property (they're `(unset)`): a host
     allowlist `AND properties.$host IN ('jachammer.ai','www.jachammer.ai','jac-builder.jaseci.org')`.
   - The env is a **top-bar switcher** (Production default; Dev; All). Default = `prod`.
2. **Real date range + compare.** Metrics take a `date_range` param (`from`/`to`) and an optional
   compare-to-previous. The UI has a working range control. NO hardcoded `INTERVAL 30 DAY` with a
   decorative label — the prototype did that and it's a lie.
3. **Honest definitions baked in.** Every tile carries: its exact definition, its window, and a
   small-N warning when the denominator is tiny. "Active" = did a *core action*, not any event.
   Keep "reach" (any event, incl. bounces) and "builders" (logged-in, did something) separate.
4. **Materialize `$host` in PostHog** (Data management → property) before shipping — `$host` is a
   JSON prop, so host-filtered queries full-scan and can time out. One-time ops task.

### 3.2 Metric definition shape (Jac)

```jac
# metrics_sv.jac — one entry per tile-backing metric
obj Metric {
    has key: str;
    has title: str;
    has definition: str;      # the honest one-liner shown in the tile tooltip
    has sql: str;             # HogQL with {env_filter}, {from}, {to} placeholders
    has kind: str = "scalar"; # scalar | series | breakdown | table
    has caveat: str = "";     # small-N / proxy warnings
}
```

The walker fills placeholders (`{env_filter}` from the switcher, `{from}`/`{to}` from the range),
runs the query, caches the result (see 3.3), and returns `{value, series, meta:{definition,window,caveat,n}}`.

### 3.3 Querying + caching

- One helper: `run_hogql(sql: str) -> dict` — `requests.post` to the Query API with the Bearer key,
  4–8s timeout, returns `results` or an error dict. All errors swallowed into a tile-level "n/a".
- **Cache** results in Redis keyed by `(metric_key, env, from, to)` with a TTL of **5–15 min**.
  Leadership doesn't need second-fresh data, and PostHog rate-limits + charges for query volume.
  A manual "refresh" button busts the cache for that tile.
- **Never** run an unbounded `SELECT *` wrapper — always project explicit columns and time-bound
  heavy joins (we hit ClickHouse 500/504s doing otherwise). Prefer materialized props over JSON props.

### 3.4 HogQL gotchas we already hit (bake these in)

- `properties.X != ''` is a **false positive** for absent props (`null != ''` → true in HogQL). To
  test presence use `coalesce(toString(properties.X),'') != ''`. (Cost us real debugging.)
- `UNION ALL` ordering is nondeterministic — use a single-row multi-column `SELECT` for KPI rows.
- Numeric props are strings — cast with `toFloat64OrNull(toString(properties.X))`.
- Auth-method split: read `auth_signup_succeeded.method` (the EVENT prop, reliable), **not** the
  `auth_provider` person prop (mostly unset).

---

## 4. Tech stack

- **Backend:** `metrics_sv.jac` walkers (JWT/admin-gated). `requests` for the Query API. Redis for cache.
- **Frontend:** `.cl.jac` pages, **jac-shadcn** components + **recharts** for charts (both already
  proven in jac-ide). `cn()` for classNames, semantic color tokens only.
- **jac-shadcn ONLY, strictly** — every surface is a semantic component (Card tiles, Tabs, Select
  env-switcher, Table, Badge, Tooltip, Sidebar, Skeleton, Sonner); never a raw `<div>`+Tailwind where
  a component exists. **Install the full jac-shadcn set up front** (`jac add --shadcn` for every
  component) right after scaffold, before building. Follow the `jac-shadcn`/`-blocks`/`-components` skills.
- **Charts — follow the dataviz rules** (these are non-negotiable and catch the most common mistakes):
  - **One y-axis ever.** Two measures of different scale → two charts or index to a common base.
    Never a dual-axis chart.
  - **Categorical colors in a fixed order, never cycled.** A 9th series folds into "Other".
  - **Color follows the entity, not its rank** — a filter that changes series count must not repaint survivors.
  - Sequential = one hue light→dark; diverging = two hues + neutral gray midpoint; status colors
    (good/warn/serious/critical) are reserved and ship with an icon+label, never color alone.
  - Legend always present for ≥2 series; ≤4 series also direct-labeled. Text uses ink tokens, not series color.
  - Every chart is interactive (crosshair+tooltip on line/area, per-mark tooltip on bar/dot). A table
    view exists for accessibility. Validate any categorical palette (colorblind-safe) — don't eyeball it.
- **Auth:** internal only. Reuse jac-scale identity; gate the whole app behind admin login. No guest.

---

## 5. Pages & tiles

Keep the prototype's 11-page structure (it's a good IA) but **every tile must map to a real metric
with a real query** — no filler. Below: each page, its tiles, the backing event(s), and the honest
definition. Mark each tile's data-source event so you know if it's live (see `verify_deploy.py`).

Legend: 🟢 = event verified firing · 🟡 = fires but needs more traffic/materialize · 🔴 = not yet built/instrumented.

### 5.1 Overview (the one screen leadership opens)
- **New signups** 🟢 — `count() auth_signup_succeeded` in range, split by `method` (password/google/github).
- **Active builders** 🟢 — distinct `person_id` who did a *core action* (`ai_message_sent` OR
  `project_created` OR `preview_start_requested` OR a git/deploy walker). NOT "any event".
- **Reach (context only)** 🟢 — distinct `person_id` with any event. Show *next to* builders, labeled
  "includes logged-out landing visitors + bounces" — never conflate with users.
- **Returning users** 🟡 — signed-up users with ≥1 core action on a later day than signup.
- **AI turns + cost** 🟢 — `ai_message_sent` count · `ai_generation_metered` `sum(cost_usd)`.
- **Preview reliability** 🟢 — `preview_ready ÷ preview_start_requested` (a real per-start success
  rate; caveat: warm/`was_prepared` previews inflate it).

### 5.2 Users & Adoption
- **Signups over time** 🟢, stacked by `method`.
- **Acquisition channel** 🟡 — `$initial_referring_domain` (PostHog auto-captures; mostly `$direct`
  today). UTM only populates if marketing links carry `utm_*` (ops task, not code).
- **Activation funnel** 🟢/🟡 — signup → project_created → first `ai_message_sent` → `preview_ready`
  → `deploy_*_succeeded`. Use `project_id` on events for per-project fidelity.
- **Retention curve** 🟡 — weekly cohorts W0–W4 (the burn spec flagged a real W4 0–3% cliff — this
  tile is the headline; get it right). PostHog retention via HogQL or the retention query kind.
- **DAU / WAU / MAU** 🟢 — distinct core-action users per window.

### 5.3 Feature Usage
- **Feature adoption** 🟢 — event volume + distinct users per surface (`ide_opened`, command palette,
  git ops, folder upload, community, deploy). Note: several are **tier-gated** (Free = 0 deploys,
  no folder-upload/community) — low numbers ≠ low interest. Annotate gated features.
- **Per-project activity** 🟡 — group by `project_id` (now on `ai_message_sent`/`_completed`/
  `preview_start_requested`); iterations per project, project funnel.

### 5.4 AI Requests
- **Volume + task mix** 🟢 — `ai_message_sent` by `task_category` (client heuristic — label it as
  such; it's not model-native and JacCoder is a single agent, not multiple features).
- **Latency** 🟢 — `ai_message_completed.duration_ms` distribution (p50/p90; use `median`, not `p50`).
- **Tool usage** 🟢 — `ai_message_completed.tool_call_count` (verified avg≈26, max 78).
- **Completion vs failure** 🟢 — completed ÷ (completed + failed/aborted).

### 5.5 AI Quality
- **Rating ratio** 🟢 — `ai_response_rated` up ÷ (up+down).
- **Issue categories** 🟢 — `ai_issue_reported` by `category` (inaccurate/incomplete/too slow/…).
- **Acceptance (kept)** 🟡 — `generation_kept` ÷ completed turns. The real "kept the output" signal;
  replaces the weak revert-rate proxy. (Def: user sent a follow-up without reverting the prior turn.)

### 5.6 Developer Impact
- **Projects created / deployed** 🟢/🟡.
- **Output kept + files changed** 🟡 — `generation_kept` · `ai_message_completed.files_changed`.
- **Time-to-first-preview / -deploy** 🟡 — from signup timestamp to first `preview_ready`/deploy.

### 5.7 Cost & Usage (revenue-sensitive — internal only)
- **Total spend + trend** 🟢 — `ai_generation_metered.sum(cost_usd)`.
- **Cost per request / per user / per model** 🟢 — group by `model`, by `person_id`.
- **Margin (cost side)** 🟡 — cost vs tier price. **Tier `$` prices live in Stripe, not code** —
  pull them from Stripe (or hardcode with a dated note + link); `TIER_LIMITS` only has spend caps
  ($1.33/$4/$10) + project/deploy limits. Do the math honestly.
- **Budget/quota usage** 🟡 — per-user spend vs their tier cap.
- ⚠️ **Gate:** `ai_generation_metered` needs `POSTHOG_PROJECT_TOKEN` on **each** pod. Confirmed on
  preview; **confirm on prod** or the prod cost tiles are empty.

### 5.8 System Health
- **Preview reliability** 🟢 (see Overview).
- **Deploy success rate** 🟡 — `deploy_*_succeeded ÷ (succeeded+failed)`, split sandbox vs production.
- **Infra** 🔴 — jac-scale already exposes `get_pod_resource_metrics` / `get_prometheus_series`
  (`deploy_manager.jac`); repoint at the `jac-builder` namespace for CPU/mem/pods. Not a PostHog metric.

### 5.9 Feedback & Roadmap
- **Issue → roadmap signal** 🟢 — `ai_issue_reported` categories ranked; trend over time.
- **Rating trend** 🟢.

### 5.10 Advanced Analytics
- Free-form HogQL box (server-side, admin-only, read-only), saved cohorts/funnels. Power-user escape hatch.

### 5.11 Settings & Data Controls
- **Environment switcher** (prod/dev/preview/all) — drives §3.1 rule 1 across every tile.
- **Date range + compare.**
- **Cache refresh** (per-tile + global).
- Data dictionary (render `EVENT_CATALOG.md`).

---

## 6. Reality checks (do NOT re-introduce these wrong assumptions)

From the assumption audit — each of these was a mistake caught in review:
- **No guest access.** Everyone signs up; "guest*" in code = the logged-out landing page. `is_guest`
  in PostHog is historical/removed — do not filter on it.
- **Single-user product.** No team/org entity. Any "team" tile is per-user or per-project.
- **JacCoder is one agent.** No discrete features / per-request language (Jac only). `task_category`
  is a client heuristic — present it as such.
- **Several low-usage features are tier-gated.** Low numbers ≠ low interest; annotate the paywall.
- **Prices live in Stripe**, not code.
- **`ready ÷ requested` is a real success rate** (the ready event is guarded once-per-start) — earlier
  audit overstated it as muddy; only `was_prepared` inflation + small-N are real caveats.

---

## 7. Build plan (phased — ship the spine first)

**Phase 0 — skeleton (1 sitting):** new Jac repo, `jac start` locally, admin auth, one page (Overview),
the metric layer with `run_hogql` + Redis cache + env-filter injection + date-range param, and the
top-bar env/range controls. Prove ONE real tile (New signups) end-to-end with the prod filter.

**Phase 1 — core pages:** Overview, Users & Adoption, Cost & Usage, AI Quality. These answer the
actual leadership questions (growth, retention, cost, quality). Wire the verified-🟢 metrics first.

**Phase 2 — depth:** Feature Usage, AI Requests, Developer Impact, System Health, Feedback.

**Phase 3 — polish:** Advanced Analytics box, infra metrics (Prometheus), compare-to-previous,
saved views, palette validation pass.

At each phase, run `verify_deploy.py` and only surface a tile whose event is 🟢/🟡 with data —
never a tile that renders zeros as if they were real.

---

## 8. Open decisions (need a human call before/while building)

1. **Repo + hostname** for the standalone app (internal URL, auth provider).
2. **Prod `POSTHOG_PROJECT_TOKEN`** — confirm it's on the prod pod (gates all cost tiles).
3. **Materialize `$host`** in PostHog (ops) — do this early; queries are slow without it.
4. **Marketing UTM** on campaign links — the only way acquisition channel becomes real.
5. **Retention definition** — calendar-week vs rolling; which "core action" counts as retained.
6. **Tier prices** — pull from Stripe live, or hardcode-with-date? (affects margin tile).

---

*This spec is buildable as-is. The instrumentation is live and verified (PR #607). The prototype
shows the look; this doc is the contract. Build the metric layer once, correctly, and the pages
become declarative.*
