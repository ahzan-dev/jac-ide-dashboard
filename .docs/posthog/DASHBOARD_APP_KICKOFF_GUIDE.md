# Dashboard App — Kickoff Guide (for a fresh session / new Jac project)

You are starting the **JacHammer Analytics Dashboard** in a **new repo and a new chat session**.
This guide is self-contained: it assumes you have none of the prior context. Read it fully, then
read `DASHBOARD_APP_BUILD_SPEC.md` (the *what*); this doc is the *how to start*.

> Paste this whole file (plus `DASHBOARD_APP_BUILD_SPEC.md` and `EVENT_CATALOG.md`) into the new
> session as the opening context. They live in the jac-ide repo at `.docs/posthog/` — copy them into
> the new repo's `.docs/` so they travel with the project.

---

## 0. TL;DR — the first five moves
1. Bootstrap a new Jac **fullstack + jac-shadcn** project (§2). Load the `jac-project-kinds` and
   `jac-scaffold` skills first — they give the exact `jac create` verb.
2. Get `jac start` running locally with the **native jac binary** (§3) — a pip `jaclang` will fail
   the moment you touch `jaclang.scale` (Redis cache / deploy).
3. Copy over the 3 context docs + the PostHog secret (§4, §5).
4. Build the **metric layer** (`metrics_sv.jac`): `run_hogql()` + Redis cache + env-filter + date-range.
   This is the spine — everything else is declarative on top.
5. Prove **one real tile** end-to-end: "New signups" with the prod env filter, on one Overview page.

Then follow the phased plan in the build spec.

---

## 1. What you're building (one paragraph)
A small, branded, **internal** analytics dashboard for JacHammer (an AI web IDE). It's a curated set
of pages; each tile is backed by a **server-side HogQL query** against PostHog, with an environment
filter and honest definitions baked in. It is NOT a PostHog embed and NOT customer-facing. The full
contract — architecture, pages, per-tile metrics, rules — is in `DASHBOARD_APP_BUILD_SPEC.md`.

