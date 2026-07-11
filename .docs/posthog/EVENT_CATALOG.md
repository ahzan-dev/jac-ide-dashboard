# PostHog Event Catalog — CORE vs Secondary

> **Decision (initial / burn-phase):** we do **not** delete events. We **designate** a CORE set that the
> dashboard depends on and guarantee those fire correctly; everything else keeps firing but is labeled
> *secondary — not a dashboard input*. Rationale: deleting an event is irreversible for the **data** (you
> can't backfill what you stopped firing), volume is a non-issue (~50k/mo vs PostHog's 1M free tier), and
> the real problem was reliability (broken deploy events, bad props), not count.
>
> **Governance:** don't add a new event without a tile that consumes it. Don't change a CORE event's name
> or property contract without updating this file and `BURN_DASHBOARD_BUILD_SPEC.md`.

Total custom events: **80** → **32 CORE** · **48 secondary**. Plus person properties + auto-capture.
The tracking-gaps pass (2026-07) added the money-loop, AI-quality-threading, first-touch attribution, and
session events marked 🆕✨ below — each backed by a tile in `metrics_sv.jac`. All read empty until the
jac-ide instrumentation ships to prod **and** prod is `environment='prod'`-tagged.

---

## CORE (26) — the dashboard contract

Audit each of these fires in the listed file with the listed props. `⚠` = known reliability issue (see bottom).

### Acquisition
| Event | Props (contract) | Powers | Fires in |
|---|---|---|---|
| `auth_signup_succeeded` 🖥 | `method` (password/google/github), `source`, `signup_trigger` 🆕✨ (guest_locked_feature/free_signup_bonus/dashboard_prompt/direct), `utm_source`/`utm_medium`/`utm_campaign`/`referrer` 🆕✨ (first-touch) | Signups (Q1), activation denom, retention cohort, **signup-trigger** (`signup_trigger_breakdown`), **acquisition channel** (`acquisition_channel`) | `services/ideServer.jac` (`me` walker, both create paths) |
| `auth_succeeded` | `method`, `is_new_user` | Active signed-in users (Q2) | `SignInForm`, `OAuthCallback` |
| `auth_sso_clicked` | `provider` | Channel / provider split | `SignInForm`, `SignUpForm` |

> **`auth_signup_succeeded` moved server-side.** It now fires from the `me` walker (once per profile create) so SSO signups are counted, not just password. `provider` is gone — use `method`. First-touch UTM is threaded onto it explicitly (client super-properties never reach a server-emitted event), so channel attribution reads `properties.utm_source` **on this event**.

### Activation & engagement
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `app_loaded` | — | Active-user heartbeat; time-spent anchor | `frontend.cl.jac` |
| `ide_opened` | — | WAU / returning / lifecycle | `JacIDE.cl.jac` |
| `ide_session_ended` 🆕✨ | `duration_active_ms` (FOCUSED time, not wall-clock), `duration_wall_ms`, `files_touched`, `previews_run`, `ended_reason` (close/nav), `session_id` | Real session depth / time-on-task (`session_depth`) | `pages/JacIDE.cl.jac` (visibilitychange + beforeunload) |
| `project_created` | `source` (prompt/template/import/folder_upload), `project_type` 🆕✨, `files_count` 🆕✨ (folder_upload only) | Projects + detail (Q3), funnel, project-complexity | `useDashboard.cl.jac` |

