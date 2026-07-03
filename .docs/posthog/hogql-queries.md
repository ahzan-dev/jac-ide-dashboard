# HogQL Query Pack — Bet Monitor

One query per dashboard tile, written for the **PostHog Query API** (`HogQLQuery`). Drop each into the API call below and you get the numbers behind the mockup. These read the events defined in the Tracking Plan.

> **Notes before you start**
> - Time windows use `INTERVAL` — tune them per tile (slopes want 12 weeks, snapshots want 28 days).
> - Several "ever did step" funnel/retention queries are **approximations** that are fine for a leadership trend. Where PostHog has a *native* insight that's stricter (ordered funnels, retention matrix), I flag it — use the native one for the canonical number and HogQL for custom slicing.
> - `cost_usd` is assumed precomputed on `generation_succeeded` (see Tracking Plan §4). If you only stored tokens, replace `toFloat(properties.cost_usd)` with `(toFloat(properties.tokens_in)/1e6*3.0 + toFloat(properties.tokens_out)/1e6*15.0)`.

---

## How to call it (Query API)

```bash
curl -s https://us.posthog.com/api/projects/{PROJECT_ID}/query/ \
  -H "Authorization: Bearer $POSTHOG_PERSONAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "query": { "kind": "HogQLQuery", "query": "SELECT 1" } }'
```

```ts
// NestJS / fetch — wrap each tile query
async function hogql(query: string) {
  const r = await fetch(
    `https://us.posthog.com/api/projects/${PROJECT_ID}/query/`,
    { method: 'POST',
      headers: { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: { kind: 'HogQLQuery', query } }) }
  );
  const { results, columns } = await r.json();   // results = array of rows
  return { columns, results };
}
```

---

# SECTION 01 — THE BET

### 1. North Star — weekly active builders who ship
```sql
SELECT toStartOfWeek(timestamp) AS week,
       uniq(person_id)          AS builders_who_shipped
FROM events
WHERE event = 'app_deployed'
  AND timestamp >= now() - INTERVAL 12 WEEK
GROUP BY week
ORDER BY week
```

### 2. W4 retention by cohort  *(the slope that must bend up)*
Cohort = signup week. Retained = did a meaningful action in the 28–35 day window after signup.
```sql
WITH cohorts AS (
  SELECT person_id,
         toStartOfWeek(min(timestamp)) AS cohort_week,
         min(timestamp)                AS signup_ts
  FROM events WHERE event = 'signup'
  GROUP BY person_id
)
SELECT c.cohort_week AS cohort_week,
       uniq(c.person_id) AS cohort_size,
       uniqIf(c.person_id,
              e.timestamp >= c.signup_ts + INTERVAL 28 DAY
          AND e.timestamp <  c.signup_ts + INTERVAL 35 DAY) AS retained_w4,
       round(100.0 * uniqIf(c.person_id,
              e.timestamp >= c.signup_ts + INTERVAL 28 DAY
          AND e.timestamp <  c.signup_ts + INTERVAL 35 DAY) / uniq(c.person_id), 1) AS w4_retention_pct
FROM cohorts c
LEFT JOIN events e
       ON e.person_id = c.person_id
      AND e.event IN ('generation_requested','app_deployed')
WHERE c.cohort_week >= now() - INTERVAL 12 WEEK
GROUP BY cohort_week
ORDER BY cohort_week
```
> PostHog's native **Retention insight** computes this matrix more rigorously — use it as the source of truth and this for cohort-over-cohort slope charting.

### 3. Margin slope — cost/user vs revenue/user, weekly
```sql
SELECT week,
       round(cost_usd / nullIf(active_users, 0), 2)  AS cost_per_active,
       round(mrr      / nullIf(active_users, 0), 2)  AS revenue_per_active
FROM (
  SELECT toStartOfWeek(timestamp) AS week,
         sumIf(toFloat(properties.cost_usd), event = 'generation_succeeded') AS cost_usd,
         uniqIf(person_id, event IN ('generation_requested','app_deployed'))  AS active_users,
         sumIf(toFloat(properties.mrr),     event = 'subscription_started')   AS mrr
  FROM events
  WHERE timestamp >= now() - INTERVAL 12 WEEK
  GROUP BY week
)
ORDER BY week
```
> `revenue_per_active` here counts *new* MRR booked that week. For true ARPU, join against an MRR snapshot table; this version is fine for reading the slope.

---

# SECTION 02 — THE ENGINE

### 4. Activation rate — signups who ship their first app
```sql
SELECT count()                              AS signups,
       countIf(deployed > 0)                AS activated,
       round(100.0 * countIf(deployed > 0) / count(), 1) AS activation_rate_pct
