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

## Toolchain reality (⚠ CHANGED 2026-07-10 — jaclang shipped a big breaking release)
**RUN with the native dev `jac`** (`~/.local/bin/jac` → `~/Documents/jaseci/jaseci/jac/zig-out/bin/jac`,
"dev mode", jaclang 0.31, py3.14). The old pip `~/.jacvenv` is gone. Per
docs.jaseci.org/community/breaking-changes: the **pluggy plugin/hook system was removed** (`hookimpl` gone) and
**byllm + jac-scale are folded into jaclang core** — no back-compat shims. Consequences that WILL bite:
- **byLLM import is `import from jaclang.byllm.lib { Model }`** (was `byllm.lib`). **Do NOT `jac install byllm`** —
  it pulls the standalone pip `byllm 0.6.19`, which still does `import ... hookimpl` → `cannot import name 'hookimpl'`
  crash at serve/build. Use the built-in (`jaclang.byllm`).
- **jac.toml config flattened** (`[plugins.<name>]` → `[<name>]`): `[scale.microservices] enabled = false`
  (was `[plugins.scale.microservices]`) and `[client.vite]` (was `[plugins.client.vite]`). Microservices MUST
  stay `false` or `jac start` auto-spawns `metrics_sv` + `billing_sv` as subprocesses; with it false, everything
  runs in one in-process gateway.
- **Type-check + serve with the SAME native `jac`** now (byllm is built in, so `jac check` / `jac test` resolve
  it). `jac check` on 0.31 is stricter — a couple pre-existing `E1053` `len(<any>)` warnings on `metrics_sv.jac`
  are runtime-harmless and don't block `jac start`.