### AI engine
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `ai_message_sent` | `prompt_length`, `attached_files_count`, `task_category` 🆕, `model` 🆕✨, `conversation_id` 🆕✨, `turn_number` 🆕✨ | Gen requested, funnel, task-mix, per-model | `useChatMode.cl.jac` |
| `ai_message_completed` | `duration_ms`, `files_changed`, `tool_call_count` (fixed), `response_length` 🆕, `model` 🆕✨, `conversation_id` 🆕✨, `turn_number` 🆕✨, `message_id` 🆕✨ | **North Star**, activation, TTFV, gen-success, **first-try success** (`first_try_success`), **per-model latency/usage** (`model_latency`/`model_usage`) | `useChatMode.cl.jac` |
| `ai_response_rated` 🆕 | `rating` (up/down), `message_id` (now stable ✨), `files_changed` | AI Quality: helpful-rate, avg rating, low-rated, quality-by-model | `ChatPanel.cl.jac` (thumbs up/down) |
| `ai_issue_reported` 🆕✨ | `category`, `message_id` (now stable ✨) | Issue-category breakdown (`issue_categories`) | `ChatPanel.cl.jac` (down-vote chips) |
| `ai_response_edited` 🆕✨ | `message_id`, `time_to_edit_ms`, `files_changed` | Real acceptance signal — user manually edited AI output (`ai_edits`); replaces the weak kept/revert proxies | `useIDE.cl.jac` (`saveFile` on an AI-authored file) |
| `ai_message_failed` | `reason`, `at_phase`, `duration_ms`, `model`/`conversation_id`/`turn_number` 🆕✨ | Failure breakdown | `useChatMode.cl.jac` |
| `ai_user_aborted` | `duration_ms` | Give-up signal | `useChatMode.cl.jac` |
| `ai_message_reverted` | `conversation_id`/`turn_number` 🆕✨ | Quality proxy (until `generation_kept`) | `useChatMode.cl.jac` |

> **AI threading.** `conversation_id` is a **client-minted thread id** (not the jac-coder session id) minted at the first send and reused across the turn's events, so `sent`/`completed` always agree. `turn_number` is shared via a ref between the two. `message_id` is a **client-minted UUID** reused synchronously and persisted as the `JacCoderMessage` id — that's what finally gives `ai_response_rated`/`ai_issue_reported` a non-empty id. `model` is the model that **actually ran** (from the start report), now on the timing events, not only `ai_generation_metered`.

### Preview (value moment)
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `preview_start_requested` | `was_prepared` | Reliability denominator | `useIDE.cl.jac` |
| `preview_ready` | `duration_ms`, `cold_start` 🆕✨ | North Star, reliability numerator, cold-only reliability (`cold_preview_reliability`) | `useIDE.cl.jac` |
| `preview_start_failed` | `reason`, `phase` | Reliability failures | `useIDE.cl.jac` |

> `cold_start` reads "always cold" today — the pre-warm plumbing (`preparedPreviewProjectRef`) is dormant, so honest but low-signal until a real pre-warm trigger ships.

### Deploy
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `deploy_sandbox_clicked` | — | Deploy intent (Q4) | `DeployPanel.cl.jac` |
| `deploy_sandbox_succeeded` | `status` | Deploy success (Q4) — 🔧 now fires after race fix | `useIDE.cl.jac` |
| `deploy_sandbox_failed` | `status` | Deploy failure | `useIDE.cl.jac` |
| `deploy_production_clicked` | `has_subdomain`, `has_domain`, `has_cert_email` | Deploy intent (Q4) | `DeployPanel.cl.jac` |
| `deploy_production_succeeded` | `status`, `has_custom_domain` | Deploy success — 🆕 added | `useIDE.cl.jac` |
| `deploy_production_failed` | `status` | Deploy failure — 🆕 added | `useIDE.cl.jac` |

### Monetization (intent + completion — the money loop)
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `upgrade_checkout_clicked` | `plan` | Upgrade **intent** | `UpgradeModal.cl.jac` |
| `upgrade_checkout_succeeded` 🆕✨🖥 | `plan`, `plan_from`, `amount_usd`, `interval`, `is_first_upgrade`, `stripe_customer_id` | **Completed upgrade** — paid conversion (`upgrade_conversion`), completed upgrades (`paid_upgrades`) | `services/billing_ops.jac` (`_apply_billing_event_to_user`, subscribe) |
| `subscription_canceled` 🆕✨🖥 | `plan_from`, `plan_to`, `mrr_delta`, `days_active` | Revenue churn (`mrr_churn`) | `services/billing_ops.jac` (cancel branch) |
| `subscription_downgraded` 🆕✨🖥 | `plan_from`, `plan_to`, `mrr_delta`, `days_active` | Downgrade driver | `services/billing_ops.jac` (subscribe, rank↓) |
| `topup_checkout_clicked` | `pack` | Top-up intent | `TopUpModal.cl.jac` |

