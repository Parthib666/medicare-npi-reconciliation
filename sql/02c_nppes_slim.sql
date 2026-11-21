-- Step 3d: add readable specialty names to the registry table.
-- Run after 02b. Reads only small tables (work.nppes_base and an 853-row lookup).
--
-- Lookup choice (from 02a, 2026-11-21): the unversioned
-- healthcare_provider_taxonomy_code_set has the most codes (853, last modified
-- 2020-03-25). The dated copies _090 to _170 are older (809 to 851 codes, 2017).
-- npi_raw is from 2026, so codes created after 2020 will have no name;
-- 02d counts them.
--
-- LEFT JOIN so a provider whose code has no name is kept, not dropped.
-- `grouping` is a reserved word in BigQuery, so it needs backticks.

CREATE OR REPLACE TABLE `npi-reconciliation.work.nppes_slim` AS
WITH taxonomy_names AS (
  SELECT
    TRIM(code)                         AS code,
    NULLIF(TRIM(`grouping`), '')       AS taxonomy_grouping,
    NULLIF(TRIM(classification), '')   AS taxonomy_classification,
    NULLIF(TRIM(specialization), '')   AS taxonomy_specialization
  FROM `bigquery-public-data.nppes.healthcare_provider_taxonomy_code_set`
  WHERE NULLIF(TRIM(code), '') IS NOT NULL
  -- Guard against duplicate codes, so the join can't create extra rows.
  QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(code) ORDER BY classification) = 1
)
SELECT
  b.*,
  l.taxonomy_grouping,
  l.taxonomy_classification,
  l.taxonomy_specialization
FROM `npi-reconciliation.work.nppes_base` AS b
LEFT JOIN taxonomy_names AS l
  ON b.primary_taxonomy = l.code;
