# Dashboard Redesign Plan — organized, drillable, filter-first

**Why:** the app grew feature-by-feature (11 pages → Ask → Reports) without a unifying structure.
Everything works, but it reads as a pile of tiles, identity shows "anon:" for users who have display
names, nothing is clickable, and the two filters that define every number (env + date range) don't
feel authoritative. This plan reorganizes around researched dashboard-design principles.

**Principles adopted** (from UXPin / DataCamp / Yellowfin / Pencil&Paper dashboard-design guides):
1. **Three layers**: Summary (KPIs, 5-second readability) → Diagnostic (breakdowns, comparisons) →
   Detail (row-level tables, drill-downs). Never mix layers on one screen.
2. **5-second rule**: each page's headline insight lives top-left; ≤ 8 visuals per page.
3. **Progressive disclosure**: summaries first, detail on demand — drill-down, not dump.
4. **Stable interaction grammar**: one way to filter (global env + range, sticky), one way to drill
   (click an entity → its 360 panel), one way to go deeper (page-level "Explore" links).
5. **Consistency**: every number's tile carries definition/window/caveat (already our honesty rule).

---

## P1 — SHIPPED with this commit (drill-down + identity)

- **Identity rule (product-wide):** user cells resolve `email → display_name → name → anon:<id8>`.
  Applied to every registry metric (user_rollup, signups_detail, cost_per_turn, project_cost_rollup,
  upgrades_detail, issue_log). "anon:" now means *genuinely never identified*, not "no email".
- **Clickable entities:** any `user`/`owner`/`email` cell in ANY table (reports, feature tables, Ask
  results) is a link → opens the **User 360 panel** inline: profile + plan, 30-day counters, cost by
  model, projects by spend, recent-activity timeline. Server: `user_360(user, env)` (PostHog-only
  Phase 1 of USER_360_BUILD_SPEC; 5 concurrent queries).

## P2 — Information architecture (next)

Reorganize the sidebar from 11 flat pages into the three layers:

```
OVERVIEW        (Summary layer — the 5-second page: 4 KPIs + 2 trends + alerts)
EXPLORE         (Diagnostic layer)
  ├ Users        (adoption, retention, lifecycle  → every user clickable)
  ├ AI Engine    (requests, quality, latency, failures)
  ├ Money        (cost, upgrades, MRR, margin — merge Cost + Impact)
  └ Reliability  (previews, deploys, errors — merge Health + Feedback)
DETAIL          (Detail layer)
  ├ Users list   (sortable by last-active → User 360 full page, not just panel)
  ├ Reports      (snapshot documents)
  └ Ask          (build any cut)
SETTINGS
```
Rules: merge the 4 weakest pages into Explore groups; a page = one question; KPI rows on top-left,
tables at the bottom; every entity cell clickable (users now; projects next).

## P3 — Filters as first-class (env + range)

- Sticky filter bar (env + range + named windows) pinned on scroll, visually prominent, with an
  explicit "N events in scope" live count so the user always knows what slice they're seeing.
- Named windows selectable from the top bar everywhere (not just report creation).
- Range presets: Today · 7d · 30d · 90d · custom · named windows.
- Every tile keeps its per-tile window label (honesty), but page headers state the active scope once.

## P4 — More elements & drill-downs  *(status 2026-07-28: Project 360, minute-precision picker, cost histogram, top-cost-movers, and named-window chart annotations SHIPPED — annotation bands render on refresh/filter changes; first-paint rendering is a known jac2js limitation (memoized components + non-reactive globs; localStorage seeding defeated by glob-init/join miscompiles). Remaining: User-360 full page (needs jac-ide read API).)*

- **Project 360**: clickable `project_id` cells → project panel (owner, runs, cost, models, deploy
  history). Same pattern as User 360.
- **New visual elements**: comparison bars (this window vs previous), annotated event markers on
  trend charts (deploys, hackathons via NamedWindow), distribution histograms (cost per turn),
  top-N movers ("who changed most vs previous window").
- **User 360 full page** (Detail layer): the panel graduates to a routed page with session-replay
  deep-links + satisfaction agent (Phase 2 of USER_360_BUILD_SPEC — needs jac-ide read API).

## Non-goals / guardrails

- No raw `<div>` chart-junk: every new element stays jac-shadcn + the dataviz palette.
- The registry stays the single source of SQL; drill-downs are parameterized server functions,
  never client-composed SQL.
- Honesty labels are non-negotiable on every new element.
