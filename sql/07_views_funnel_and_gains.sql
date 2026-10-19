-- ============================================================================
-- 07. Dashboard views: funnel rows and model gains table
-- ============================================================================
-- Purpose : shape data for Looker Studio.
--   - v_funnel : funnel steps as rows (UNPIVOT) with step-to-step (LAG) and
--                share-of-total (FIRST_VALUE) rates.
--   - v_gains  : buyers captured per score decile with a running total.
-- Depends on: ga4_funnel.propensity_scores, written from the modelling
--             notebook (out-of-fold scores; decile 1 = highest propensity).
-- Finding : top 2 deciles hold ~80% of later buyers; bottom 50% hold 4.5%.

-- Query 10a: Funnel as rows, with step-to-step rates
CREATE OR REPLACE VIEW `ga4_funnel.v_funnel` AS
SELECT
  CAST(SUBSTR(step, 2, 1) AS INT64)           AS step_order,
  REGEXP_REPLACE(step, r'^s\d_', '')          AS step,
  users,
  ROUND(SAFE_DIVIDE(users, LAG(users)         OVER (ORDER BY step)) * 100, 1) AS pct_of_previous,
  ROUND(SAFE_DIVIDE(users, FIRST_VALUE(users) OVER (ORDER BY step)) * 100, 2) AS pct_of_total
FROM (
  SELECT
    COUNT(*)         AS s1_users,
    SUM(viewed)      AS s2_view_item,
    SUM(checked_out) AS s3_begin_checkout,
    SUM(paid_info)   AS s4_add_payment,
    SUM(purchased)   AS s5_purchase
  FROM `ga4_funnel.user_summary`
)
UNPIVOT (users FOR step IN (s1_users, s2_view_item, s3_begin_checkout, s4_add_payment, s5_purchase));

-- Query 10b: Gains table with cumulative capture
CREATE OR REPLACE VIEW `ga4_funnel.v_gains` AS
SELECT
  decile,
  COUNT(*)                               AS users,
  SUM(purchased_later)                   AS later_buyers,
  ROUND(AVG(purchased_later) * 100, 2)   AS buy_rate_pct,
  ROUND(SUM(SUM(purchased_later)) OVER (ORDER BY decile)
        / SUM(SUM(purchased_later)) OVER () * 100, 1) AS cum_capture_pct
FROM `ga4_funnel.propensity_scores`
GROUP BY decile;

-- ----------------------------------------------------------------------------
-- Check: buy rate by decile
-- ----------------------------------------------------------------------------
SELECT decile, COUNT(*) AS users, SUM(purchased_later) AS later_buyers,
       ROUND(AVG(purchased_later) * 100, 2) AS buy_rate_pct
FROM `ga4_funnel.propensity_scores`
GROUP BY decile
ORDER BY decile;
