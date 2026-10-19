-- ============================================================================
-- 06. Modelling table: ga4_funnel.model_first_session
-- ============================================================================
-- Purpose : features from each user's FIRST session only, and a target of
--           'purchased in a LATER session' (purchased_later).
-- Leakage guards:
--   - nothing after the first session is used as a feature;
--   - users who bought in their first session are excluded;
--   - users first seen after 2020-12-31 are excluded (time to come back).
-- Depends on: ga4_funnel.user_summary (file 04) for the channel column.
-- Positive rate ~1.1%, which is the PR-AUC baseline for the model.

-- Query 9: First-session features -> did they buy later?
CREATE OR REPLACE TABLE `ga4_funnel.model_first_session` AS
WITH ev AS (
  SELECT
    user_pseudo_id, event_timestamp, event_name,
    device.category          AS device,
    device.operating_system  AS os,
    geo.country              AS country,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')        AS session_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_msec
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
first_sess AS (            -- each user's first session ID
  SELECT
    user_pseudo_id,
    ARRAY_AGG(session_id IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS first_session_id
  FROM ev
  GROUP BY user_pseudo_id
),
features AS (              -- behaviour inside the first session only
  SELECT
    e.user_pseudo_id,
    DATE(TIMESTAMP_MICROS(MIN(e.event_timestamp)))                AS first_date,
    EXTRACT(HOUR      FROM TIMESTAMP_MICROS(MIN(e.event_timestamp))) AS fs_hour,
    EXTRACT(DAYOFWEEK FROM TIMESTAMP_MICROS(MIN(e.event_timestamp))) AS fs_dow,
    ARRAY_AGG(e.device  IGNORE NULLS ORDER BY e.event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS device,
    ARRAY_AGG(e.os      IGNORE NULLS ORDER BY e.event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS os,
    ARRAY_AGG(e.country IGNORE NULLS ORDER BY e.event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS country,
    COUNTIF(e.event_name = 'page_view')            AS fs_page_views,
    COUNTIF(e.event_name = 'view_item')            AS fs_item_views,
    COUNTIF(e.event_name = 'add_to_cart')          AS fs_add_to_cart,
    COUNTIF(e.event_name = 'view_search_results')  AS fs_searches,
    COUNTIF(e.event_name = 'view_promotion')       AS fs_promo_views,
    COUNTIF(e.event_name = 'scroll')               AS fs_scrolls,
    MAX(IF(e.event_name = 'begin_checkout', 1, 0)) AS fs_began_checkout,
    ROUND(IFNULL(SUM(e.engagement_msec), 0) / 1000, 1) AS fs_engaged_seconds,
    MAX(IF(e.event_name = 'purchase', 1, 0))       AS fs_purchased
  FROM ev e
  JOIN first_sess f
    ON e.user_pseudo_id = f.user_pseudo_id
   AND e.session_id     = f.first_session_id
  GROUP BY e.user_pseudo_id
),
later AS (                 -- target: any purchase AFTER the first session
  SELECT
    e.user_pseudo_id,
    MAX(IF(e.event_name = 'purchase', 1, 0)) AS purchased_later
  FROM ev e
  JOIN first_sess f ON e.user_pseudo_id = f.user_pseudo_id
  WHERE e.session_id != f.first_session_id
  GROUP BY e.user_pseudo_id
)
SELECT
  fe.* EXCEPT (fs_purchased),
  s.channel,
  IFNULL(l.purchased_later, 0) AS purchased_later
FROM features fe
LEFT JOIN later l                         USING (user_pseudo_id)
LEFT JOIN `ga4_funnel.user_summary` s     USING (user_pseudo_id)
WHERE fe.fs_purchased = 0                 -- not already a buyer
  AND fe.first_date <= '2020-12-31';      -- enough time to come back

-- ----------------------------------------------------------------------------
-- Check: size and positive rate
-- ----------------------------------------------------------------------------
SELECT
  COUNT(*)                         AS users,
  SUM(purchased_later)             AS later_buyers,
  ROUND(AVG(purchased_later)*100, 2) AS positive_rate_pct
FROM `ga4_funnel.model_first_session`;
