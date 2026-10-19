-- ============================================================================
-- 01. Event inventory
-- ============================================================================
-- Purpose : list every GA4 event with its volume, to decide which events can
--           form a funnel and to spot broken tracking early.
-- Source  : GA4 public sample, 1 Nov 2020 - 31 Jan 2021.
-- Finding : view_item_list has only 71 events (broken), so it is not used.

SELECT event_name,
       COUNT(*) AS events,
       COUNT(DISTINCT user_pseudo_id) AS users
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
GROUP BY event_name
ORDER BY events DESC;
