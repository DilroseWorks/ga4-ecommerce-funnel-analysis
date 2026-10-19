-- ============================================================================
-- 08. Weekly KPI table: ga4_funnel.weekly_metrics
-- ============================================================================
-- Purpose : session-level weekly metrics that feed the AI weekly briefing.
--           SQL computes every number; the LLM only writes prose about them.
-- Method  : weeks start Monday; partial weeks at the edges are dropped
--           (days_in_week = 7).
-- Findings: conversion peaks at 1.99% (week of 7 Dec) and bottoms at 0.56%
--           (week of 4 Jan); week of 25 Jan shows revenue per order of $17.78
--           vs a typical ~$74, a likely revenue-tracking gap.

-- Step 1: Weekly session-level metrics (complete weeks only)
CREATE OR REPLACE TABLE `ga4_funnel.weekly_metrics` AS
WITH ev AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date)                                  AS d,
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY))        AS week_start,
    user_pseudo_id,
    CONCAT(user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING))                  AS session_id,
    event_name,
    ecommerce.purchase_revenue_in_usd                                 AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
sess AS (                                   -- one row per session
  SELECT
    week_start,
    session_id,
    ANY_VALUE(user_pseudo_id)                        AS user_pseudo_id,
    MAX(IF(event_name = 'view_item',        1, 0))   AS viewed,
    MAX(IF(event_name = 'begin_checkout',   1, 0))   AS checked_out,
    MAX(IF(event_name = 'add_payment_info', 1, 0))   AS paid_info,
    MAX(IF(event_name = 'purchase',         1, 0))   AS purchased,
    IFNULL(SUM(IF(event_name = 'purchase', revenue, NULL)), 0) AS revenue
  FROM ev
  WHERE session_id IS NOT NULL
  GROUP BY week_start, session_id
),
days AS (                                   -- how many days each week contains
  SELECT week_start, COUNT(DISTINCT d) AS days_in_week
  FROM ev
  GROUP BY week_start
),
w AS (                                      -- one row per week
  SELECT
    week_start,
    COUNT(*)                        AS sessions,
    COUNT(DISTINCT user_pseudo_id)  AS users,
    SUM(viewed)                     AS view_sessions,
    SUM(checked_out)                AS checkout_sessions,
    SUM(paid_info)                  AS payment_sessions,
    SUM(purchased)                  AS purchase_sessions,
    ROUND(SUM(revenue), 0)          AS revenue
  FROM sess
  GROUP BY week_start
)
SELECT
  w.*,
  ROUND(SAFE_DIVIDE(purchase_sessions, sessions)          * 100, 2) AS conv_rate_pct,
  ROUND(SAFE_DIVIDE(view_sessions, sessions)              * 100, 1) AS view_rate_pct,
  ROUND(SAFE_DIVIDE(checkout_sessions, view_sessions)     * 100, 1) AS view_to_checkout_pct,
  ROUND(SAFE_DIVIDE(payment_sessions, checkout_sessions)  * 100, 1) AS checkout_to_payment_pct,
  ROUND(SAFE_DIVIDE(purchase_sessions, payment_sessions)  * 100, 1) AS payment_to_purchase_pct,
  ROUND(SAFE_DIVIDE(revenue, purchase_sessions), 2)                 AS revenue_per_order
FROM w
JOIN days USING (week_start)
WHERE days.days_in_week = 7
ORDER BY week_start;

-- ----------------------------------------------------------------------------
-- Check
-- ----------------------------------------------------------------------------
SELECT * FROM `ga4_funnel.weekly_metrics` ORDER BY week_start;
