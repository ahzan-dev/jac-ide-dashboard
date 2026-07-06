# Project: JacHammer Analytics Dashboard

Internal, read-only analytics cockpit. Full-stack Jac app. Reads PostHog via server-side HogQL.
- Spec: `.docs/posthog/DASHBOARD_APP_BUILD_SPEC.md` · Events: `.docs/posthog/EVENT_CATALOG.md`
- Visual spec: `.docs/posthog/prototype/index.html` (11 pages, env switcher, honesty labels — match it).
- PostHog project `425465`. Secrets in `.env`: `POSTHOG_API_KEY` (phx_, READ, server-only), `REDIS_URL`,
  `POSTHOG_HOST=https://us.posthog.com`.

## Hard rules
- **`POSTHOG_API_KEY` (phx_) is a READ key and is SERVER-ONLY** — only used in `metrics_sv.jac`. Never in a
  `.cl.jac` file, client bundle, or Vite define. Client → `/function/metric` walker → PostHog. Never client → PostHog.
- **Every HogQL query injects the environment filter** (`env_filter()` in `metrics_sv.jac`, default `prod`).
  One PostHog project ingests prod+dev+preview+local; unfiltered numbers are ~80% noise.
- **`prod` is NOT identifiable by the `environment` super-property** — prod does not emit it yet (only
  local/preview/dev do). So `env_filter('prod')` matches `environment='prod'` **OR a `$host` allowlist**
  (`jachammer.ai`, `www.jachammer.ai`, `jac-builder.jaseci.org`). This is spec §3.1 rule-1 fallback and is
  load-bearing — without it prod returns 0.
- Honest tiles: each carries its exact definition, window, and small-N/proxy caveat.
- HogQL: presence = `coalesce(toString(properties.X),'') != ''`; numbers = `toFloat64OrNull(toString(...))`.

## Toolchain reality (READ THIS — it cost a session to learn)
This app does **NOT** use `jaclang.scale`. Caching is the plain `redis` Python package, not scale's tiered memory.
Therefore:
- **RUN with the pip jac `~/.jacvenv/bin/jac` (v0.16.7), NOT the native `~/.jacbin/jac`.** The native binary's
  `jac start` scale-serve path is BROKEN in this build (`No module named 'jaclang.scale.memory'` /
  `jaclang.scale.jserver.jfast_api` / `trace_ctx` — missing bundled submodules) and forces a MongoDB backend
  (pymongo not installed). `~/.jacvenv` has no scale layer, so it serves the plain fullstack app in-process.
  `~/.jacvenv` already has `requests` + `redis` installed.
