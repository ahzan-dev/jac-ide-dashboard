# Burn Dashboard — Build Plan

The proper plan for the standalone internal metrics dashboard, before we commit code to the
Jac app. Companion to `BURN_DASHBOARD_BUILD_SPEC.md` (tiles + verified queries) and
`EVENT_CATALOG.md` (the event contract).

## Decisions locked
- **Separate internal app** (own repo/URL), **Option B** = custom branded UI. Not a PostHog
  shared link; not a chatbot (deferred).
- **Data source:** PostHog **HogQL Query API** (`POST /api/projects/425465/query/`) + native
  Retention/Lifecycle/Funnel query kinds.
- **Target stack:** small **Jac fullstack app** (reuses jac-shadcn + team muscle memory).

## Current blocker → why the HTML prototype exists
`jac start` has a core issue the team is actively fixing, so we can't build/run the Jac app
right now. Rather than stall, we built a **framework-free HTML/CSS/JS prototype**
(`prototype/`) rendered from a **real PostHog snapshot**. It validates the entire design and
data shape *today*. When `jac start` is healthy, the prototype is the spec we port from —
nothing about the design is left to re-decide.

## Architecture (3 layers — the key never reaches the browser)
```
Dashboard UI  ──"metric name + range"──▶  Backend (metric registry + cache)  ──HogQL + phx_──▶  PostHog
   (charts)   ◀──── clean {series} ─────        (holds the phx_ key)          ◀── columns/results
```
- **Frontend** asks for a **metric name** (`north_star`, `activation_rate`, …), never SQL.
- **Backend** owns the SQL in a registry, holds the `phx_` key in env, zips
  `columns`+`results` → clean series, caches ~60s (stacks on PostHog's own cache).

## The metric registry (backend)
One entry per tile — a direct lift of the verified queries in the build spec:
```
_METRICS = {
  "north_star":      {kind:"hogql",     unit:"builders", query:"SELECT toStartOfWeek(...) ..."},
  "activation_rate": {kind:"hogql",     unit:"%",        query:"..."},
  "retention":       {kind:"retention", body:{...}},          # native RetentionQuery
  "lifecycle":       {kind:"lifecycle", body:{...}},          # new/returning/resurrecting
  ...
}
```
Walker `metric_ops(metric, range_days)` → validate name → cache check → POST to PostHog →
return `{success, unit, series, cached_at}`.

## Build phases
- **Phase 0 — prototype (DONE):** `prototype/index.html` + `gen_data.py`, real data, validated
  in-browser. This is the sign-off artifact.
- **Phase A — prove the pipe** (once `jac start` works): scaffold Jac app + `metric_ops` walker
  + one real tile end-to-end (`north_star`).
- **Phase B — the ✅ tiles:** port the ~9 powerable tiles from the prototype (North Star,
  retention, activation rate + funnel, TTFV, gen-success, preview reliability, revert,
  new-vs-returning, signups/projects). Queries already verified.
- **Phase C — layout + gate:** 4-section layout, slope chrome, scariest-number box, admin
  email allowlist, deploy to internal URL.
- **Phase D — blocked tiles:** the ledger + Stripe join for margin/burn/CAC/power-user cost.

## Prototype → Jac app mapping (what ports to what)
| Prototype piece | Jac app equivalent |
|---|---|
| `gen_data.py` queries | `_METRICS` registry entries in the `metric_ops` walker |
| `data.js` snapshot | live `metric_ops` responses (+ 60s cache) |
| `lineChart`/`barChart`/`retentionTable` JS | `.cl.jac` chart components (Recharts or ported SVG) |
| slope / partial-week logic | same logic in a `useMetric` hook / component |
| dark palette CSS vars | jac-shadcn semantic tokens |

## Open decisions (parked — from the earlier questions)
- **Auth gating:** email allowlist (recommended) vs single shared login vs later.
- **Hosting:** which internal URL / whether it rides the same K8s deploy path.

## Honest gaps to keep labeling
- Retention needs runway (cohorts still maturing).
- No `$` in PostHog — Section 4 is ledger + Stripe, shown as 🔒 until that join exists.
- Deploy-success + tier(`plan`) are fixed in code but need prod deploy to populate.