### 1a. The mockup IS your visual spec — build to match it
There is a **working, framework-free prototype of all 11 pages** at `.docs/posthog/prototype/` (open
`prototype/index.html` in a browser — it runs standalone, no build). **This is the design and UX
reference to replicate**, specifically:
- the **11-page sidebar IA** and each page's tile composition,
- the **top-bar environment switcher** (Production / Dev / All) and date range,
- the **honesty layer** — every tile carries its definition, its window label, and small-N/proxy
  warnings (this is the whole point; don't drop it),
- the **strawman numbers** in `prototype/data.js` came from real HogQL (`prototype/gen_data.py`) —
  reuse those queries as your metric starting points.

**Port the structure + UX, NOT the CSS:** the prototype is hand-rolled HTML/CSS; the real app rebuilds
the same layouts with **jac-shadcn + recharts** (semantic tokens, the `dataviz` chart rules). Think of
the prototype as the wireframe-with-real-data; the app is the production build of it. Copy the whole
`prototype/` folder into the new repo so you can diff against it as you go.

---

## 2. Bootstrap the project

**Load these skills first (in the new session):** `jac-project-kinds` → `jac-scaffold` →
`jac-fullstack-patterns` → `jac-shadcn` / `jac-shadcn-components`. They are authoritative for the
current CLI; don't guess commands from memory.

The kind is a **full-stack Jac app** (`.cl.jac` client + server walkers, `main.jac` gateway),
scaffolded with the **jac-shadcn** variant (Nova style, so charts + cards look right out of the box):
```bash
# confirm the exact template name via the jac-scaffold skill; typically:
jac create <dashboard-app-name> --use jac-shadcn
cd <dashboard-app-name>
```
Then add the deps you'll need to `jac.toml` (`requests` for the Query API; `redis` for cache) — see
the `jac-config` skill for the `[dependencies]` block, and `jac-npm-packages` for `recharts`.

**Even better base:** the **`jac-starter`** repo (at `../jac-starter` relative to jac-ide) is an
AI-ready Jac fullstack starter that already ships the portable **CLAUDE.md + MCP + skills + memory
context layer** and a verified minimal demo. Cloning it gives you the whole Jac-context scaffolding
for free — strongly preferred over a bare `jac create`. Confirm it exists, then start from it.

---

## 3. Local run environment (this WILL bite you if skipped)

The company code targets the **native `jac` binary** (Zig launcher + bundled CPython, with
`jac-scale`/byLLM folded into core as `jaclang.scale`). A pip-installed `jaclang` in a venv does
**not** have `jaclang.scale` and dies with `No module named 'jaclang.scale'` the moment the server
imports it (Redis cache, deploy, microservices). So:

```bash
# 1. native binary (has jaclang.scale) — this is the toolchain the CI/deploy use
mkdir -p ~/.jacbin
curl -fsSL https://github.com/jaseci-labs/jaseci/releases/download/dev/jac-dev-linux-x86_64 -o ~/.jacbin/jac
chmod +x ~/.jacbin/jac
export PATH="$HOME/.jacbin:$PATH"     # must win over any .jacvenv jac

# 2. deps into the binary's bundled CPython (a system pip is invisible to it)
jac install                            # if a stale .jac/venv exists → rm -rf .jac/venv first

# 3. Redis for the metric cache (local container)
docker run -d --name dash-redis -p 6379:6379 redis:7

# 4. run
jac start main.jac
```

**Two traps this exact toolchain has (from hard experience):**
- **`jac install` AND `jac start` both rewrite `jac.toml` and STRIP ALL COMMENTS.** Snapshot it
  (`git show HEAD:jac.toml > /tmp/keep`) and restore after. If you write a `dev-up.sh`, bake the
  restore in (restore after install, and background-restore once `:8000` responds).
- **`.jacvenv` `jac check` is permissive** — it silently passes things the native compiler rejects
  (e.g. an in-body `"""docstring"""` inside a function body → native `E0002` "Missing ';'" → **no
  bytecode** → `No bytecode found for X.jac` at import). Always verify with the **native** `jac check`
  and a real `jac start`, not just the venv check. Put docstrings *before* the def, never inside the body.

*(If you keep the app minimal — no Redis, cache in-process, no deploy — a plain pip `jaclang` may
suffice and you can skip the native binary. But the moment you want Redis or K8s deploy, use the
native binary.)*

---

## 4. The PostHog contract (the only external dependency)

- **Project id:** `425465`
- **Query API (READ):** `POST https://us.posthog.com/api/projects/425465/query/` with body
  `{"query": {"kind": "HogQLQuery", "query": "<SQL>"}}` and header `Authorization: Bearer <phx_ key>`.
- **The key:** `POSTHOG_API_KEY` (starts `phx_`) — a **personal READ key**. It is **SERVER-ONLY**:
  lives in the pod env, used only inside `metrics_sv.jac`, **never** shipped to the client / a
  `.cl.jac` file / a Vite define. The browser calls your walkers; your walkers call PostHog.
- Get the key value from **jac-ide's `.env`** (`grep POSTHOG_API_KEY /path/to/jac-ide/.env`) and put
  it in the new app's `.env` + the deploy secret. (There's also a public `phc_` *write* token — you
  do NOT need it for the dashboard; that's for emitting events, which this app never does.)
- **Load the `posthog-jac-builder` skill** in the new session — it has the curl recipes, the
  materialized-property notes, and the account details, and confirms the key is already configured.

**Verified event contract** (these are firing live as of PR #607 — build tiles against them):
`auth_signup_succeeded {method, source}`, `ai_message_sent {task_category, project_id, prompt_length,…}`,
`ai_message_completed {duration_ms, tool_call_count, response_length, files_changed, project_id}`,
`ai_generation_metered {cost_usd, model, project_id, run_id}` (server), `ai_response_rated {rating,…}`,
`ai_issue_reported {category,…}`, `generation_kept {message_id, project_id}`, `preview_start_requested
{was_prepared, project_id}` / `preview_ready {duration_ms}`, `deploy_*_{succeeded,failed}`; super-prop
`environment` (prod/dev/preview/local) on every event; person props `plan`, `auth_provider`. Full
list + which tile each feeds: `EVENT_CATALOG.md`.

### 4a. Managing PostHog (not just querying it)
PostHog already has assets built for this project — **reuse them, don't reinvent:**
- **~3 dashboards, ~24 insights, ~3 cohorts, ~2 alerts** already exist in project 425465. The SQL
  behind those insights is a ready-made starting point for your tile queries — pull an insight's
  query via the API and adapt it. `scripts/posthog-bootstrap.sh` (in jac-ide) recreates them.
- **Materialize `$host`** (PostHog UI → Data management → Properties → `$host` → Materialize). `$host`
  is a JSON prop, so any host-filtered/historical query full-scans and can 500/504. Do this **once,
  early** — it's the difference between snappy and timing-out. (Same applies to any prop you filter
  on heavily, e.g. `environment`, `method`.)
- **Management API** (create/edit insights, cohorts, alerts) uses the same `phx_` key against
  `/api/projects/425465/insights/`, `/cohorts/`, etc. — but you rarely need it: the dashboard is a
  read app. Keep management in PostHog's UI or the bootstrap script.
- **Load the `posthog-jac-builder` skill** — it's the authoritative reference for all of this (curl
  recipes, account, the key already being in `.env`, materialization, per-user deep-dives).