FROM (
  SELECT person_id,
         minIf(timestamp, event = 'signup')      AS signup_ts,
         countIf(event = 'app_deployed'
                 AND timestamp > minIf(timestamp, event = 'signup')) AS deployed
  FROM events
  WHERE event IN ('signup','app_deployed')
  GROUP BY person_id
  HAVING signup_ts >= now() - INTERVAL 28 DAY
)
```

### 5. Time to first shipped app (median minutes)
```sql
SELECT round(median(ttfa_min), 1) AS median_ttfa_minutes,
       round(quantile(0.9)(ttfa_min), 1) AS p90_ttfa_minutes
FROM (
  SELECT person_id,
         dateDiff('minute',
                  minIf(timestamp, event = 'signup'),
                  minIf(timestamp, event = 'app_deployed')) AS ttfa_min
  FROM events
  WHERE event IN ('signup','app_deployed')
  GROUP BY person_id
  HAVING minIf(timestamp, event = 'app_deployed') > minIf(timestamp, event = 'signup')
     AND minIf(timestamp, event = 'signup') >= now() - INTERVAL 28 DAY
)
```

### 6. "Actually worked" rate — kept ÷ succeeded  *(the truth metric)*
```sql
SELECT countIf(event = 'generation_succeeded') AS succeeded,
       countIf(event = 'generation_kept')      AS kept,
       round(100.0 * countIf(event = 'generation_kept')
                   / nullIf(countIf(event = 'generation_succeeded'), 0), 1) AS kept_rate_pct
FROM events
WHERE event IN ('generation_succeeded','generation_kept')
  AND timestamp >= now() - INTERVAL 28 DAY
```

### 7. Activation funnel — drop-off by step
```sql
SELECT uniq(person_id)                  AS signup,
       uniqIf(person_id, has_project)   AS project,
       uniqIf(person_id, has_gen)       AS gen_success,
       uniqIf(person_id, has_preview)   AS preview,
       uniqIf(person_id, has_deploy)    AS deploy
FROM (
  SELECT person_id,
         countIf(event = 'project_created')      > 0 AS has_project,
         countIf(event = 'generation_succeeded') > 0 AS has_gen,
         countIf(event = 'app_previewed')        > 0 AS has_preview,
         countIf(event = 'app_deployed')         > 0 AS has_deploy
  FROM events
  WHERE event IN ('signup','project_created','generation_succeeded','app_previewed','app_deployed')
    AND timestamp >= now() - INTERVAL 28 DAY
  GROUP BY person_id
  HAVING countIf(event = 'signup') > 0
)
```
> This is an **unordered** "ever reached step" funnel. For strict ordering + time-to-convert per step, use PostHog's native **FunnelsQuery** — it enforces sequence and handles the conversion window. Keep this HogQL version for ad-hoc slicing (by channel, template, etc.).

---

# SECTION 03 — THE LEAK

### 8. Retention curve — weeks-since-signup (run once per cohort window to overlay)
```sql
WITH s AS (
  SELECT person_id, min(timestamp) AS signup_ts
  FROM events WHERE event = 'signup' GROUP BY person_id
)
SELECT dateDiff('week', s.signup_ts, e.timestamp) AS weeks_since,
       uniq(e.person_id)                          AS retained
FROM s
JOIN events e ON e.person_id = s.person_id
WHERE e.event IN ('generation_requested','app_deployed')
  AND s.signup_ts >= now() - INTERVAL 6 WEEK       -- "current" cohort; shift window for "prior"
  AND dateDiff('week', s.signup_ts, e.timestamp) BETWEEN 0 AND 4
GROUP BY weeks_since
ORDER BY weeks_since
```

### 9. Churn proxy (paid)
```sql
SELECT countIf(event = 'subscription_started')  AS new_subs,
       countIf(event = 'subscription_canceled') AS canceled,
       round(100.0 * countIf(event = 'subscription_canceled')
                   / nullIf(countIf(event = 'subscription_started'), 0), 1) AS churn_proxy_pct
FROM events
WHERE event IN ('subscription_started','subscription_canceled')
  AND timestamp >= now() - INTERVAL 30 DAY
```
> True churn needs an active-subscriber base, not just new subs. If you sync subscriptions to a PostHog data warehouse table (or via the Stripe connector), compute `canceled / active_at_start_of_period` instead.

### 10. Iterations per project, split by outcome  *(healthy vs failing)*
```sql
SELECT outcome,
       round(avg(iters), 1) AS avg_iterations,
       count()              AS projects
