# JacHammer Hackathon Report — Executive Summary

**Window:** 2026-07-26 17:00 → 2026-07-27 00:30 UTC (7.5 h) · **Platform:** jachammer.ai (prod events only)

## Headline numbers

| Metric | Value |
|---|---|
| Unique visitors (any prod event) | **283** |
| New signups | **91** (33 GitHub · 55 Google · 3 password) |
| Returning sign-ins (pre-existing accounts) | **5** |
| Users who used the AI builder | **43** |
| Projects created | **40** by 29 users |
| AI turns (sent → completed) | **297 → 242** |
| **Total AI cost (metered)** | **$351.76** across 230 runs |
| BYOK usage | **1 run** ($0.31) — everything else platform-keyed |
| Previews (requested → ready) | 198 → 220 (2 failed) |
| Sandbox deploys (click → success) | 38 clicks (9 users) → **20 succeeded** (6 users), 21 failed |
| Production deploys (click → success) | 9 clicks (5 users) → **6 succeeded** (2 users), 1 failed |
| GitHub connected | **13 users** (2 failures) |
| Upgrades completed | **44** (intent clicks: 49; failed: 3) — $970.00 checkout value |
| Users who hit an AI failure | 8 users, 40 failures |
| Users blocked by quota | 5 |

## Cost by model

| Model | Runs | Users | Total $ | Avg $/run | Max $/run |
|---|---|---|---|---|---|
| claude-sonnet-4-6 | 172 | 39 | 198.1704 | 1.15215 | 9.0239 |
| claude-opus-4-6 | 38 | 6 | 102.7264 | 2.70333 | 25.9825 |
|  | 11 | 8 | 46.606 | 4.23691 | 10.6238 |
| gpt-5.4 | 2 | 1 | 3.1781 | 1.58903 | 1.7386 |
| gpt-5.2 | 6 | 2 | 0.7694 | 0.12823 | 0.2298 |
| claude-opus-4-5-20251101 | 1 | 1 | 0.3051 | 0.30508 | 0.3051 |

## Five findings that matter

1. **Sonnet 4.6 was the workhorse, Opus 4.6 the cost driver.** Sonnet: $198.17 over 172 runs (39 users).
   Opus: $102.73 over just 38 runs by 6 users — avg $2.70/run, one single turn cost **$25.98**.
2. **BYOK was essentially unused**: 1 run out of 230 ($0.31). The hackathon ran ~100% on platform keys.
3. **11 metered runs carry a blank `model` property totaling $46.61** — an
   instrumentation gap worth fixing (they're real spend, unattributable to a model).
4. **Project starts were prompt-first**: 35/40 from a prompt, 4 from templates,
   1 import, 0 folder upload. GitHub import was almost never the entry path.
5. **Deploy friction was real**: sandbox success ratio 20/41 events; 5 users hit AI quota blocks and
   3 upgrade checkouts failed — see REPORT.md §Issues for names.

Full detail: `REPORT.md` · raw tables: `data/*.csv`
