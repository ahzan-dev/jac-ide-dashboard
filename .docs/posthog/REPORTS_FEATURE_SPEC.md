# Reports Feature Spec — "Report Studio"
### From one-off Claude sessions to a first-class platform capability

**Origin.** On 2026-07-27 the hackathon report (window 2026-07-26 17:00 → 07-27 00:30 UTC) was produced
*outside* the platform: Claude ran ~15 hand-written HogQL queries against PostHog, joined them in Python,
and wrote Markdown + CSVs into `reports/`. The dashboard — whose entire purpose is answering these
questions — could not do it. The near-miss of "publish it as a Claude artifact" exposed the real gap:
**the platform can answer questions but cannot produce, snapshot, or share a document.**

This spec closes that gap. Design rule throughout: **reuse what exists** (registry, Pin recipes,
`metrics_batch` concurrency, `_prep_query_sql` guardrails, byLLM planner, DynamicTile) — a report is a
composition of primitives we already have, plus three genuinely new capabilities: **snapshots, narrative
synthesis, and share links**.

---

## 1 · Gap analysis — what the hackathon exercise needed vs what the platform has

| Capability the report needed | Platform today | Gap |
|---|---|---|
| Sub-day time window (17:00→00:30) | `date_from`/`date_to` are **dates**; `{bkt}` floor is `toDate` | **G1** — datetime windows + hour/30-min buckets |
| Per-user / per-project rollup tables (user × 25 counters, identity → email) | Registry shapes: scalar/series/rows/funnel/retention — nothing entity-centric | **G2** — cohort/entity drill-down shape |
| Cross-query joins + Python aggregation (user×model cost matrix) | Each metric = 1–2 queries; no post-join step | **G3** — composite metrics |
| A *document*: ordered sections, tables, findings, caveats, methodology | Pages are fixed tile grids; Ask answers one tile at a time | **G4** — the Report object |
| Frozen numbers (a submission must not drift) | Pins/views re-run **live**; Redis cache is a perf detail, not a snapshot | **G5** — snapshots |
| AI narrative ("five findings that matter") | `ai_insights` writes 3–4 sentences per page — close, but not sectioned or query-grounded | **G6** — synthesis pass |
| Hand the result to a non-admin (judge, exec, teammate) | Single admin login; every data endpoint `def:priv`; no public routes | **G7** — share links + viewer role |
| Export (Markdown/CSV/PDF) | Nothing | **G8** — export |
| "During the hackathon" as a first-class time reference | Nothing; Ask planner only knows relative words | **G9** — named windows |

**Strengths to build on (do NOT rebuild):** verified registry with env-filter injection everywhere ·
`metrics_batch` asyncio fan-out (solves jac-serve serialization) · Pin/SavedView per-user graph
persistence + `run_pinned` recipe re-execution · Ask planner (`ai_build` → QueryPlan) with SQL
guardrails · DynamicTile chart-string rendering · honest-labeling culture · data dictionary grounding.

---

## 2 · Product concept

**Reports** = a new nav page + server module. A report is an ordered list of **sections**; each section
is one of:

- **`tile`** — a recipe identical to a Pin (`{kind: registry|sql, key?, sql?, chart, title}`) — rendered
  by the existing `DynamicTile`.
- **`table`** — a rows-shaped recipe rendered full-width (entity drill-downs live here).
- **`text`** — Markdown prose (human- or AI-written; findings, caveats, methodology).
- **`header`** — section break.

A report has a **window** (`from_dt`/`to_dt`, minute precision — G1), an **env**, and a **mode**:

- **Live** — sections re-run on open (like Pins). For recurring ops reports.
- **Snapshot** — results frozen at build time into the report node (G5). For submissions, retros,
  audits. A live report can be "frozen" into a snapshot copy at any time.

Three ways to create one:

1. **From a template** — parameterized section lists we ship: `event-report` (the hackathon report,
   generalized: signups → funnel → cost by model/user/project → BYOK → deploys → GitHub → upgrades →
   issues → timeline), `weekly-review`, `launch-retro`, `incident-review`. Pick template + window → built.
2. **From an Ask thread** — "Compile into report" button on the Ask page: the thread's answered tiles
   become sections, then the synthesis pass writes the prose (G6). This is the killer flow: the
   *investigation you already did* becomes the document.
3. **From scratch / pins** — "Add to report" next to 📌 on any tile; text sections edited inline.

---

## 3 · Data model (graph, per-user, mirrors `Pin`/`SavedView`)

