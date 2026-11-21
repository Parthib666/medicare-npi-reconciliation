-- Check 12: billed Medicare in 2015, deactivated in the registry today
-- Rule: registry status is 'deactivated' (deactivation date set, and no
--       reactivation on or after it).
-- Groups, by deactivation date:
--   before_2015  deactivated before 1 Jan 2015, yet billed during 2015.   Severity: high
--   during_2015  deactivated during 2015. The billing data is a yearly
--                total, so it can't show whether the services came
--                before or after the deactivation.                        Severity: medium
--   after_2015   deactivated later: retirement, death, practice closed.   Severity: info
-- Reason codes are blank in npi_raw, so there's no split by cause.
-- Expected (from step 4): 13 / 751 / 34,253.
-- Output: work.chk_12_deactivated, one row per deactivated NPI.

CREATE OR REPLACE TABLE `npi-reconciliation.work.chk_12_deactivated` AS
SELECT
  m.npi,
  m.entity_code,
  m.last_org_name,
  m.first_name,
  m.state,
  m.provider_type,
  m.services,
  m.allowed_usd,
  n.npi_deactivation_date,
  n.replacement_npi,
  CASE
    WHEN n.npi_deactivation_date <  DATE '2015-01-01' THEN 'before_2015'
    WHEN n.npi_deactivation_date <= DATE '2015-12-31' THEN 'during_2015'
    ELSE 'after_2015'
  END AS deactivation_group
FROM `npi-reconciliation.work.medicare_providers_2015` AS m
JOIN `npi-reconciliation.work.nppes_slim` AS n
  USING (npi)
WHERE n.status = 'deactivated';

-- Show the result.
SELECT
  deactivation_group,
  COUNT(*)                       AS providers,
  ROUND(SUM(allowed_usd))        AS allowed_usd,
  MIN(npi_deactivation_date)     AS earliest,
  MAX(npi_deactivation_date)     AS latest
FROM `npi-reconciliation.work.chk_12_deactivated`
GROUP BY deactivation_group
ORDER BY earliest;
