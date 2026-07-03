# Burn Dashboard — HTML/CSS/JS prototype

A **working, framework-free** prototype of the JacHammer burn-phase dashboard, rendered
from a **real PostHog snapshot**. Its job: let us *see the design + data working now*,
decoupled from the Jac runtime (which is blocked by the `jac start` core issue). When
`jac start` is healthy, this becomes the visual + data-shape spec for the Jac app.

Now a **multi-page sidebar app** (matching the mockup): 11 pages grouped in a left nav with per-page
readiness dots (🟢/🟡/🔴), hash-routed. The **Overview** page is fully built on real data; the other
10 pages are honest **stubs** that list each item's feasibility verdict (from `DASHBOARD_FEASIBILITY.md`)
and get built out per the v1 tier order.

## Files
| File | What |
|---|---|
| `index.html` | App shell — sidebar + topbar + content, all CSS. Loads `data.js` then `app.js`. |
| `app.js` | The app: hand-rolled SVG charts, hash router, Overview page, stub pages. No framework/CDN/build. |
| `data.js` | `window.DASHBOARD_DATA = {...}` — a real snapshot from PostHog project 425465. |
| `gen_data.py` | Re-pulls the snapshot (verified HogQL/native queries) and rewrites `data.js`. |

Navigate by clicking sidebar items (hash routes: `#overview`, `#users`, `#cost`, …).

## View it
Just **double-click `index.html`** — it loads `data.js` via a `<script>` tag, which works
over `file://` (no server needed, no key in the browser).

Or serve it (nicer for reloads):
```bash
cd .docs/posthog/prototype
python3 -m http.server 8899      # then open http://127.0.0.1:8899/index.html
```

## Refresh the data
```bash
cd .docs/posthog/prototype
python3 gen_data.py              # reads POSTHOG_API_KEY from repo .env, rewrites data.js
```
The `phx_` key stays server-side (Python only) — it never touches `index.html`.

**Environment switcher:** one PostHog project ingests dev + prod + previews, so `gen_data.py`
builds a snapshot **per environment** (`ENVIRONMENTS` = Production / Dev / All) by filtering each
query to that env's hosts. The top-bar toggle (`Production · Dev · All envs`) flips the entire
dashboard between them. Production = real end users (`jachammer.ai`); Dev = developers
(`jac-builder-dev.jaseci.org`). Edit `ENVIRONMENTS` if a domain changes.

## What's real vs. blocked
- **Live from PostHog:** North Star, retention heatmap, activation rate + funnel, TTFV,
  generation success, preview reliability, revert rate, new-vs-returning, signups,
  projects (+ source), active users, time-spent, deploy *intent*.
- **Blocked (shown with a 🔒 ribbon):** margin, burn/runway, CAC, power-user cost — need the
  credit-ledger + Stripe join (Section 4 of `../BURN_DASHBOARD_BUILD_SPEC.md`).
- **Fixed, pending prod deploy:** deploy *success* counts and Pro/Builder tier split
  (the two blind-spot fixes) — they'll populate once shipped.

## Design notes (dataviz method)
- Single blue hue for all time-series lines (magnitude), status colors (green/amber/red)
  reserved for the ▲/▼ slope badges only — never color-as-identity.
- Slopes compare the **last two complete weeks**; the in-progress week is drawn faded/dashed
  and excluded from ▲/▼ (slope-not-snapshot discipline).
- Hover any line for the crosshair + value tooltip.
- Every tile has a **`?` badge** with a plain-English explanation of what it means / what we track —
  **hover** on desktop, **tap to toggle** on touch (tap again or elsewhere to close).
- Cards in a row are **equal height**; line/bar charts stretch to fill (no empty boxes).
