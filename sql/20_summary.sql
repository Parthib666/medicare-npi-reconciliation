-- Step 6: one summary table of every check.
-- Run after 10-17. Reads only the small work tables.
-- Output: work.dq_summary, one row per check (or per sub-group of a check):
--   check_id, check_name, severity, what_it_means,
--   providers_checked, providers_failed, pct_failed,
--   allowed_usd_affected, pct_of_total_allowed
-- providers_checked is the number of providers each check could actually
-- test (e.g. field comparisons exclude deactivated records), so pct_failed
-- is fair for every row.

CREATE OR REPLACE TABLE `npi-reconciliation.work.dq_summary` AS
WITH
m AS (SELECT * FROM `npi-reconciliation.work.medicare_providers_2015`),
n AS (SELECT * FROM `npi-reconciliation.work.nppes_slim`),
total AS (SELECT SUM(allowed_usd) AS allowed FROM m),

-- Denominators
d_all       AS (SELECT COUNT(*) AS c FROM m),
d_matched   AS (SELECT COUNT(*) AS c FROM n),
d_compared  AS (SELECT COUNT(*) AS c FROM n WHERE status != 'deactivated'),
d_location  AS (SELECT COUNT(*) AS c
                FROM `npi-reconciliation.work.chk_14_location`
                WHERE location_result != 'not_compared'),
d_names     AS (SELECT COUNT(*) AS c
                FROM m JOIN n USING (npi)
                WHERE n.status != 'deactivated'
                  AND m.last_org_name IS NOT NULL
                  AND IF(m.entity_code = 'O', n.org_name, n.last_name) IS NOT NULL),
d_specialty AS (
  -- Same rule as check 16: labelled specialty, provider types with 100+ providers.
  SELECT COUNT(*) AS c
  FROM (
    SELECT m.provider_type, COUNT(*) OVER (PARTITION BY m.provider_type) AS type_providers
    FROM m JOIN n USING (npi)
    WHERE n.status != 'deactivated' AND n.taxonomy_classification IS NOT NULL
  )
  WHERE type_providers >= 100
),
d_enumerated AS (SELECT COUNT(*) AS c FROM n WHERE provider_enumeration_date IS NOT NULL),

rows_ AS (
  SELECT '10' AS check_id, 'ID not in registry' AS check_name, 'high' AS severity,
         'Billed Medicare under an NPI the registry has no record of' AS what_it_means,
         (SELECT c FROM d_all) AS providers_checked,
         COUNT(*) AS providers_failed, SUM(allowed_usd) AS allowed_usd_affected
  FROM `npi-reconciliation.work.chk_10_not_in_registry`

  UNION ALL
  SELECT '11', 'Invalid NPI (check digit)', 'high',
         'NPI fails the official check-digit formula, so it cannot be a real ID',
         (SELECT c FROM d_all), COUNT(*), SUM(allowed_usd)
  FROM `npi-reconciliation.work.chk_11_invalid_check_digit`

  UNION ALL
  SELECT '12a', 'Deactivated before 2015', 'high',
         'NPI was deactivated years before it billed Medicare in 2015',
         (SELECT c FROM d_matched), COUNT(*), SUM(allowed_usd)
  FROM `npi-reconciliation.work.chk_12_deactivated`
  WHERE deactivation_group = 'before_2015'

  UNION ALL
  SELECT '12b', 'Deactivated during 2015', 'medium',
         'Deactivated in the billing year; yearly data cannot show which came first',
         (SELECT c FROM d_matched), COUNT(*), SUM(allowed_usd)
  FROM `npi-reconciliation.work.chk_12_deactivated`
  WHERE deactivation_group = 'during_2015'

  UNION ALL
  SELECT '12c', 'Deactivated after 2015', 'info',
         'Normal churn since 2015: retirement, death, practice closed',
         (SELECT c FROM d_matched), COUNT(*), SUM(allowed_usd)
  FROM `npi-reconciliation.work.chk_12_deactivated`
  WHERE deactivation_group = 'after_2015'

  UNION ALL
  SELECT '13', 'Person vs organisation', 'high',
         'Medicare and the registry disagree on whether the NPI is a person or an organisation',
         (SELECT c FROM d_compared), COUNT(*), SUM(allowed_usd)
  FROM `npi-reconciliation.work.chk_13_entity_mismatch`

  UNION ALL
  SELECT '14a', 'Different state', 'info',
         'Practice state differs after cleaning; mostly providers who moved since 2015',
         (SELECT c FROM d_location), COUNT(*), SUM(allowed_usd)
  FROM `npi-reconciliation.work.chk_14_location`
  WHERE location_result = 'state_mismatch'

  UNION ALL
  SELECT '14b', 'Same state, different ZIP', 'info',
         'Practice ZIP differs within the same state; mostly moves within the state',
         (SELECT c FROM d_location), COUNT(*), SUM(allowed_usd)
  FROM `npi-reconciliation.work.chk_14_location`
  WHERE location_result = 'zip_mismatch'

  UNION ALL
  SELECT '15', 'Different name', 'info',
         'Legal name differs after cleaning; marriage, or organisation renamed or acquired',
         (SELECT c FROM d_names), COUNT(*), SUM(allowed_usd)
  FROM `npi-reconciliation.work.chk_15_name_mismatch`

  UNION ALL
  SELECT '16', 'Unusual specialty', 'medium',
         'Registry specialty is held by under 1% of providers of the same Medicare type',
         (SELECT c FROM d_specialty), COUNT(*), SUM(allowed_usd)
  FROM `npi-reconciliation.work.chk_16_specialty_mismatch`

  UNION ALL
  SELECT '17', 'Billed before ID was issued', 'high',
         'Registry issue date is after 2015, but the NPI billed Medicare in 2015',
         (SELECT c FROM d_enumerated), COUNT(*), SUM(allowed_usd)
  FROM `npi-reconciliation.work.chk_17_issued_after_billing`
)
SELECT
  check_id,
  check_name,
  severity,
  what_it_means,
  providers_checked,
  providers_failed,
  ROUND(SAFE_DIVIDE(providers_failed, providers_checked) * 100, 3)        AS pct_failed,
  ROUND(COALESCE(allowed_usd_affected, 0))                               AS allowed_usd_affected,
  ROUND(SAFE_DIVIDE(COALESCE(allowed_usd_affected, 0),
                    (SELECT allowed FROM total)) * 100, 3)                AS pct_of_total_allowed
FROM rows_;

-- Show the result, most serious first.
SELECT *
FROM `npi-reconciliation.work.dq_summary`
ORDER BY
  CASE severity WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,
  check_id;