- **Auth changed**: tokens are now ~221 chars and the OLD `.jac/data` admin hash fails login (401 "Invalid
  credentials") under new jaclang — re-seed a fresh user (`/user/register`) if login 401s.
- **Redis**: use `dash-redis` (`docker run -d --name dash-redis -p 6379:6379 redis:7-alpine`),
  `REDIS_URL=redis://localhost:6379`. Cache degrades to a no-op if Redis is unreachable (app still works uncached).
- **byLLM gotcha still live**: byLLM/litellm inject a default `temperature`, which Opus 4.7+/Sonnet 5 reject.
  `INSIGHT_LLM` defaults to **`claude-haiku-4-5`** (accepts it; override via `INSIGHTS_MODEL`). The old
  pydantic / `rm -rf .jac` gotcha is now moot (byllm is core, not a stale project venv).
- Jac syntax: docstrings BEFORE the def; no `pass` (use `return;`); `json.loads(...) as dict`;
  `requests.post(data=json.dumps(payload))` + explicit `Content-Type` header (`json=` trips the JsonType checker).
- **`$host` reality (reconciled — the two old claims below contradicted each other):** the byLLM eval found
  host-filtered `prod` time-queries (`toDate(timestamp)=today()` + the `$host` allowlist) **full-scan and hit the
  20s `run_hogql` timeout**. Treat `$host` as effectively NOT materialized for AI-builder-generated queries. Real
  fix: **emit `environment='prod'` from prod** so the `$host` allowlist fallback (and the full scan) disappears —
  see `.docs/posthog/TRACKING_GAPS.md` §D-14.

## Dev up (local)
```bash
docker start dash-redis 2>/dev/null || docker run -d --name dash-redis -p 6379:6379 redis:7-alpine
set -a; source .env; set +a
export JAC_BUN="$HOME/.bun/bin/bun"
jac start main.jac --port=8010     # native dev jac. :8000 is often the jac-ide app — use a free port.
# login 401? re-seed a fresh admin:
# curl -X POST :8010/user/register -H 'Content-Type: application/json' \
#   -d '{"identities":[{"type":"username","value":"admin"},{"type":"email","value":"admin@jaseci.org"}],"credential":{"type":"password","password":"jachammer"}}'
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
- `$host`: was believed materialized (`events.mat_$host`, ~1.4s), BUT the 2026-07 byLLM eval saw host-filtered
  time-queries full-scan to the 20s timeout — treat it as effectively NOT materialized for ad-hoc/AI-builder
  queries (see Toolchain reality `$host` note + `TRACKING_GAPS.md` §D-14). Registry batch queries are still fast.
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
  - **Stripe join**: (⚠️ STALE as of the decision-review batch below — `STRIPE_SECRET_KEY` **is now set** in
    `.env`, along with `VITE_PUBLIC_POSTHOG_PROJECT_TOKEN` + `POSTHOG_PROJECT_ID`; the margin/cost tiles may now
    compute real numbers — verify.) Historically: no `STRIPE_SECRET_KEY` in `.env`, so margin/runway/CAC on the
    Cost page were honest "—" tiles (burn spec §4 "cost of the bet"). Integration point: add `STRIPE_SECRET_KEY`, a `billing_sv.jac`
    with a `def:priv billing_summary()` that lists active Stripe subscriptions → MRR, and compute
    margin = (MRR − metered_spend) ÷ MRR; wire it into the Cost tiles (mirrors the POSTHOG_PROJECT_TOKEN pattern).
  - **Production hardening TODO**: (1) set `[scale.jwt] secret` (config flattened — was `[plugins.scale.jwt]`; default is the insecure test key —
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

## Decision-review batch (honesty fixes + hardcoded-tile resolution; verified via curl + browser)
Prompted by a per-tile "does this help a decision?" review. Fixes:
- **Mislabels corrected**: Impact "Acceptance proxy trend" now fed by a new **`kept_weekly`** metric (revert-based
  acceptance), not `gen_success_weekly` (completion). `churn_risk` carries a real rolling-window label (was showing
  the date-picker range it ignores). "Registered" → "Signups (180d)" (fixed 180d window). "Cost / active user" →
  **"Cost / spender"** (`cost_per_user` SQL divides by distinct spenders, not actives).
- **Naming**: the one `funnel` metric now reads "Activation funnel" on all 3 pages it appears; Advanced
  "Failure-pattern detection" → "Top failure reasons", "Usage forecast (naive)" → "AI volume (daily)" (it's history).
- **HogQL box**: prefilled query now includes the exact prod env clause + a hint that ad-hoc SQL is NOT
  auto-env-filtered.
- **Hardcoded tiles resolved**: Impact "Est. hours saved" → an honest **range** ("N–Mh", ~1.5–3 min/file) instead of
  false-precise "Nh". **Deleted 3 permanently-blocked stubs**: Prompt clustering (Advanced), CAC by channel (Cost),
  True uptime (Health).
- **AI insights (real, via byLLM)**: new `InsightsBox.cl.jac` ("Generate insights" button) → `ai_insights(context)` in
  `metrics_sv.jac`, an **actual `by llm()`** call (`_write_insight` + `sem`, model `INSIGHT_LLM`). Summarizes the
  page's scalars/rows/series and returns a 3–4-sentence decision readout. Degrades honestly with no key. See the
  byLLM gotchas in **Toolchain reality** above (pydantic `.jac` nuke; `temperature`→haiku).
- **Dynamic data dictionary**: new `event_usage(events)` server fn scans the `METRICS` registry live; DataDictionary
  fetches it on mount (`async can with entry`) and shows a **"Metrics"** column = count of registry metrics
  referencing each event (`—` when none). Self-updating — can't silently drift from the registry.

## AI-first "Ask" builder + byLLM eval (2026-07)
- **Ask (AI builder) page** (`components/pages/AskPage.cl.jac`, nav "✨ Ask") — a conversational planner: NL
  question → `ai_build(question,env,date_from,date_to)` (def:priv) → byLLM `_plan_query` returns a `QueryPlan`
  with `mode` ∈ **metrics** (reuse verified registry keys) / **query** (write an env-injected read-only HogQL
  `SELECT`, grounded by `_SCHEMA_DOC`) / **clarify**. Renders via `components/dash/DynamicTile.cl.jac`
  (chart-string → an existing tile). **Registry-first**, raw-SQL as the escape hatch; the LLM never writes JSX.
  Time-words ("today"/"this week") route to dated queries; "X vs Y" → `chart=compare` (±% delta, `good_up`
  colors direction). **📌 Pin** → `components/pages/PinnedPage.cl.jac` ("My Dashboard") re-runs saved recipes
  LIVE via `run_pinned` (recipe, not snapshot). Every answer has a "How this was built" panel (mode/reasoning/SQL).
- **Non-negotiable**: `ai_build`'s generated SQL gets `env_filter()` auto-injected in `_prep_query_sql` (it is
  NOT the ad-hoc `run_adhoc` path) — read-only, single-statement, `LIMIT`-capped.
- **Tests** — `metrics_sv.test.jac`: 27 deterministic tests (`jac test metrics_sv.jac`) covering env injection,
  `_prep_query_sql`, `_shape_ai_tile` (stat/compare/table/series), `_pct_delta`, `_col_index`, `_tile_for`,
  `_catalog`. A `by INSIGHT_LLM` fn **cannot be MockLLM'd** (model bound at def-time) → planner quality is eval'd
  against the live endpoint, not unit-tested.
- **Planner prompt hardening** (from a 41-scenario eval): `QueryPlan` fields ordered `chart`/`good_up` BEFORE the
  verbose `sql` (truncation was silently defaulting them → comparisons rendered as plain tables); `max_tokens=1400`;
  a **concept-gap honesty rule** (don't fake untracked answers like session-length/acquisition-channel/first-try —
  `clarify` and name the gap); `re.search(r"(?i)\blimit\b")` for the LIMIT cap (a `\nLIMIT` defeated the old check).
- **Product tracking gaps** → `.docs/posthog/TRACKING_GAPS.md`: ranked new events the AI builder can't answer
  without (upgrade_checkout_succeeded, UTM/referrer, conversation_id+turn_number, `model` on ai_message_*, ship
  the built-but-unlaunched ai_response_rated/ai_issue_reported UI, ai_response_edited, ide_session_ended,
  cold_start on preview_ready).