> **Money-loop events are server-side + idempotent.** They fire from inside `_apply_billing_event_to_user` on `customer.subscription.created/.updated/.deleted` (NOT checkout/invoice — the tier flip happens there). Only a real tier change fires; a redelivered webhook sees `old==new` and no-ops. `is_first_upgrade` is authoritative (checks for a prior subscription grant, not the `old_tier=='free'` proxy).

### Cost (server-side emitted)
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `ai_generation_metered` 🆕 | `cost_usd`, `model`, `project_id`, `run_id` | Inference spend, cost/generation, cost-per-active-user, **margin cost-side**, power-user cost | `services/jaccoder_client.jac` (`_record_user_cost_entry`) |

> **Server-side capture (5 events).** `ai_generation_metered` + `auth_signup_succeeded` + the three money-loop events are all sent via `requests.post(.../capture/)` with the public `phc_` key through the shared `_post_posthog_capture`, which now does a **bounded retry** (3 tries, 0.5s→1.5s, stop on 4xx) so a transient blip can't silently drop a revenue/cost event. `distinct_id` = `analytics_distinct_id(profile)` = **`analytics_id or user_id`** (the id the frontend `identify()`s with; deliberately NOT `display_name`, which differs for SSO / renamed users and would attach to a phantom person). Emits the **real metered $** (byLLM → litellm cost), not tokens. Requires `POSTHOG_PROJECT_TOKEN` (or `VITE_PUBLIC_POSTHOG_PROJECT_TOKEN`) in the **backend** env. No-ops if the key is absent.

### Feature adoption (core-adjacent — the "% of actives using X" tile)
| Event | Powers | Fires in |
|---|---|---|
| `git_commit_succeeded` | git adoption | `useGit.cl.jac` |
| `github_connect_succeeded` | github adoption | `GitPanel.cl.jac` |
| `project_shared` | community/share adoption | `ShareModal.cl.jac` |
| `export_downloaded` | export adoption; churn-risk cohort | `ExportPanel`, `JacIDE` |

---

## Super property (on EVERY event — filter product metrics by this)
- `environment` 🆕 — `prod` / `dev` / `preview` / `local`, registered in `initAnalytics()` (`utils/analytics.cl.jac`) from the hostname. **One PostHog project ingests all environments; only `prod` (jachammer.ai) is real end users.** Every dashboard query must filter `environment = 'prod'` (or `$host` for historical data before this shipped). See DASHBOARD_FEASIBILITY §Reality #0. **NOTE:** super-properties ride **client** events only — server-emitted events (the 5 above) re-add `environment` explicitly; anything else you register must be threaded onto server events by hand (this is why UTM had to be added to `auth_signup_succeeded` explicitly).
- `utm_source`/`utm_medium`/`utm_campaign`/`utm_content`/`referrer`/`initial_referring_domain`/`landing_path` 🆕✨ — first-touch, `register_once` in `captureFirstTouch()` (`utils/analytics.cl.jac`) at landing. On **client** events they ride as super-properties; for **signups** read them off `auth_signup_succeeded` (threaded explicitly). Empty = direct/no campaign.

## Person properties (DO NOT touch — these slice every chart)
- `plan` 🆕 — free/builder/pro, from `me.billing` (`useUserTier.cl.jac`)
- `is_guest`, `auth_provider` — from `identify()` on login/SSO/guest
- `name`, `email`, `display_name` — identification / Persons UI display
- `theme`, `resolved_theme` — from `useTheme`

## Auto-captured (keep)
- `$pageview` + `$pageleave` — **the time-spent source (Q7)**
- `$identify`, `$set` — identity writes
- `$exception` — JS errors (many blank = CORS redaction, not a bug)
- Autocapture limited to `[data-ph-track]`, click/submit only
- Session replay masked on `[data-ph-mask]`, `code`, `pre`, `.monaco-editor`

---

## Secondary (48) — keep firing, do NOT build tiles on them

Free insurance for future deep-dives. Not part of the dashboard contract.

