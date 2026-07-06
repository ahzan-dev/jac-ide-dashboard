# JacHammer Analytics Dashboard — Progress

_Last updated: 2026-07-03_

**Status:** feature-complete in dev (11 pages live, admin-gated). Remaining work is mostly
**ops/credentials + enhancements**, not core code. See `CLAUDE.md` for architecture & gotchas.

Runs locally: `~/.jacvenv/bin/jac start main.jac --port=8000` (see CLAUDE.md "Dev up"). Admin login: `admin` / `jachammer`.

---

## ✅ Done

### Phase 0 — Foundation
- [x] Scaffold jac-shadcn fullstack app; install full component set (54)
- [x] `metrics_sv.jac`: `run_hogql` + Redis cache (10-min TTL) + env-filter injection + date range
- [x] One real tile end-to-end (New signups) with env switcher; proved prod ≠ all

### Phase 1 — App shell + core pages
- [x] `AppShell`: 11-page `Sidebar` nav (5 groups, readiness dots), top-bar env/range/refresh, meta strip
- [x] Metric registry generalized to shapes: scalar/series/rows/funnel/native-retention
- [x] Reusable tiles (StatTile, chart tiles) + honesty layer (`?` tooltips, slope, small-N, window labels)
- [x] **Overview** + **Users & Adoption** pages fully wired
- [x] Performance: one concurrent `metrics_batch` call per page (async gather); fixed server serialization

### Phase 2 — depth pages
- [x] **AI Requests** (KPIs, requests/day + peak-hours columns, failure reasons)
- [x] **Advanced Analytics** (+ working free-form HogQL box `run_adhoc`, read-only)
- [x] **Feature Usage** (adoption bars + feature table)
- [x] **System Health** (latency/reliability/JS-errors + trends + honest infra/uptime stubs)

### Phase 3 — honesty pages
- [x] **AI Quality** (failure/revert/latency proxies + honest "Helpful rate: n/a")
- [x] **Feedback & Roadmap** (problem-area proxy + issue categories + needs-list)
- [x] **Developer Impact** (kept/code + client-computed "est. hours" + honest ROI stub)
- [x] **Cost & Usage** (cost KPIs read n/a on prod with "awaiting token" notes; proxies render)
- [x] **Settings & Data** (privacy/data/access cards + data-dictionary summary)

### Chart redesign (dataviz pass — form follows the data's job)
- [x] Area (volume trends) · Line (rate trends) · H-bars (rankings) · Columns (distributions)
- [x] Meter (single ratio) · Donut (part-to-whole) · Funnel · Retention heatmap
- [x] Validated categorical palette (`--viz-1..6` light+dark)

### Phase 4 — auth gate + Stripe hook
- [x] Data endpoints `def:priv` → 401 without token; `verify_session` for stale-token bounce
- [x] `Gate` → login-only `LoginPage` / `AppShell` (+ Log out); hardcoded admin `admin`/`jachammer`
- [x] Cost page presents full burn-§4 "cost of the bet" with honest Stripe-gated tiles + integration point

---

## ⬜ To do

### 1. Ops gates — no code, unblock real data (highest leverage)
- [ ] Add **`POSTHOG_PROJECT_TOKEN`** to the prod pod → lights up the whole Cost & Usage page
- [ ] Deploy **PR #607** to prod → AI-Quality thumbs, Feedback issues, deploy-success, `plan` tier, `tool_call_count`
- [ ] Add **`STRIPE_SECRET_KEY`** → margin / runway / CAC
- [ ] Get prod to **emit the `environment` super-property** (removes the "$host-allowlisted" fallback disclosure)

### 2. Security hardening — before any real deploy
- [ ] Set `[plugins.scale.jwt] secret` (default is jac-scale's insecure test key — tokens forgeable)
- [ ] Move admin password out of the seed into a secret; rotate `jachammer`
- [ ] (Optional) Gate to jac-scale role `admin` (provision via `/admin`) vs "any registered user"

### 3. Deployment
- [ ] jac-scale deploy to an internal URL behind auth; prod secrets + cluster Redis

### 4. Remaining code features (priority order)
- [x] Real **`billing_sv.jac`** Stripe module (active subs → MRR → margin) wired into Cost tiles
      — degrades honestly without `STRIPE_SECRET_KEY`; live-computes margin % when key + subs present
- [ ] **Infra metrics** for System Health via jac-scale Prometheus (CPU/mem/pods/uptime)
- [x] **Lifecycle tile** (native LifecycleQuery: new/returning/resurrecting/dormant) — stacked bar on Advanced
- [x] **Deploy success-rate tile** — success rate honest n/a until PR #607 + real deploy-intent hbars, on System Health
- [x] **Compare-to-previous** deltas on KPIs — each scalar runs its query over the prior equal-length
      window; StatTile + GaugeTile show "±% vs prev" colored by good/bad (falls back to weekly slope if no prev)
- [x] **Calendar date-range picker** — top-bar native date inputs (from → to, browser calendar); server takes
      explicit `date_from`/`date_to`. KPIs, hbars, funnel AND trends all follow the range now, with **adaptive
      bucketing** (daily ≤31d · weekly ≤186d · monthly beyond). Retention/lifecycle keep their own cohort windows.
- [x] **Chart polish** — fixed Y-axis label clipping (margin) and hbar label truncation (labels moved above bars).
- [x] **Full data dictionary** in Settings — searchable table of the 26 CORE events (event / category /
      properties / powers / status), `components/dash/DataDictionary.cl.jac`
- [x] **Saved views** — save/restore/remove the current {page, env, date range} to localStorage, shown as chips
      in a bar under the top bar (`components/dash/SavedViews.cl.jac`)

### 5. Known issues / tech debt
- [x] Dead-code cleanup — removed unreachable `StubPage`, `STUB_NOTES`, unused `_W10` glob (all 11 pages are real)
- [ ] Native `jac check metrics_sv.jac` intermittently flags E1032 on redis/requests (runtime fine; split/annotate)
- [ ] Runs on `~/.jacvenv` jac 0.16.7, not native (native scale-serve broken in this build) — version-drift risk
- [ ] Radial gauges replaced by linear meters (recharts 3.x radial scaling broken) — revisit if circular look wanted

### 6. Open data-definition decisions (spec §8)
- [ ] Retention definition — calendar-week vs rolling; which core action = "retained"
- [ ] Marketing UTM on campaign links (only way "acquisition channel" becomes real)