```jac
node Report {
    has title: str;
    has from_dt: str;            # ISO datetime, minute precision
    has to_dt: str;
    has env: str = "prod";
    has mode: str = "snapshot";  # snapshot | live
    has sections: list = [];     # [{type, title, recipe?, md?, order}]
    has snapshot: dict = {};     # section_id -> frozen result payload (mode=snapshot)
    has built_at: str = "";
    has share_token: str = "";   # "" = private; else public read token (G7)
    has share_masked: bool = True;  # mask emails on the public view
    has created: str = "";
}
```

Hangs off the owner's `root` like `Pin`. Snapshot payloads are the already-shaped tile results
(same JSON `metrics_batch` returns) — cap each at ~200KB, total ~2MB; store row-level bulk (per-turn
CSV equivalents) only up to a `LIMIT 500` per table section.

---

## 4 · Server API (`metrics_sv.jac` or a new `reports_sv.jac`)

| Endpoint | Auth | Does |
|---|---|---|
| `report_create(title, from_dt, to_dt, env, template)` | priv | Instantiate template sections (or empty) |
| `report_build(rid, refresh)` | priv | Run every recipe **concurrently** (reuse the `metrics_batch` asyncio.gather pattern), store snapshot, return results |
| `report_generate(rid)` | priv | G6: byLLM synthesis — summary + per-section findings + caveats → `text` sections (see §7) |
| `report_from_thread(tid, title)` | priv | Ask-thread tiles → sections |
| `report_list / report_get / report_update / report_delete` | priv | CRUD (positional args, like `thread_*`) |
| `report_share(rid, masked)` / `report_unshare(rid)` | priv | Mint/revoke `share_token` (`secrets.token_urlsafe(24)`) |
| `report_public(token)` | **pub** | Serve the **frozen snapshot only** — see §8 security invariants |
| `report_export(rid, fmt)` | priv | `md` (assembled Markdown) · `csv` (zip of table sections). PDF = client print CSS, not server |
| `window_list / window_add / window_remove` | priv | G9: named windows (`{name, from_dt, to_dt}`) — the date picker gains a "Named window…" option and the Ask/report planners resolve "during <name>" |

### Registry upgrades that fall out of this (G1–G3)

- **G1 datetime windows**: `metric`/`metrics_batch`/`run_pinned` accept full ISO datetimes in
  `date_from`/`date_to` (backward compatible — bare dates still work). `{bkt}` adaptive scale extends
  down: `toStartOfInterval(timestamp, INTERVAL 30 MINUTE)` ≤ 2 days · `toStartOfHour` ≤ 7 days · then
  the existing day/week/month ladder. **Every** query keeps the explicit `>= a AND < b` form (BETWEEN
  gotcha stands).
- **G2 entity shape**: new registry kind `"cohort"` — a rows query keyed by an entity
  (`distinct_id`/`project_id`) with an identity-resolution pass (`person.properties.email` fallback
  chain → the `who()` logic from the hackathon script, server-side). Ships with:
  `user_rollup` (the 25-counter per-user table), `project_cost_rollup`, `user_model_cost_matrix`.
- **G3 composite kind**: `"composite"` metrics declare `parts: [keys]` + a named Python `combine`
  fn — runs parts concurrently, merges (e.g. matrix = per-turn rows pivoted by model). Registry-first
  discipline holds: the hackathon's ad-hoc queries get **promoted into the registry** as
  `signups_detail`, `cost_per_turn`, `upgrades_detail`, `deploy_outcomes`, `issue_log`, `byok_split` —
  next event needs zero hand-written SQL.

---

## 5 · Client (`components/pages/ReportsPage.cl.jac` + `ReportView.cl.jac`)

- **Reports** nav entry (below My Dashboard). List = jac-shadcn Table (title, window, mode,
  shared-badge, built_at) + "New report" dialog (template Select · title Input · two
  `Input type="datetime-local"` — native, since Popover/Calendar freeze).
- **ReportView** = the document: sticky header (title, window chip, env chip, mode badge,
  Rebuild / Generate insights / Share / Export buttons) then sections in order — `DynamicTile` for
  tiles, `TableTile` full-width for tables, rendered Markdown for text (reuse the Ask page's md
  renderer). Edit mode: reorder / delete / add-text on each section.
- **Share dialog**: toggle → shows `https://<host>/report/<token>` + "mask emails" switch + revoke.
- **Public route** `/report/<token>`: renders outside the auth `Gate` (read-only, no sidebar, no
  pickers — a document, with a small "Generated by JacHammer Analytics" footer). Print CSS = the PDF
  export (G8).
