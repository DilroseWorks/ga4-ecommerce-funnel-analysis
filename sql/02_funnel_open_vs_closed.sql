-- ============================================================================
-- 02. Funnel: open vs closed, session and user level
-- ============================================================================
-- Purpose : count how many sessions/users reach each purchase step.
--   - Open funnel   : the step happened at all.
--   - Closed funnel : steps happened in order (timestamps compared).
-- Method  : MIN(IF(...)) gives the first time of each step; COUNTIF(t_a <= t_b)
--           checks order (NULL comparisons are skipped by COUNTIF).
-- Finding : the closed funnel collapses, which led to the checks in file 03.
-- Locked funnel (user level, open): users -> view_item 22.7% -> begin_checkout
--           15.9% -> add_payment_info 59.2% -> purchase 76.8%.


-- ----------------------------------------------------------------------------
-- 2a. Session level (6 steps)
-- ----------------------------------------------------------------------------
-- Query 1: Session-level funnel, open vs closed
WITH events AS (
  -- Step A: one row per event, labelled with its session ID
  SELECT
    CONCAT(user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING)) AS session_id,
    event_name,
    event_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),

firsts AS (
  -- Step B: one row per session, with the FIRST time each step happened
  SELECT
    session_id,
    MIN(IF(event_name = 'view_item',         event_timestamp, NULL)) AS t_view,
    MIN(IF(event_name = 'add_to_cart',       event_timestamp, NULL)) AS t_cart,
    MIN(IF(event_name = 'begin_checkout',    event_timestamp, NULL)) AS t_checkout,
    MIN(IF(event_name = 'add_shipping_info', event_timestamp, NULL)) AS t_shipping,
    MIN(IF(event_name = 'add_payment_info',  event_timestamp, NULL)) AS t_payment,
    MIN(IF(event_name = 'purchase',          event_timestamp, NULL)) AS t_purchase
  FROM events
  WHERE session_id IS NOT NULL
  GROUP BY session_id
)

-- Step C: count sessions at each step, both ways
SELECT
  'open' AS funnel_type,
  COUNT(*)                          AS sessions,
  COUNTIF(t_view     IS NOT NULL)   AS view_item,
  COUNTIF(t_cart     IS NOT NULL)   AS add_to_cart,
  COUNTIF(t_checkout IS NOT NULL)   AS begin_checkout,
  COUNTIF(t_shipping IS NOT NULL)   AS add_shipping,
  COUNTIF(t_payment  IS NOT NULL)   AS add_payment,
  COUNTIF(t_purchase IS NOT NULL)   AS purchase
FROM firsts

UNION ALL

SELECT
  'closed',
  COUNT(*),
  COUNTIF(t_view IS NOT NULL),
  COUNTIF(t_view <= t_cart),
  COUNTIF(t_view <= t_cart AND t_cart <= t_checkout),
  COUNTIF(t_view <= t_cart AND t_cart <= t_checkout AND t_checkout <= t_shipping),
  COUNTIF(t_view <= t_cart AND t_cart <= t_checkout AND t_checkout <= t_shipping
          AND t_shipping <= t_payment),
  COUNTIF(t_view <= t_cart AND t_cart <= t_checkout AND t_checkout <= t_shipping
          AND t_shipping <= t_payment AND t_payment <= t_purchase)
FROM firsts;

-- ----------------------------------------------------------------------------
-- 2b. User level (5 steps, shipping step dropped; see file 03)
-- ----------------------------------------------------------------------------
-- Query 3: User-level funnel (5 steps), open vs closed
WITH firsts AS (
  -- One row per user, with the FIRST time they ever did each step
  SELECT
    user_pseudo_id,
    MIN(IF(event_name = 'view_item',        event_timestamp, NULL)) AS t_view,
    MIN(IF(event_name = 'add_to_cart',      event_timestamp, NULL)) AS t_cart,
    MIN(IF(event_name = 'begin_checkout',   event_timestamp, NULL)) AS t_checkout,
    MIN(IF(event_name = 'add_payment_info', event_timestamp, NULL)) AS t_payment,
    MIN(IF(event_name = 'purchase',         event_timestamp, NULL)) AS t_purchase
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY user_pseudo_id
)
SELECT
  'open' AS funnel_type,
  COUNT(*)                         AS users,
  COUNTIF(t_view     IS NOT NULL)  AS view_item,
  COUNTIF(t_cart     IS NOT NULL)  AS add_to_cart,
  COUNTIF(t_checkout IS NOT NULL)  AS begin_checkout,
  COUNTIF(t_payment  IS NOT NULL)  AS add_payment,
  COUNTIF(t_purchase IS NOT NULL)  AS purchase
FROM firsts

UNION ALL

SELECT
  'closed',
  COUNT(*),
  COUNTIF(t_view IS NOT NULL),
  COUNTIF(t_view <= t_cart),
  COUNTIF(t_view <= t_cart AND t_cart <= t_checkout),
  COUNTIF(t_view <= t_cart AND t_cart <= t_checkout AND t_checkout <= t_payment),
  COUNTIF(t_view <= t_cart AND t_cart <= t_checkout AND t_checkout <= t_payment
          AND t_payment <= t_purchase)
FROM firsts;
