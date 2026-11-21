-- Check 10: ID not in registry
-- Rule: an NPI that billed Medicare in 2015 has no record at all in the
--       March 2026 NPI registry.
-- Severity: high. Every NPI ever issued should stay in the registry, even
--           after deactivation, so a missing one is a real data problem.
-- Expected: 2 NPIs (from step 3 validation).
-- Output: work.chk_10_not_in_registry, one row per failing NPI.

CREATE OR REPLACE TABLE `npi-reconciliation.work.chk_10_not_in_registry` AS
SELECT
  m.npi,
  m.entity_code,
  m.last_org_name,
  m.first_name,
  m.state,
  m.zip5,
  m.provider_type,
  m.services,
  m.allowed_usd
FROM `npi-reconciliation.work.medicare_providers_2015` AS m
LEFT JOIN `npi-reconciliation.work.nppes_slim` AS n
  USING (npi)
WHERE n.npi IS NULL;

-- Show the result (run the whole file; this is the last result shown).
SELECT * FROM `npi-reconciliation.work.chk_10_not_in_registry`
ORDER BY allowed_usd DESC;