- Ask page: **"Compile into report"** button per thread; every tile gets "Add to report ▸" next to 📌.

---

## 6 · Why not just keep using Claude/artifacts (honest answer)

Claude sessions stay the right tool for **novel, one-off investigations** — schema spelunking, weird
joins, hypothesis-hopping. The platform should own what recurs: the *second* hackathon report should be
one click, grounded in verified registry SQL, snapshot-frozen, shareable under our domain, with zero
context re-explaining. Artifact publishing was a workaround for G7 specifically; once share links exist
the workaround is unnecessary — and the data never leaves our infrastructure, which matters because
reports contain **participant emails** (PII we should not push to third-party hosting by default).

---

## 7 · AI synthesis pass (G6 — productizing what Claude did)

`report_generate(rid)`:
1. Gather the built section results (snapshot payloads) → compact context (same shaping `ai_insights`
   does per page, but across all sections, capped ~6k tokens — scalars, top-5 rows per table, deltas).
2. byLLM call (model `INSIGHT_LLM`, default `claude-haiku-4-5`; the temperature gotcha stands) with a
   `sem`-documented output object: `{summary: str, findings: list[str], caveats: list[str]}` —
   findings must reference concrete numbers present in the context (prompt rule), caveats must include
   the standing honesty notes (env filter, person-props-are-current, blank-model spend if present).
3. Insert as `text` sections: "Executive summary" (top), "Findings", "Caveats & method" (bottom).
   Regeneration replaces only AI-authored sections (flag `ai: true`), never human text.
4. Degrades honestly with no key (button disabled + note), like InsightsBox.

Planner grounding: `_SCHEMA_DOC` + the template section list; the concept-gap honesty rule from the
Ask planner applies (never fabricate a section the events can't support).

---

## 8 · Security invariants (non-negotiable)

1. `report_public` serves **stored snapshot JSON only** — it never executes SQL, never touches the
   registry, never accepts query params beyond the token. A leaked token exposes one frozen document,
   not a query surface.
2. Tokens: `secrets.token_urlsafe(24)`, revocable, single-report scope. No enumeration (constant-time
   lookup by walking the owner graph is fine at our scale; add a token→jid index node if slow).
3. `share_masked` default **true**: emails render as `j***@berkeley.edu` on the public view; the owner
   sees full emails when logged in.
4. Recipe SQL inside reports goes through the same `_prep_query_sql` pipeline as `ai_build`
   (env-filter injection, SELECT/WITH-only, single statement, LIMIT cap). `run_adhoc` stays out of
   reports (paste results in as a snapshot table instead).
5. Export endpoints are `def:priv`; the public route offers print-to-PDF only.

---

## 9 · Phases

**R1 — Foundation (registry + document, no AI, no sharing)**
Datetime windows (G1) · promote hackathon queries to registry (G2 cohort kind + the 6 promoted
metrics) · `Report` node + CRUD + `report_build` snapshotting · ReportsPage + ReportView (template:
`event-report`) · named windows (G9).
*Accept:* rebuild the 2026-07-26 hackathon report entirely in-app from the template in <1 min; numbers
match `reports/hackathon-2026-07-26/` (this becomes the regression fixture).

**R2 — AI (synthesis + thread compilation)**
`report_generate` (G6) · "Compile into report" from Ask threads · "Add to report" on tiles ·
composite kind (G3, user×model matrix).
*Accept:* generated summary/findings/caveats read correct against the fixture; human text survives
regeneration.

**R3 — Sharing & export (G7, G8)**
Share tokens + masked public route outside Gate · Markdown/CSV export · print CSS.
*Accept:* incognito browser renders the shared report read-only; revoke 404s it; masked emails verified.

**R4 — Ops (recurring value)**
Scheduled live reports (weekly-review template, cron walker) · optional viewer-role accounts
(jac-scale roles / `ReadPerm` — replaces token links where real logins are wanted) · Slack/email
delivery of the summary.

**Effort feel:** R1 is the big one (registry surgery + two pages) — roughly a Phase-2-sized effort.
R2 and R3 are each small (the byLLM and Pin/Gate patterns already exist to copy). R4 is optional polish.

---

## 10 · Non-goals

- No WYSIWYG layout editor — sections are a vertical list, period.
- No public *live* reports — public = snapshot, always (invariant §8.1).
- No in-report ad-hoc SQL editing — authoring happens via Ask/registry; reports compose, they don't query.
- Not a replacement for exploratory Claude sessions (§6) — it's the landing strip for what they find.
