-- ============================================================================
-- 03. Data-quality checks on the GA4 funnel events
-- ============================================================================
-- Purpose : explain why the closed funnel collapses before trusting any rate.
-- Findings:
--   1. add_shipping_info is logged BEFORE begin_checkout in 62% of sessions
--      -> shipping step dropped from the funnel.
--   2. 42% of users who began checkout have no add_to_cart event
--      -> cart step undercounted, excluded from conversion rates.
--   (Also see file 05: '(data deleted)' medium and self-referral traffic.)


-- ----------------------------------------------------------------------------
-- 3a. Session level: out-of-order events and skipped steps
-- ----------------------------------------------------------------------------
-- Query 2: Why does the closed funnel collapse?
WITH events AS (
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
SELECT
  -- Hypothesis 1: events logged out of order
  COUNTIF(t_checkout IS NOT NULL AND t_shipping IS NOT NULL) AS checkout_and_shipping,
  COUNTIF(t_shipping <  t_checkout)  AS shipping_before_checkout,
  COUNTIF(t_shipping =  t_checkout)  AS shipping_same_time,
  COUNTIF(t_cart     >  t_checkout)  AS cart_after_checkout,

  -- Hypothesis 2: buyers skipped earlier steps in this session
  COUNTIF(t_purchase IS NOT NULL)                     AS purchase_sessions,
  COUNTIF(t_purchase IS NOT NULL AND t_view IS NULL)  AS purchase_no_view,
  COUNTIF(t_purchase IS NOT NULL AND t_cart IS NULL)  AS purchase_no_cart,
  COUNTIF(t_purchase IS NOT NULL AND t_payment IS NULL) AS purchase_no_payment,
  COUNTIF(t_purchase < t_payment)                     AS purchase_before_payment
FROM firsts;

-- ----------------------------------------------------------------------------
-- 3b. User level: the cart -> checkout break
-- ----------------------------------------------------------------------------
-- Query 4: Diagnose the cart -> checkout break (user level)
WITH firsts AS (
  SELECT
    user_pseudo_id,
    MIN(IF(event_name = 'add_to_cart',    event_timestamp, NULL)) AS t_cart,
    MIN(IF(event_name = 'begin_checkout', event_timestamp, NULL)) AS t_checkout,
    MIN(IF(event_name = 'purchase',       event_timestamp, NULL)) AS t_purchase
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY user_pseudo_id
)
SELECT
  COUNTIF(t_checkout IS NOT NULL)                    AS checkout_users,
  COUNTIF(t_checkout IS NOT NULL AND t_cart IS NULL) AS checkout_never_carted,   -- cause (a)
  COUNTIF(t_cart > t_checkout)                       AS first_cart_after_checkout, -- cause (b)
  COUNTIF(t_purchase IS NOT NULL)                    AS buyers,
  COUNTIF(t_purchase IS NOT NULL AND t_cart IS NULL) AS buyers_never_carted
FROM firsts;