**Auth/onboarding UI:** `auth_page_viewed` · `auth_tab_switched` · `auth_login_submitted` · `auth_signup_submitted` · `auth_failed` · `auth_logged_out` · `signup_gate_opened`
**Guest:** `guest_home_viewed` · `guest_chip_clicked` · `guest_prompt_submitted` · `guest_locked_feature_clicked`
**Dashboard UI:** `dashboard_viewed` · `dashboard_prompt_submitted`* · `dashboard_suggestion_clicked`
**Projects (edge/error):** `project_creation_failed` · `project_creation_blocked_quota` · `project_deleted` · `project_share_failed` · `project_share_blocked_quota`
**IDE UI:** `ide_v2_tab_changed` · `inspector_element_selected` · `intent_dispatched`
**AI UI:** `ai_image_attached` · `ai_message_blocked_quota` · `ai_model_switched_from_chat` (feeds `model_mix`) · `ai_model_locked_clicked_from_chat` · `ai_message_start_retry`
**Preview UI:** `preview_tab_changed` · `preview_viewport_changed` · `preview_link_shared` · `preview_share_menu_opened`
**Git/GitHub (edge):** `git_commit_attempted` · `git_commit_failed` · `github_connect_clicked` · `github_connect_failed`
**Deploy upsell:** `deploy_sandbox_upgrade_clicked` · `deploy_production_upgrade_clicked`
**Deploy/hero UI** (from the deploy-hero work, props not yet audited): `dashboard_card_deploy_clicked` · `sidebar_deploy_clicked` · `deploy_hero_github_import` · `hero_mode_changed`
**Billing UI/edge:** `chat_credit_pill_clicked` · `low_credit_cta_clicked` · `usage_tab_viewed` · `upgrade_checkout_failed` · `upgrade_modified` · `topup_checkout_failed` · `free_signup_bonus_shown` · `free_signup_bonus_cta_clicked` · `free_signup_bonus_dismissed`
**Notifications:** `notif_nudge_accepted` · `notif_nudge_dismissed`
**Misc:** `not_found_viewed`

\* `dashboard_prompt_submitted` is a candidate to promote to CORE if we want a top-of-funnel "prompt → project" conversion tile.

---

## Known reliability issues
1. **`token` prop — NOT a bug (corrected).** `properties.token` appears on *every* event with the public `phc_` project token. Our code never sets it — it's PostHog's standard ingestion field (the project API key every `posthog-js` payload carries). The `phc_` token is public-by-design (already ships in the client bundle). No leak, no action; just ignore it in the property list.
2. **`tool_call_count` — FIXED.** Was always `0`: the filter counted `type=="activity"` (only for `agent_activity` events, which current jac-coder doesn't emit) and `type=="agent_tool_done"` (a mutation branch that never creates such an activity). Real tool calls are stored as `type=="llm_tool_call"`. Now counts that (`useChatMode.cl.jac`). Pending prod deploy — verify `tool_call_count > 0` on new completions. `files_changed` remains the primary work proxy.
3. **Deploy outcomes** — 🆕/🔧 fixed in code (`useIDE.cl.jac`), **pending prod deploy**. Verify post-deploy that `deploy_*_succeeded` count > 0.
4. **`plan` person property** — 🆕 added, pending prod deploy. Verify persons carry `plan` (breakdown returns free/builder/pro, not null).
5. **Tracking-gaps events (🆕✨)** — instrumented on jac-ide `feat/posthog-tracking-gaps` (PR #652). All read empty until that ships to prod **and** prod is `environment='prod'`-tagged (env-tagging is on `dev`, reaches prod on the next `dev`→`main`). Verify post-deploy: `upgrade_checkout_succeeded` on the right person (Stripe test upgrade), `ai_response_rated`/`ai_issue_reported` carry a non-empty `message_id`, `ai_message_completed` carries `model`/`conversation_id`/`turn_number`, `auth_signup_succeeded` carries `signup_trigger` + `utm_*`.

*🆕✨ = added by the 2026-07 tracking-gaps pass. Re-run `scripts/extract-posthog-events.sh` (jac-ide) to regenerate the authoritative event list and diff it against this file when `track()`/`emit_event` calls change.*
