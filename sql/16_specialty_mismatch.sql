-- Check 16: unusual specialty for the provider type
-- Medicare's provider_type ("Cardiology", "Nurse Practitioner") and the
-- registry's taxonomy ("Internal Medicine / Cardiovascular Disease") use
-- different vocabularies, so they can't be compared directly.
--
-- Rule (data-driven, no hand-built mapping):
--   For each Medicare provider type, see which registry specialty
--   (taxonomy classification) its providers have. Flag a provider whose
--   classification is held by fewer than 1% of providers of the same type.
--   Example: if 98% of "Nurse Practitioner" providers are classified
--   "Nurse Practitioner" in the registry, one classified "Chiropractor"
--   gets flagged.
-- Only provider types with at least 100 comparable providers are used, so
-- the percentages are meaningful.
-- Excluded: deactivated records (decision 7) and the 502 codes with no name.
-- Severity: medium. It's a signal that the specialty changed or one source
--           is wrong; it's not proof either way.
-- The 1% and 100 thresholds are judgement calls; change them here if needed.
-- Output: work.chk_16_specialty_mismatch, one row per flagged NPI.

CREATE OR REPLACE TABLE `npi-reconciliation.work.chk_16_specialty_mismatch` AS
WITH pairs AS (
  SELECT
    m.npi,
    m.entity_code,
    m.last_org_name,
    m.first_name,
    m.state,
    m.provider_type,
    m.services,
    m.allowed_usd,
    n.primary_taxonomy,
    n.taxonomy_classification,
    n.taxonomy_specialization
  FROM `npi-reconciliation.work.medicare_providers_2015` AS m
  JOIN `npi-reconciliation.work.nppes_slim` AS n
    USING (npi)
  WHERE n.status != 'deactivated'
    AND n.taxonomy_classification IS NOT NULL
),
shares AS (
  SELECT
    provider_type,
    taxonomy_classification,
    COUNT(*)                                                     AS pair_providers,
    SUM(COUNT(*)) OVER (PARTITION BY provider_type)              AS type_providers,
    COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY provider_type)   AS pair_share
  FROM pairs
  GROUP BY provider_type, taxonomy_classification
),
usual AS (
  SELECT
    provider_type,
    taxonomy_classification AS usual_classification,
    pair_share              AS usual_share
  FROM shares
  WHERE TRUE   -- older BigQuery versions require a WHERE before QUALIFY
  QUALIFY ROW_NUMBER() OVER (PARTITION BY provider_type ORDER BY pair_providers DESC) = 1
)
SELECT
  p.*,
  s.pair_share,
  s.type_providers,
  u.usual_classification,
  u.usual_share
FROM pairs AS p
JOIN shares AS s USING (provider_type, taxonomy_classification)
JOIN usual  AS u USING (provider_type)
WHERE s.type_providers >= 100
  AND s.pair_share < 0.01;

-- Show the result: provider types with the most flags.
SELECT
  provider_type,
  usual_classification,
  ROUND(usual_share * 100, 1)   AS usual_pct,
  COUNT(*)                      AS flagged,
  ANY_VALUE(type_providers)     AS type_providers,
  ROUND(SUM(allowed_usd))       AS allowed_usd
FROM `npi-reconciliation.work.chk_16_specialty_mismatch`
GROUP BY provider_type, usual_classification, usual_share
ORDER BY flagged DESC
LIMIT 25;
