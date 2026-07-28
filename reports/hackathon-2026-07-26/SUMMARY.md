# JacHammer Hackathon Report — Executive Summary

**Window:** 2026-07-26 17:00 → 2026-07-27 03:30 UTC (10.5 h — corrected end time) · **Platform:** jachammer.ai (prod events only)

## Headline numbers

| Metric | Value |
|---|---|
| Unique visitors (any prod event) | **357** |
| New signups | **112** (40 GitHub · 68 Google · 3 password) |
| Returning sign-ins (pre-existing accounts) | **8** |
| Users who used the AI builder | **55** |
| Projects created | **48** by 31 users |
| AI turns (sent → completed) | **373 → 302** |
| **Total AI cost (metered)** | **$526.62** across 301 runs |
| BYOK usage | **1 run** ($0.31) — everything else platform-keyed |
| Previews (requested → ready) | 309 → 315 (22 failed) |
| Sandbox deploys (click → success) | 70 clicks (18 users) → **37 succeeded** (11 users), 30 failed |
| Production deploys (click → success) | 53 clicks (15 users) → **26 succeeded** (9 users), 10 failed |
| GitHub connected | **14 users** (6 failures) |
| Upgrades completed | **53** (intent clicks: 56; failed: 3) — $1,135.00 checkout value |
| Users who hit an AI failure | 10 users, 52 failures |
| Users blocked by quota | 6 |

## Cost by model

| Model | Runs | Users | Total $ | Avg $/run | Max $/run |
|---|---|---|---|---|---|
| claude-sonnet-4-6 | 210 | 50 | 229.4527 | 1.09263 | 9.0239 |
| claude-opus-4-6 | 63 | 7 | 194.5823 | 3.08861 | 25.9825 |
|  | 19 | 12 | 98.3277 | 5.17514 | 20.0071 |
| gpt-5.4 | 2 | 1 | 3.1781 | 1.58903 | 1.7386 |
| gpt-5.2 | 6 | 2 | 0.7694 | 0.12823 | 0.2298 |
| claude-opus-4-5-20251101 | 1 | 1 | 0.3051 | 0.30508 | 0.3051 |

## Five findings that matter

1. **Sonnet 4.6 was the workhorse, Opus 4.6 the cost driver.** See the cost-by-model table above —
   Opus averages ~3× Sonnet's per-run cost, with single turns up to $26.
2. **BYOK was essentially unused**: 1 run out of 301 ($0.31). The hackathon ran ~100% on platform keys.
3. **19 metered runs carry a blank `model` property totaling $98.33** — an
   instrumentation gap worth fixing (they're real spend, unattributable to a model).
4. **Project starts were prompt-first**: 35/48 from a prompt, 4 from templates,
   5 import, 4 folder upload. GitHub import was almost never the entry path.
5. **Deploy friction was real**: sandbox success ratio 37/67 events; 6 users hit AI quota blocks and
   3 upgrade checkouts failed — see REPORT.md §Issues for names.

Full detail: `REPORT.md` · raw tables: `data/*.csv`