- **Use the native `~/.jacbin/jac check <file>` for authoritative type-checking** (it's stricter than the venv),
  but serve with `~/.jacvenv/bin/jac`. Best of both.
- **`[plugins.scale.microservices] enabled = false` in `jac.toml` is REQUIRED.** Otherwise the scale layer
  auto-detects `metrics_sv` (sv-imported by the client) as a microservice and spawns it as a subprocess with the
  broken venv jac → crash. With it false, `metrics_sv` runs in-process (also plain-imported in `main.jac`).
- **Redis must be published on the host.** The pre-existing `jac-redis` container has NO host port map; use the
  dedicated `dash-redis` (`docker run -d --name dash-redis -p 6379:6379 redis:7-alpine`). `REDIS_URL=redis://localhost:6379`.
  The cache degrades gracefully to no-op if Redis is unreachable (so the app still works uncached).
- Docstrings go BEFORE the def, never inside a function body. Jac has no `pass` (use `return;`).
  `json.loads(...)` returns Any → cast with `as dict`. `requests.post(json=...)` trips the JsonType checker →
  use `data=json.dumps(payload)` with an explicit `Content-Type: application/json` header.
- **PostHog `$host` is NOT materialized** (only `environment` is). Host-filtered prod queries full-scan and can
  exceed a tight timeout (`run_hogql` uses 15s for now). Materializing `$host` in PostHog is the real fix
  (spec open-decision #3) — then drop the timeout back to ~8s.

## Dev up (local)
```bash
docker start dash-redis 2>/dev/null || docker run -d --name dash-redis -p 6379:6379 redis:7-alpine
set -a; source .env; set +a
export JAC_BUN="$HOME/.bun/bin/bun"          # native binary lacks bun; venv jac finds it via PATH/JAC_BUN
~/.jacvenv/bin/jac start main.jac --port=8000   # serves the app at http://localhost:8000/
```

## UI — jac-shadcn ONLY (strict)
Every surface is a jac-shadcn component (Card tiles, Tabs, Select env-switcher, Table, Badge, Tooltip, Sidebar,
Skeleton, Sonner). Never a raw `<div>`+Tailwind where a component exists. The full component set is already
installed (`jac add --shadcn`, 54 components in `components/ui/`). Charts = recharts in the jac-shadcn Chart
container; follow the `dataviz` skill. Read `jac-shadcn`/`-blocks`/`-components` before writing JSX.

## jac2js gotchas (client `.cl.jac` — learned building Phase 1)
- **Component tags MUST be Capitalized.** `def:pub app_shell()` rendered `<app_shell>` as a literal unknown
  DOM element (blank screen). Name components `AppShell`, reference `<AppShell />`. Lowercase = intrinsic tag.
- **Python format specs don't compile.** `f"{x:+.0f}"`, `f"{n:,}"`, `f"{v:.1f}"` pass through unformatted (raw
  float shown). Build strings manually: `str(int(round(x)))`, a manual thousands-grouper, etc. See
  `components/dash/util.cl.jac`.
- **Inline JSX lambda `tickFormatter` miscompiles** → axis shows `[object Object]`. Use a named `def:pub`
  function (e.g. `short_date`) and pass it by reference: `tickFormatter={short_date}`.
- **HMR is unreliable for entry (`main.jac`) + cross-module changes.** After editing, force a clean rebuild:
  `rm -rf .jac/client/dist .jac/client/compiled` then restart. (Component-only edits usually HMR fine.)
- Charts: recharts inside the jac-shadcn `ChartContainer` (`config={{ "y": {label,color} }}`, child = an
  AreaChart/LineChart/BarChart with `data`). Sparkline = `AreaChart` in an `h-12 aspect-auto` ChartContainer.
- **jac-shadcn `Popover` and `Calendar` freeze the renderer** in this build (open → infinite render, CDP
  screenshots time out). The date-range picker uses plain `Input type="date"` inline instead — native browser
  calendar, robust, and `e.target.value` is already a `YYYY-MM-DD` string (no Date interop). Avoid Popover/Calendar.
- **Date range is `date_from`/`date_to` (ISO strings), not `range_days`.** `metric`/`metrics_batch` take explicit
  dates; the server derives range length → previous-window (for deltas) and an **adaptive time bucket** via
  `{bkt}` in the SQL (`toDate` ≤31d · `toStartOfWeek` ≤186d · `toStartOfMonth` beyond). Trend metrics use
  `{bkt}(timestamp)` + `_RANGE` so they follow the picker; retention/lifecycle keep their own cohort windows.
- **Cross-indexing an outer-scope list with an inner loop var INSIDE a JSX slot freezes the renderer**
  (infinite loop, no error). `{for r in rows { {for (ci,cell) in enumerate(r) { {cols[ci]} }} }}` hangs;
  `str(cell)` alone is fine. Fix: precompute the formatted rows in the component BODY (plain Jac) and keep
  JSX slots trivial (`{for cc in fr["cells"] { <TableCell>{cc["v"]}</TableCell> }}`). See `TableTile`.
- **HogQL env-filter injection + `BETWEEN`**: `timestamp BETWEEN a AND b {env_filter}` becomes
  `BETWEEN a AND b AND (...)` → ClickHouse mis-binds the `AND` → http 400. Use explicit `timestamp >= a AND
  timestamp < b {env_filter}` in any query the env filter is appended to.

## Performance (why the batch endpoint exists)
- **jac-serve (0.16.7) serializes concurrent requests** — 6 parallel `/function/metric` calls took ~6× a
  single call. A per-tile fetch model → a full page serializes ~15 queries → very slow.
- Fix: **`metrics_batch(keys, env, range_days, refresh)`** runs all of a page's queries **concurrently in ONE
  request** via `async def:pub` + `asyncio.gather(*[asyncio.to_thread(run_hogql, …)])`. 12 metrics (~18 HogQL
  calls) return in ~5s cold, instant when Redis-cached. **Each page makes ONE batch call**; tiles are
  presentational (receive their result object as a `data` prop — no per-tile `sv import`/fetch).
- `$host` **is already materialized** in PostHog (`events.mat_$host`) — a prod query is ~1.4s. PostHog is NOT
  the bottleneck; server serialization was. So materialization is done; don't re-flag it.
- Range semantics: KPIs + hbars + funnel use the selected `{from}/{to}`; **weekly trends (10wk) and retention
  (6 cohort-weeks) keep their own multi-period windows** (a slope needs multiple periods) — labeled honestly.

## Chart design system (dataviz pass — form follows the data's job)
Tiles in `components/dash/ChartTiles.cl.jac` (+ `StatTile`). Pick by job, NOT by habit:
- **Volume/count trend over time** → `AreaTile` (filled area, single series): active_weekly, returning_weekly,
  files_changed_weekly, ai_requests_weekly, exception_weekly, daily_ai.
- **Rate/% or latency trend** → `LineTile` (line, no fill): gen_success_weekly, preview_reliability_weekly,
  revert_weekly, latency_weekly.
- **Ranking across nominal categories** → `BarsTile` (horizontal bars): top_features, problem_areas,
  ai_fail_reasons, model_mix, issue_categories.
- **Distribution over ordinal buckets** (day, hour) → `VBarTile` (columns): requests_daily, peak_hours.
- **Single ratio vs a limit** → `GaugeTile` = a **linear meter track** (big % + filled track). NOT a radial:
  recharts 3.x `PolarAngleAxis` radial-gauge scaling is unreliable (renders a fixed tiny arc regardless of
  value); the dataviz-canonical form for a single ratio is a same-ramp meter anyway.
- **Part-to-whole, ≤6 slices** → `DonutTile` (Pie + legend + direct labels): signup_method.
- **Funnel** → `FunnelTile`; **cohort grid** → `RetentionTile` heatmap; **table** → `TableTile`; KPI numbers →
  `StatTile` (area sparkline + slope). Static/blocked → `StaticStat`; honesty note → `Banner`.
- **Categorical palette** = dataviz validated set in `global.css` (`--viz-1..6`, light+dark), fixed order,
  never cycled; single-series charts use `var(--chart-1)` (blue). Validated with the dataviz script
  (light worst-adjacent ΔE 24.2; dark 10.3 floor → donut carries a legend/direct labels as the relief).
  Status colors (`--success`/`--destructive`) reserved for slope badges only.

## Status
- **Phase 0 DONE**: metric layer + one live tile end-to-end. Proven prod≠all; cache hit verified.
- **Phase 1 DONE** (verify in browser): full app shell — `components/AppShell.cl.jac` (11-page `Sidebar` nav in
  5 groups w/ readiness dots, top-bar env/range/refresh `Select`s, meta strip). Metric registry
  (`metrics_sv.jac`) now ~20 metrics across shapes scalar/series/rows/funnel/native-retention, generic
  shaping + env filter on all. Reusable tiles in `components/dash/` (StatTile w/ sparkline+slope, LineTile,
  BarsTile, FunnelTile, RetentionTile heatmap) + `util.cl.jac` (fmt/slope/short_date). Pages:
  **Overview** + **Users & Adoption** fully wired; the other 9 render honest `StubPage` "planned" cards.
  Verified live in browser: KPIs+sparklines+rounded slopes, line charts w/ date axes, hbars, funnel,
  retention heatmap (W4 col red, small-N ⚠), env filter prod≠all.
- **Phase 2 DONE** (verified in browser): **AI Requests** (KPIs, requests/day + peak-hours vertical bars,
  failure reasons), **Advanced Analytics** (churn-risk, baseline, failure-pattern, journey funnel, forecast,
  + a working **free-form HogQL box** — `run_adhoc`, SELECT/WITH-only, server-side), **Feature Usage**
  (adoption hbars + feature table), **System Health** (latency/reliability/JS-errors + trend lines +
  honest infra/uptime stubs). New registry metrics: latency_weekly, exception_weekly/total, requests_daily,
  peak_hours, daily_ai, requests_per_active, prompt_len, ai_baseline, ai_fail_reasons, feature_table. New
  tiles: VBarTile, TableTile, StaticStat, Banner. AppShell routes all 6 real pages; feedback/quality/impact/
  cost/settings still honest stubs.
- Perf model still holds: each page = ONE `metrics_batch` call (concurrent server-side). All queries curl-
  verified; env filter prod≠all everywhere.
- Nav note: in CDP automation the first sidebar click sometimes only focuses (2nd click navigates) — appears
  to be a click-precision artifact, not reproduced as a logic bug; worth a real-mouse check.
- **Phase 3 DONE** (verified in browser): all 11 pages now real. **AI Quality** (failure/revert/latency proxies
  + honest "Helpful rate: n/a" until ai_response_rated), **Feedback** (problem-area proxy + issue categories +
  needs-list), **Developer Impact** (kept/code + client-computed "est. hours" + honest ROI stub), **Cost & Usage**
  (cost KPIs read n/a on prod with "Awaiting POSTHOG_PROJECT_TOKEN" notes; model-mix proxy + volume + tier
  limits; auto-fills when token ships), **Settings** (static privacy/data/access InfoCards + data dictionary).
  New metrics: failure_rate, revert_rate/revert_weekly, rating_ratio, metered_rows, total_spend,
  cost_per_request, cost_per_user, files_changed_weekly, ai_requests_weekly, model_mix, issue_categories.
- Sidebar nav in CDP: click by element **ref** (ref_1=Overview … ref_6=AI Quality, ref_9=Cost, ref_11=Settings),
  NOT pixel coords — coords are unreliable, refs navigate on a single click.
- Native `jac check metrics_sv.jac` intermittently shows E1032 on redis/requests attrs (checker loses the
  imported module types on the big file); the `.jacvenv` build+runtime is fine (all metrics curl-verified).
- **Phase 4 DONE** (verified in browser): **admin auth gate** + Stripe integration point.
  - Data endpoints (`metric`, `metrics_batch`, `run_adhoc`) are **`def:priv`** → 401 `Unauthorized` without a
    token (verified). `verify_session` (def:priv) lets the client validate a stored token on load.
  - Client flow: `main.jac` → `components/Gate.cl.jac` (auth boundary) → `LoginPage` (login-only, no signup)
    or `AppShell` (with a Log out button in the sidebar footer). Gate re-checks a present token via
    `verify_session` on mount and bounces stale/invalid tokens to login (present ≠ valid).
  - **Hardcoded admin: username `admin` / password `jachammer`** — seeded once via `/user/register` (persists
    in the user DB across restarts; JWT is stateless so tokens survive restarts too). Re-seed if the DB is wiped:
    `curl -X POST :8000/user/register -d '{"identities":[{"type":"username","value":"admin"},{"type":"email","value":"admin@jaseci.org"}],"credential":{"type":"password","password":"jachammer"}}'`.
  - **Stripe join**: no `STRIPE_SECRET_KEY` in `.env`, so margin/runway/CAC on the Cost page are honest "—"
    tiles (burn spec §4 "cost of the bet"). Integration point: add `STRIPE_SECRET_KEY`, a `billing_sv.jac`
    with a `def:priv billing_summary()` that lists active Stripe subscriptions → MRR, and compute
    margin = (MRR − metered_spend) ÷ MRR; wire it into the Cost tiles (mirrors the POSTHOG_PROJECT_TOKEN pattern).
  - **Production hardening TODO**: (1) set `[plugins.scale.jwt] secret` (default is the insecure test key —
    anyone can forge tokens); (2) move the admin password out of the seed command into a secret / rotate it;
    (3) optionally gate to jac-scale role `admin` (provision via `/admin`) instead of "any registered user".
  - User DB persists in `.jac/data/` (SQLite: `main.db`); the admin survives normal restarts. If it's wiped
    (e.g. `jac clean`/`.jac` reset), re-seed with the `/user/register` one-liner above.

## Post-Phase-4 additions (all verified in browser; see PROGRESS.md)
- **Compare-to-previous**: each scalar also queries the prior equal-length window → `prev`/`delta`; StatTile +
  GaugeTile show "±% vs prev" (falls back to weekly slope when the prev window has no data).
- **Calendar date range**: top-bar native `<input type=date>` × 2 (Popover/Calendar freeze — avoid them).
  Server takes `date_from`/`date_to`; derives previous-window + an **adaptive `{bkt}`** (`toDate` ≤31d ·
  `toStartOfWeek` ≤186d · `toStartOfMonth` beyond). Trends follow the range; retention/lifecycle keep cohort windows.
- **Lifecycle** tile (native LifecycleQuery, stacked bar) on Advanced; **deploy** intent + honest success-rate
  on System Health; real **`billing_sv.jac`** Stripe MRR→margin on Cost (honest "—" without a key).
- **Data dictionary** (searchable 26-event table) + **saved views** (localStorage chips) on Settings/top bar.
- **Chart polish**: Y-axis no longer clipped (margin), hbar labels moved above bars (no truncation).
- **Cleanup**: removed dead `StubPage`, `STUB_NOTES`, `_W10`; all 11 pages route to real components (Settings is
  the routing fallback).
