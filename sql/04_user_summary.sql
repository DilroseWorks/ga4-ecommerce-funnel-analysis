-- ============================================================================
-- 04. Clean user-level table: ga4_funnel.user_summary
-- ============================================================================
-- Purpose : one row per user for the dashboard and for modelling.
-- Method  : first-touch device/country/medium/source via
--           ARRAY_AGG(... IGNORE NULLS ORDER BY event_timestamp LIMIT 1).
--           (ANY_VALUE is NOT used: it returns an arbitrary row, which earlier
--           produced a false 'paid search converts at half the rate' result.)
-- Channel : tracking artifacts kept separate ('Data deleted', 'Self-referral').
-- Run once before files 05-07.

CREATE SCHEMA IF NOT EXISTS `ga4_funnel` OPTIONS (location = 'US');

-- Query 8: Clean user-level table for dashboard + modelling
CREATE OR REPLACE TABLE `ga4_funnel.user_summary` AS
WITH ev AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    event_name,
    device.category        AS device,
    geo.country            AS country,
    traffic_source.medium  AS medium,
    traffic_source.source  AS source,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    ecommerce.purchase_revenue_in_usd AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
u AS (
  SELECT
    user_pseudo_id,
    DATE(TIMESTAMP_MICROS(MIN(event_timestamp))) AS first_seen_date,
    -- first non-null value per user (repeatable, unlike ANY_VALUE)
    ARRAY_AGG(device  IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS device,
    ARRAY_AGG(country IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS country,
    ARRAY_AGG(medium  IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS medium,
    ARRAY_AGG(source  IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS source,
    COUNT(DISTINCT session_id)          AS sessions,
    COUNTIF(event_name = 'page_view')   AS page_views,
    COUNTIF(event_name = 'view_item')   AS item_views,
    MAX(IF(event_name = 'view_item',        1, 0)) AS viewed,
    MAX(IF(event_name = 'begin_checkout',   1, 0)) AS checked_out,
    MAX(IF(event_name = 'add_payment_info', 1, 0)) AS paid_info,
    MAX(IF(event_name = 'purchase',         1, 0)) AS purchased,
    COUNTIF(event_name = 'purchase')    AS purchases,
    IFNULL(SUM(IF(event_name = 'purchase', revenue, NULL)), 0) AS revenue_usd
  FROM ev
  GROUP BY user_pseudo_id
)
SELECT
  *,
  CASE
    WHEN medium = '(data deleted)' THEN 'Data deleted'
    WHEN medium = 'referral' AND source = 'shop.googlemerchandisestore.com' THEN 'Self-referral'
    WHEN medium = 'referral' THEN 'Referral'
    WHEN medium = 'organic'  THEN 'Organic search'
    WHEN medium = 'cpc'      THEN 'Paid search'
    WHEN medium = '(none)'   THEN 'Direct'
    ELSE 'Other'
  END AS channel
FROM u;

-- ----------------------------------------------------------------------------
-- Check: users, buyers and revenue by channel, with a total row
-- ----------------------------------------------------------------------------
SELECT channel, COUNT(*) AS users, SUM(purchased) AS buyers,
       ROUND(SUM(revenue_usd), 0) AS revenue_usd
FROM `ga4_funnel.user_summary`
GROUP BY ROLLUP(channel)
ORDER BY users DESC;
