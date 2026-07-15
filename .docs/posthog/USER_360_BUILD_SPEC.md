# User 360 + Satisfaction Agent — Build Spec

> **Status:** design only — not built. This is the plan to build from.
> **Repo:** `jac-ide-dashboard` (the internal analytics app; separate from the product `jac-ide`).
> **One-liner:** a per-user deep-dive page — pick a user (sorted by last activity), and see everything about them in one place: their session replays, activity timeline, profile, projects + status, chat history, and an LLM-judged satisfaction score.

This productizes the manual "power-user deep-dive" recipe (`docs/USER_DEEPDIVE_*.md`) into a page anyone on the team can open.

---

## 1. The idea (as given)

A **Users** view that lists users by **last login**, and for each user shows:
1. **Session replay** (embedded / iframe)
2. **Activities** (what they did)
3. **Their details** (whatever profile info we have)
4. **Projects they created** + **the status** of each
5. **Chat history**
6. **Satisfaction**

The idea is good — a "User 360" is a standard, high-value internal tool. The refinements below are about **where each piece of data actually lives** and **not over-building** for hackathon scale.

---

## 2. The one decision that shapes everything: two data planes

The dashboard today talks to **exactly one source — PostHog**. But the six panels above are split across **two** sources, and pretending they all come from PostHog is the trap:

| Data | Lives authoritatively in… | In PostHog? |
|---|---|---|
| Last active / login | PostHog events (`auth_succeeded`, `ide_opened`) | ✅ yes |
| Session replay | **PostHog** (native) | ✅ yes |
| Activity timeline | PostHog events | ✅ yes |
| User details (name/email/tier) | jac-ide `UserProfile` + billing | ⚠️ partial (person props: name, email, plan) |
| **Projects + live status** | **jac-ide `Project` nodes** (name, branch, last_commit, preview/deploy status) | ❌ only *creation* + *deploy attempts* as events — **no live status** |
| **Full chat history** | **jac-ide `JacCoderMessage` nodes** (complete, incl. steps) | ⚠️ only `ai_turn_transcript` (opt-in, prompt+reply, truncated) |
| Satisfaction | derived (agent over transcripts) | ✅ from `ai_turn_transcript` |

**Takeaway:** PostHog is the right source for **behavior** (activity, replays, last-active, satisfaction). It is **not** a reliable source for **authoritative product state** (live project status, full chat). Those live in the jac-ide backend graph.

### The better path: PostHog-first, phased — add a jac-ide read API only when you must

- **Phase 1 (recommended first ship — PostHog only, zero coupling):** everything derivable from PostHog events + person properties + replays + `ai_turn_transcript`. Ships fast, keeps the dashboard decoupled, good enough for the hackathon.
- **Phase 2 (authoritative — adds one thin read-only admin API on jac-ide):** a single `admin_user_snapshot(user_id)` walker on the jac-ide backend (behind an admin token) that returns the `UserProfile` + `Project` list **with live status** + full `JacCoderMessage` history + billing. The dashboard calls it only for the panels PostHog can't serve well.

> **Why phase it:** coupling the dashboard to the product backend (Phase 2) is a real architectural commitment — cross-service auth, a stable admin contract, a new attack surface on user data. Don't take it on until "live project status" and "full chat history" are genuinely must-haves. For the hackathon, Phase 1's approximations (project *count* from `project_created`, chat from `ai_turn_transcript`) are almost certainly enough.

---

## 3. Panel-by-panel: source, fetch, phase

| Panel | Phase 1 source (PostHog) | Phase 2 upgrade (jac-ide API) |
|---|---|---|
| **User list (by last active)** | HogQL: `SELECT person_id, max(email/name), max(timestamp) last_seen, count() events GROUP BY person_id ORDER BY last_seen DESC` | — |
| **Details** | person properties: `email`, `name`, `plan`, `auth_provider`, first-touch `utm_*` | `UserProfile` (user_id, display_name, created_at, tier) + billing (credits, MRR) |
| **Activity timeline** | events for that `distinct_id`, chronological (reuse the deep-dive recipe) | — (PostHog is canonical) |
| **Session replays** | list via `/session_recordings?person_uuid=…`; **deep-link** each to PostHog's player | **embed** via share-token iframe (only if viewers lack PostHog logins) |
| **Projects + status** | `project_created` events → count, source, created_at (⚠️ **no live status**) | `Project` nodes → name, active_branch, last_commit, **live preview/deploy status** |
| **Chat history** | `ai_turn_transcript` events (prompt + reply, opt-in) | `JacCoderMessage` nodes → full history incl. steps + checkpoints |
| **Satisfaction** | agent over `ai_turn_transcript` (see §5) | same (transcript is the input either way) |

---

## 4. Architecture (fits the existing dashboard)

The dashboard is a Jac app: `metrics_sv.jac` runs server-side HogQL/PostHog queries with the **personal API key** + Redis cache, and a byLLM **Ask planner**. The User 360 slots in the same way — **new server functions + two client pages**, no new infra.

```
Client (new)                          Server (metrics_sv.jac + new module)
─────────────                         ─────────────────────────────────────
UsersListPage  ──/user_list──▶        user_list(env, page)  → HogQL persons+last_seen
UserDetailPage ──/user_snapshot──▶    user_snapshot(distinct_id) → parallel:
  ├ Details tile                        • person props (PostHog persons API)
  ├ Activity timeline                   • events (PostHog events API)
  ├ Replays (deep-link/iframe)          • recordings list (session_recordings API)
  ├ Projects (count/status)             • project_created events  [P1] / admin API [P2]
  ├ Chat history                        • ai_turn_transcript events [P1] / admin API [P2]
  └ Satisfaction tile        ──────▶    satisfaction_for(distinct_id) → cached score (§5)
```

