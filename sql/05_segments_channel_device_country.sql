-- ============================================================================
-- 05. Segment analysis: device, traffic medium, country, source
-- ============================================================================
-- Purpose : test whether WHO we attract (marketing) or WHAT happens on site
--           explains conversion.
-- Finding : device, country and first-touch channel all convert at ~1.5-1.6%,
--           so the problem is the checkout experience, not marketing mix.
-- Note    : 5b/5c originally used ANY_VALUE() for medium/source. That is
--           non-deterministic and produced a misleading channel gap, so they
--           are shown here with first-touch ARRAY_AGG, as in file 04.


-- ----------------------------------------------------------------------------
-- 5a. Funnel + revenue by device, with an ALL row (ROLLUP)
-- ----------------------------------------------------------------------------
-- Query 5: User-level funnel + revenue by device, with total row
WITH users AS (
  SELECT
    user_pseudo_id,
    -- the device of the user's FIRST event (users can switch devices)
    ARRAY_AGG(device.category ORDER BY event_timestamp LIMIT 1)[OFFSET(0)] AS device,
    MAX(IF(event_name = 'view_item',        1, 0)) AS viewed,
    MAX(IF(event_name = 'begin_checkout',   1, 0)) AS checked_out,
    MAX(IF(event_name = 'add_payment_info', 1, 0)) AS paid_info,
    MAX(IF(event_name = 'purchase',         1, 0)) AS purchased,
    SUM(IF(event_name = 'purchase', ecommerce.purchase_revenue_in_usd, 0)) AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY user_pseudo_id
)
SELECT
  COALESCE(device, 'ALL')                                      AS device,
  COUNT(*)                                                     AS users,
  SUM(viewed)                                                  AS viewers,
  SUM(checked_out)                                             AS checkouts,
  SUM(paid_info)                                               AS payment_info,
  SUM(purchased)                                               AS buyers,
  ROUND(SUM(revenue), 0)                                       AS revenue_usd,
  ROUND(SAFE_DIVIDE(SUM(purchased),   COUNT(*))        * 100, 2) AS conversion_pct,
  ROUND(SAFE_DIVIDE(SUM(checked_out), SUM(viewed))     * 100, 1) AS view_to_checkout_pct,
  ROUND(SAFE_DIVIDE(SUM(paid_info),   SUM(checked_out))* 100, 1) AS checkout_to_payment_pct,
  ROUND(SAFE_DIVIDE(SUM(purchased),   SUM(paid_info))  * 100, 1) AS payment_to_purchase_pct,
  ROUND(SAFE_DIVIDE(SUM(revenue),     SUM(purchased)), 2)       AS revenue_per_buyer
FROM users
GROUP BY ROLLUP(device)
ORDER BY users DESC;

-- ----------------------------------------------------------------------------
-- 5b. Funnel by traffic medium and by country (countries with 3,000+ users)
-- ----------------------------------------------------------------------------
-- Query 6: Funnel by traffic medium and by country (top countries)
WITH users AS (
  SELECT
    user_pseudo_id,
    ARRAY_AGG(traffic_source.medium IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS medium,  -- first touch
    ARRAY_AGG(geo.country ORDER BY event_timestamp LIMIT 1)[OFFSET(0)] AS country,
    MAX(IF(event_name = 'view_item',        1, 0)) AS viewed,
    MAX(IF(event_name = 'begin_checkout',   1, 0)) AS checked_out,
    MAX(IF(event_name = 'add_payment_info', 1, 0)) AS paid_info,
    MAX(IF(event_name = 'purchase',         1, 0)) AS purchased,
    SUM(IF(event_name = 'purchase', ecommerce.purchase_revenue_in_usd, 0)) AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY user_pseudo_id
)
SELECT
  'medium' AS dimension, medium AS segment,
  COUNT(*) AS users, SUM(purchased) AS buyers,
  ROUND(SAFE_DIVIDE(SUM(purchased),   COUNT(*))         * 100, 2) AS conversion_pct,
  ROUND(SAFE_DIVIDE(SUM(checked_out), SUM(viewed))      * 100, 1) AS view_to_checkout_pct,
  ROUND(SAFE_DIVIDE(SUM(paid_info),   SUM(checked_out)) * 100, 1) AS checkout_to_payment_pct,
  ROUND(SAFE_DIVIDE(SUM(revenue),     SUM(purchased)), 2)         AS revenue_per_buyer
FROM users
GROUP BY medium

UNION ALL

SELECT
  'country', country,
  COUNT(*), SUM(purchased),
  ROUND(SAFE_DIVIDE(SUM(purchased),   COUNT(*))         * 100, 2),
  ROUND(SAFE_DIVIDE(SUM(checked_out), SUM(viewed))      * 100, 1),
  ROUND(SAFE_DIVIDE(SUM(paid_info),   SUM(checked_out)) * 100, 1),
  ROUND(SAFE_DIVIDE(SUM(revenue),     SUM(purchased)), 2)
FROM users
GROUP BY country
HAVING COUNT(*) >= 3000      -- only countries big enough to trust

ORDER BY dimension, users DESC;

-- ----------------------------------------------------------------------------
-- 5c. Source drill-down: referral, paid search and '(data deleted)'
-- ----------------------------------------------------------------------------
-- Query 7: Source-level drill-down for key mediums
WITH users AS (
  SELECT
    user_pseudo_id,
    ARRAY_AGG(traffic_source.medium IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS medium,
    ARRAY_AGG(traffic_source.source IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS source,
    MAX(IF(event_name = 'purchase', 1, 0)) AS purchased,
    SUM(IF(event_name = 'purchase', ecommerce.purchase_revenue_in_usd, 0)) AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY user_pseudo_id
)
SELECT
  medium,
  source,
  COUNT(*)                                              AS users,
  SUM(purchased)                                        AS buyers,
  ROUND(SAFE_DIVIDE(SUM(purchased), COUNT(*)) * 100, 2) AS conversion_pct,
  ROUND(SUM(revenue), 0)                                AS revenue_usd,
  ROUND(SUM(purchased) / SUM(SUM(purchased)) OVER (PARTITION BY medium) * 100, 1)
                                                        AS share_of_medium_buyers_pct
FROM users
WHERE medium IN ('referral', 'cpc', '(data deleted)')
GROUP BY medium, source
HAVING COUNT(*) >= 300
ORDER BY medium, users DESC;