FROM (
  SELECT properties.project_id AS pid,
         countIf(event = 'generation_requested') AS iters,
         multiIf(countIf(event = 'app_deployed')     > 0, 'shipped',
                 countIf(event = 'project_abandoned') > 0, 'abandoned',
                 'open') AS outcome
  FROM events
  WHERE event IN ('generation_requested','app_deployed','project_abandoned')
    AND timestamp >= now() - INTERVAL 28 DAY
  GROUP BY pid
)
WHERE outcome IN ('shipped','abandoned')
GROUP BY outcome
ORDER BY outcome
```

### 11. Where projects die  *(the tile that exposed the post-preview leak)*
```sql
SELECT properties.last_stage AS stage,
       count()               AS abandons,
       round(100.0 * count() / sum(count()) OVER (), 1) AS pct_of_abandons
FROM events
WHERE event = 'project_abandoned'
  AND timestamp >= now() - INTERVAL 28 DAY
GROUP BY stage
ORDER BY abandons DESC
```

---

# SECTION 04 — COST OF THE BET

### 12. Cost per generation (weekly slope)
```sql
SELECT toStartOfWeek(timestamp)                 AS week,
       round(avg(toFloat(properties.cost_usd)), 3) AS cost_per_generation,
       count()                                   AS generations
FROM events
WHERE event = 'generation_succeeded'
  AND timestamp >= now() - INTERVAL 12 WEEK
GROUP BY week
ORDER BY week
```

### 13. Inference spend (monthly)
```sql
SELECT toStartOfMonth(timestamp)                AS month,
       round(sum(toFloat(properties.cost_usd)), 0) AS inference_spend_usd,
       round(sum(toFloat(properties.cost_usd))
             / nullIf(uniq(person_id), 0), 2)   AS cost_per_active_user
FROM events
WHERE event = 'generation_succeeded'
  AND timestamp >= now() - INTERVAL 6 MONTH
GROUP BY month
ORDER BY month
```

### 14. Value per user by acquisition channel
```sql
SELECT person.properties.acquisition_channel AS channel,
       uniq(person_id)                        AS users,
       round(sumIf(toFloat(properties.mrr), event = 'subscription_started')
             / nullIf(uniq(person_id), 0), 2) AS rev_per_user_usd
FROM events
WHERE timestamp >= now() - INTERVAL 90 DAY
GROUP BY channel
ORDER BY rev_per_user_usd DESC
```
> **CAC (the spend side) lives outside PostHog** — your ad platforms know spend, PostHog knows value. Import ad spend into a warehouse table and join, or maintain CAC-per-channel in config and divide. This query gives you the *value* half (the LTV proxy); pair it with spend to get the ratio on the tile.

### 15. Top 10% power-user cost  *(watch by name)*
```sql
SELECT round(sumIf(cost, rn <= cnt * 0.1), 0)          AS top10pct_cost_usd,
       round(sum(cost), 0)                              AS total_cost_usd,
       round(100.0 * sumIf(cost, rn <= cnt * 0.1)
                   / nullIf(sum(cost), 0), 1)           AS pct_of_total_spend
FROM (
  SELECT person_id,
         sum(toFloat(properties.cost_usd))                                   AS cost,
         row_number() OVER (ORDER BY sum(toFloat(properties.cost_usd)) DESC) AS rn,
         count() OVER ()                                                     AS cnt
  FROM events
  WHERE event = 'generation_succeeded'
    AND timestamp >= now() - INTERVAL 30 DAY
  GROUP BY person_id
)
```
To name the actual whales (so you can look at who they are), run:
```sql
SELECT person_id,
       round(sum(toFloat(properties.cost_usd)), 2) AS cost_usd,
       count()                                      AS generations,
       any(person.properties.is_paying)            AS paying
FROM events
WHERE event = 'generation_succeeded'
  AND timestamp >= now() - INTERVAL 30 DAY
GROUP BY person_id
ORDER BY cost_usd DESC
LIMIT 20
```

---

## Wiring it together

Each query returns `{ columns, results }`. Map `results` rows straight into the tile components in `bet-monitor.html` — the sparkline arrays expect a flat list of numbers (e.g. the `week → value` column from a weekly query). For the weekly slope tiles, pull the value column into the `data-spark="…"` attribute; for the funnel, feed the single-row counts into the bar widths.

**Refresh cadence:** snapshots (kept-rate, funnel, activation) hourly is plenty. Slopes (retention-by-cohort, margin, North Star) daily. Don't over-poll the Query API — cache results server-side and let the dashboard read your cache.