- **Reuse:** `run_hogql` / `run_query`, `env_filter`, the Redis cache (`_cache_get/_put`), the `INSIGHT_LLM` byLLM model, and the deep-dive recipe in the skill.
- **New server module** (e.g. `users_sv.jac`): `user_list`, `user_snapshot`, `user_recordings`, `satisfaction_for`.
- **New client pages:** `UsersListPage` (table, sort by last-seen, search) + `UserDetailPage` (tabbed/section layout for the 6 panels).
- **Auth:** this exposes **PII + chat content + replays** → it must be **internal-only** (same gate as the rest of the CEO dashboard; do not expose publicly). Call this out loudly in the build.

---

## 5. The satisfaction agent

An LLM judges satisfaction from the actual conversation (`ai_turn_transcript` = `prompt` + `response`), which is a far better signal than the thumbs up/down.

**Design (the better path — batch + cache, not live):**
1. **Input:** `ai_turn_transcript` events for a user, grouped by `distinct_id`, ordered by time. (Requires `JAC_STORE_AI_TRANSCRIPTS=true` on the product deploy.)
2. **Per-turn judge** (byLLM), structured output:
   ```
   obj TurnSatisfaction {
       has score: int = 3;          # 1..5 (1 frustrated → 5 delighted)
       has label: str = "neutral";  # frustrated | neutral | satisfied
       has signal: str = "";        # one-line reason, cites the turn
   }
   ```
   Prompt it to weigh: did the reply address the ask? did the user immediately retry/rephrase (a low signal)? error replies. **Never invent** — score only from the text.
3. **Per-user rollup:** average score + trend (improving/declining across the session) + the single worst turn (for drill-in).
4. **Caching (important):** do **not** re-score on every page load — LLM latency + cost. Cache the per-turn score keyed by `message_id` (Redis or the dashboard store); only score transcripts you haven't seen. Store the rollup with a TTL. A nightly/on-demand batch job scores new turns.
5. **Output tile:** a per-user satisfaction score + sparkline + expandable list of low-scoring turns (each showing the prompt/reply that earned the score).

**Guardrails:**
- First-try-success (`turn_number=1` completed, no follow-up in the `conversation_id`) is a cheap *behavioral* proxy — show it alongside the LLM score as a sanity check.
- Exclude `is_error=true` turns from the "AI quality" read, or score them separately (a failure isn't the same as a bad answer).
- Sample, don't score-everything, if volume ever grows — for hackathon scale (dozens–hundreds of users) scoring all turns is fine.

---

## 6. Session replay integration — the practical bit

PostHog replays reach the dashboard three ways (simplest → most work):

1. **Deep-link (recommended for v1):** `user_recordings(distinct_id)` lists a user's sessions (duration, date, page count) via `GET /api/projects/425465/session_recordings/?person_uuid=…`; each row links to `us.posthog.com/project/425465/replay/{id}`. Zero player to build; works because the team has PostHog logins.
2. **Embed via share token:** `GET/PATCH …/session_recordings/{id}/sharing/` → `access_token` → iframe the shared player. Use only if non-PostHog people must watch. Scopes: `session_recording:read` + `sharing_configuration:read/write`.
3. **Full in-app player:** render rrweb snapshots yourself. **Don't** — PostHog's player is better and this is weeks of work.

---

## 7. Phasing / roadmap

- **Phase 1 — PostHog-only User 360 (ship first):** user list by last-seen, details from person props, activity timeline, replay **deep-links**, project **count** (from `project_created`), chat + satisfaction from `ai_turn_transcript` (needs the flag on), satisfaction agent with cached scores. No jac-ide coupling.
- **Phase 2 — authoritative product state:** add the read-only `admin_user_snapshot` walker on jac-ide → live **project status**, full **chat history**, tier/billing; wire the "Projects" + "Chat" panels to it. Embedded replays if needed.
- **Phase 3 — polish:** cross-user cohorts inline (e.g. "show only hackathon `utm_campaign` users"), satisfaction leaderboard, alerts on frustrated users.

---

## 8. Open decisions (need your call before building)

1. **Phase 2 now or later?** Do you need **live project status** + **full chat (with steps)**, or is Phase 1's PostHog approximation enough for the hackathon? (Recommend: Phase 1 first.)
2. **Replays:** deep-link (team has PostHog) or embedded (external viewers)?
3. **Satisfaction scale:** 1–5 score, or 3-way frustrated/neutral/satisfied? Per-turn, per-user, or both?
4. **Access:** confirm this page is behind the internal/admin gate — it shows PII + chat + replays.
5. **Transcript flag:** the whole chat/satisfaction half depends on `JAC_STORE_AI_TRANSCRIPTS=true` on the product deploy. Confirm it'll be on for the window you care about.

---

## 9. What I'd explicitly NOT do (anti-bloat)

- ❌ Don't build a custom rrweb player — deep-link PostHog's.
- ❌ Don't run the satisfaction LLM on every page load — batch + cache.
- ❌ Don't pull "live project status" from PostHog — it isn't there; use the admin API (Phase 2) or show creation-only for v1.
- ❌ Don't couple to the jac-ide backend until Phase 1 proves the page is worth it.
- ❌ Don't over-engineer pipelines for hackathon-scale volume — on-demand queries are fine.
