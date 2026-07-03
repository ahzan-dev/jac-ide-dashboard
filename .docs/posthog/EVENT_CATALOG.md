# PostHog Event Catalog — CORE vs Secondary

> **Decision (initial / burn-phase):** we do **not** delete events. We **designate** a CORE set that the
> dashboard depends on and guarantee those fire correctly; everything else keeps firing but is labeled
> *secondary — not a dashboard input*. Rationale: deleting an event is irreversible for the **data** (you
> can't backfill what you stopped firing), volume is a non-issue (~50k/mo vs PostHog's 1M free tier), and
> the real problem was reliability (broken deploy events, bad props), not count.
>
> **Governance:** don't add a new event without a tile that consumes it. Don't change a CORE event's name
> or property contract without updating this file and `BURN_DASHBOARD_BUILD_SPEC.md`.

Total custom events: **74** → **26 CORE** · **48 secondary**. Plus person properties + auto-capture.

---

## CORE (26) — the dashboard contract

Audit each of these fires in the listed file with the listed props. `⚠` = known reliability issue (see bottom).

### Acquisition
| Event | Props (contract) | Powers | Fires in |
|---|---|---|---|
| `auth_signup_succeeded` | `provider` | Signups (Q1), activation denom, retention cohort | `SignUpForm.cl.jac` |
| `auth_succeeded` | `method`, `is_new_user` | Active signed-in users (Q2) | `SignInForm`, `OAuthCallback` |
| `auth_sso_clicked` | `provider` | Channel / provider split | `SignInForm`, `SignUpForm` |

### Activation & engagement
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `app_loaded` | — | Active-user heartbeat; time-spent anchor | `frontend.cl.jac` |
| `ide_opened` | — | WAU / returning / lifecycle | `JacIDE.cl.jac` |
| `project_created` | `source` (prompt/template/import/folder_upload) | Projects + detail (Q3), funnel | `useDashboard.cl.jac` |

### AI engine
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `ai_message_sent` | `prompt_length`, `attached_files_count`, `task_category` 🆕 | Gen requested, funnel, task-mix | `useChatMode.cl.jac` |
| `ai_message_completed` | `duration_ms`, `files_changed`, `tool_call_count` (fixed), `response_length` 🆕 | **North Star**, activation, TTFV, gen-success | `useChatMode.cl.jac` |
| `ai_response_rated` 🆕 | `rating` (up/down), `message_id`, `files_changed` | AI Quality: helpful-rate, avg rating, low-rated, quality-by-model | `ChatPanel.cl.jac` (thumbs up/down) |
| `ai_message_failed` | `reason`, `at_phase`, `duration_ms` | Failure breakdown | `useChatMode.cl.jac` |
| `ai_user_aborted` | `duration_ms` | Give-up signal | `useChatMode.cl.jac` |
| `ai_message_reverted` | — | Quality proxy (until `generation_kept`) | `useChatMode.cl.jac` |

### Preview (value moment)
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `preview_start_requested` | `was_prepared` | Reliability denominator | `useIDE.cl.jac` |
| `preview_ready` | `duration_ms` | North Star, reliability numerator | `useIDE.cl.jac` |
| `preview_start_failed` | `reason`, `phase` | Reliability failures | `useIDE.cl.jac` |

### Deploy
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `deploy_sandbox_clicked` | — | Deploy intent (Q4) | `DeployPanel.cl.jac` |
| `deploy_sandbox_succeeded` | `status` | Deploy success (Q4) — 🔧 now fires after race fix | `useIDE.cl.jac` |
| `deploy_sandbox_failed` | `status` | Deploy failure | `useIDE.cl.jac` |
| `deploy_production_clicked` | `has_subdomain`, `has_domain`, `has_cert_email` | Deploy intent (Q4) | `DeployPanel.cl.jac` |
| `deploy_production_succeeded` | `status`, `has_custom_domain` | Deploy success — 🆕 added | `useIDE.cl.jac` |
| `deploy_production_failed` | `status` | Deploy failure — 🆕 added | `useIDE.cl.jac` |

### Monetization intent (leading revenue signal — $ itself is Stripe, not PostHog)
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `upgrade_checkout_clicked` | `plan` | Upgrade intent | `UpgradeModal.cl.jac` |
| `topup_checkout_clicked` | `pack` | Top-up intent | `TopUpModal.cl.jac` |

### Cost (server-side emitted — the one backend event)
| Event | Props | Powers | Fires in |
|---|---|---|---|
| `ai_generation_metered` 🆕 | `cost_usd`, `model`, `project_id`, `run_id` | Inference spend, cost/generation, cost-per-active-user, **margin cost-side**, power-user cost | `services/jaccoder_client.jac` (`_record_user_cost_entry`) |

> This is the **only backend-captured** event — sent via `requests.post(.../capture/)` with the public `phc_` key, fired once per turn right after the credit-ledger write (idempotency guard prevents doubles). `distinct_id` = `profile.display_name` (the auth username the frontend `identify()`s with) so it lands on the right person. Emits the **real metered $** (from byLLM → litellm cost), not tokens. Requires `POSTHOG_PROJECT_TOKEN` (or `VITE_PUBLIC_POSTHOG_PROJECT_TOKEN`) in the **backend** env — must be added to the prod pod secret. No-ops if the key is absent.

### Feature adoption (core-adjacent — the "% of actives using X" tile)
| Event | Powers | Fires in |
|---|---|---|
| `git_commit_succeeded` | git adoption | `useGit.cl.jac` |
| `github_connect_succeeded` | github adoption | `GitPanel.cl.jac` |
| `project_shared` | community/share adoption | `ShareModal.cl.jac` |
| `export_downloaded` | export adoption; churn-risk cohort | `ExportPanel`, `JacIDE` |

---

## Super property (on EVERY event — filter product metrics by this)
- `environment` 🆕 — `prod` / `dev` / `preview` / `local`, registered in `initAnalytics()` (`utils/analytics.cl.jac`) from the hostname. **One PostHog project ingests all environments; only `prod` (jachammer.ai) is real end users.** Every dashboard query must filter `environment = 'prod'` (or `$host` for historical data before this shipped). See DASHBOARD_FEASIBILITY §Reality #0.

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
**AI UI:** `ai_image_attached` · `ai_message_blocked_quota` · `ai_model_switched_from_chat` · `ai_model_locked_clicked_from_chat`
**Preview UI:** `preview_tab_changed` · `preview_viewport_changed` · `preview_link_shared` · `preview_share_menu_opened`
**Git/GitHub (edge):** `git_commit_attempted` · `git_commit_failed` · `github_connect_clicked` · `github_connect_failed`
**Deploy upsell:** `deploy_sandbox_upgrade_clicked` · `deploy_production_upgrade_clicked`
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

*Generated from source on the current branch. Re-run the extraction if `track()` calls change.*
