-- Check 13: person vs organisation
-- Rule: Medicare entity code and registry entity type must agree:
--       Medicare 'I' (individual)   = registry 1
--       Medicare 'O' (organisation) = registry 2
--       Missing on either side counts as a mismatch.
--       Deactivated registry records are excluded (their fields are empty;
--       decision 7).
-- Severity: high. An NPI can't change between person and organisation, so
--           any disagreement is a data error.
-- Expected: 0 (step 4, Q3). Kept so the report can state it was checked.
-- Output: work.chk_13_entity_mismatch, one row per failing NPI.

CREATE OR REPLACE TABLE `npi-reconciliation.work.chk_13_entity_mismatch` AS
SELECT
  m.npi,
  m.entity_code                 AS medicare_entity,
  n.entity_type_code            AS registry_entity,
  m.last_org_name,
  n.last_name                   AS registry_last_name,
  n.org_name                    AS registry_org_name,
  m.state,
  m.provider_type,
  m.services,
  m.allowed_usd
FROM `npi-reconciliation.work.medicare_providers_2015` AS m
JOIN `npi-reconciliation.work.nppes_slim` AS n
  USING (npi)
WHERE n.status != 'deactivated'
  AND NOT COALESCE(
        (m.entity_code = 'I' AND n.entity_type_code = 1)
     OR (m.entity_code = 'O' AND n.entity_type_code = 2),
        FALSE);

-- Show the result.
SELECT
  (SELECT COUNT(*) FROM `npi-reconciliation.work.nppes_slim` WHERE status != 'deactivated') AS npis_checked,
  COUNT(*) AS npis_failed
FROM `npi-reconciliation.work.chk_13_entity_mismatch`;
