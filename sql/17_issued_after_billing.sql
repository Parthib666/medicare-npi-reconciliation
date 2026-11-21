-- Check 17: billed before the ID existed
-- Rule: the registry says the NPI was issued (enumerated) after 31 Dec 2015,
--       but it appears in the 2015 Medicare billing data.
-- Severity: high until explained. Possible explanations: an error in either
--           source, or a record re-issued with a new enumeration date.
-- Expected: 2 NPIs (step 4, Q2). Look both up by hand on the public NPI
--           registry search (npiregistry.cms.hhs.gov) and note what you find
--           in the README.
-- Output: work.chk_17_issued_after_billing, one row per failing NPI.

CREATE OR REPLACE TABLE `npi-reconciliation.work.chk_17_issued_after_billing` AS
SELECT
  m.npi,
  m.entity_code,
  m.last_org_name,
  m.first_name,
  m.state,
  m.provider_type,
  m.services,
  m.allowed_usd,
  n.provider_enumeration_date,
  n.last_update_date,
  n.status,
  n.last_name                    AS registry_last_name,
  n.org_name                     AS registry_org_name,
  n.state                        AS registry_state,
  n.taxonomy_classification
FROM `npi-reconciliation.work.medicare_providers_2015` AS m
JOIN `npi-reconciliation.work.nppes_slim` AS n
  USING (npi)
WHERE n.provider_enumeration_date > DATE '2015-12-31';

-- Show the result.
SELECT * FROM `npi-reconciliation.work.chk_17_issued_after_billing`
ORDER BY provider_enumeration_date;