### 4b. Environment variables & secrets (the complete set)
Put these in the new app's `.env` (local) and the deploy secret (prod). Grab values from jac-ide's
`.env` where noted.

| Key | Purpose | Source / note |
|---|---|---|
| `POSTHOG_API_KEY` | **Read** key for the HogQL Query API | copy from jac-ide `.env` (`phx_…`). **SERVER-ONLY.** |
| `POSTHOG_HOST` | Query API host | `https://us.posthog.com` (constant; env only if you may switch regions) |
| `POSTHOG_PROJECT_ID` | Project id | `425465` (constant is fine) |
| `REDIS_URL` / `REDIS_HOST` / `REDIS_PORT` | metric cache | local `redis://localhost:6379`; prod = cluster Redis |
| `MONGODB_URI` | only if you persist saved views / admin users | optional — a pure read app can skip it |
| auth secret(s) | admin gate (JWT signing / admin creds) | depends on your auth choice (§ jac-sv-auth) |

**Do NOT** add the public `phc_` write token — this app never emits events. And **never** expose
`POSTHOG_API_KEY` to the client (no `.cl.jac`, no Vite `[plugins.client.vite.define]`).

---

## 5. Carry-over checklist (copy from jac-ide into the new repo)
- `.docs/posthog/DASHBOARD_APP_BUILD_SPEC.md`  ← the contract
- `.docs/posthog/EVENT_CATALOG.md`             ← the data dictionary
- `.docs/posthog/verify_deploy.py`             ← reuse its `hog()` helper + the presence-check pattern
- `.docs/posthog/prototype/`                   ← visual reference for the 11 pages (structure only)
- `POSTHOG_API_KEY` value from jac-ide `.env`  → new `.env`

Do NOT carry over jac-ide's app code — the dashboard is a clean, much simpler app.

---

## 6. Skills to load, by task
- Starting/scaffolding: `jac-project-kinds`, `jac-scaffold`, `jac-config`, `jac-fullstack-patterns`
- Server (walkers that query PostHog): `jac-sv-endpoints`, `jac-sv-auth` (admin gate), `jac-sv-deploy`
  (K8s + Redis + secrets), `jac-python-interop` (`requests`)
- Client (pages + state): `jac-cl-components`, `jac-cl-organization`, `jac-cl-routing`,
  `jac-cl-auth` (AuthGuard), `jac-cl-styling`
- UI + charts: `jac-shadcn`, `jac-shadcn-blocks`, `jac-shadcn-components`, `jac-npm-packages`
  (recharts), and **`dataviz`** — read it BEFORE writing any chart (one-axis rule, categorical color
  order, palette validation, tooltips/legend/table).
- PostHog: `posthog-jac-builder`
- Debugging Jac: `jac-debugging`, `jac-types`, `jac-testing`

---

## 7. Phase 0 — the concrete first slice (do this before any pages)

Goal: one real tile, end-to-end, proving the metric layer + env filter + secret hygiene.

1. **`metrics_sv.jac`** — server module with:
   - `glob _PH_KEY = os.environ.get("POSTHOG_API_KEY", "")` and `_PH_URL = "https://us.posthog.com/api/projects/425465/query/"`.
   - `def run_hogql(sql: str) -> dict` — `requests.post` with the Bearer key, 8s timeout, returns
     `results` or `{error}`. Swallow exceptions to a tile-level n/a.
   - `def _cache_get/_cache_put` via Redis, keyed `(metric_key, env, from, to)`, TTL ~10 min.
   - `walker:pub` (or admin-gated) `metric` that takes `key`, `env`, `from`, `to`, injects the
     env filter (`AND properties.environment = '<env>'`), runs the query (cache first), returns
     `{value, series, meta:{definition, window, caveat}}`.
2. **One metric — New signups:**
   ```sql
   SELECT count() FROM events
   WHERE event = 'auth_signup_succeeded'
     AND properties.environment = {env}
     AND timestamp >= {from} AND timestamp < {to}
   ```
   (Presence-check pattern if you ever test a prop: `coalesce(toString(properties.X),'') != ''` —
   `properties.X != ''` is a false-positive in HogQL.)
3. **One page — Overview** (`.cl.jac`): a top bar with an **env switcher** (Production default / Dev /
   All) and a **date range**, plus one stat tile that spawns the `metric` walker and renders the number
   with its definition tooltip. Prove that flipping the switcher changes the number (prod vs all).
4. Confirm it: the prod number should be much smaller than "all" (one PostHog project ingests
   prod+dev+preview+local — we measured `local=112, preview=73` in a single day of noise).

Once that slice works, the rest of the spec is filling in metrics + pages declaratively.

---

## 8. Drop-in CLAUDE.md for the new repo (append to the starter's)

```md
## Project: JacHammer Analytics Dashboard
Internal, read-only analytics cockpit. Full-stack Jac app. Reads PostHog via server-side HogQL.
Spec: .docs/posthog/DASHBOARD_APP_BUILD_SPEC.md · Events: .docs/posthog/EVENT_CATALOG.md
Visual spec: .docs/posthog/prototype/index.html (11 pages, env switcher, honesty labels — match it).
PostHog project 425465; assets (dashboards/insights/cohorts) already exist — reuse via posthog-jac-builder skill.
Secrets in .env: POSTHOG_API_KEY (phx_, READ, server-only), REDIS_URL, POSTHOG_HOST=https://us.posthog.com.
Materialize $host in PostHog before shipping (JSON prop → slow queries otherwise).

### Hard rules
- POSTHOG_API_KEY (phx_) is a READ key and is SERVER-ONLY — never in a .cl.jac file, client bundle,
  or Vite define. Client → walker → PostHog. Never client → PostHog.
- EVERY HogQL query injects the environment filter (properties.environment = <env>, default 'prod').
  One PostHog project ingests prod+dev+preview+local; unfiltered numbers are ~80% noise.
- Metrics take a real date_range; no hardcoded INTERVAL with a decorative label.
- Honest definitions on every tile: "active" = did a core action (not any event); reach vs users
  kept distinct; small-N flagged; every tile shows its window.
- HogQL: presence = coalesce(toString(properties.X),'') != '' ; numbers = toFloat64OrNull(toString(...)).
- Auth-method split = auth_signup_succeeded.method (event prop), NOT the auth_provider person prop.

### UI — jac-shadcn ONLY (strict)
- Every surface is a jac-shadcn component: Card tiles, Tabs, Select (env switcher), Table, Badge,
  Tooltip (definitions), Sidebar (nav), Skeleton, Sonner. NEVER a raw <div>+Tailwind where a
  component exists. Charts = recharts in the jac-shadcn Chart container; follow the dataviz skill.
- Install the FULL component set up front (`jac add --shadcn` for every component) right after
  scaffold. Read jac-shadcn / jac-shadcn-blocks / jac-shadcn-components before writing any JSX.

### Jac toolchain (this project)
- Run with the NATIVE jac binary (~/.jacbin/jac, has jaclang.scale); a pip jaclang lacks it.
- `jac install` AND `jac start` strip jac.toml comments — snapshot from git + restore.
- `.jacvenv` `jac check` is permissive; verify with the native binary. Docstrings go BEFORE the def,
  never inside a function body (native parser rejects it → "No bytecode found").
```

---

*Start with §0. The metric layer is the whole game — build it once, correctly, and every tile in the
spec becomes a few lines of config. The instrumentation is already live and verified; you're building
the read side only.*
