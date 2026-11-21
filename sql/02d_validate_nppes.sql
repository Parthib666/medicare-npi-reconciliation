-- Step 3f: confirm work.nppes_slim is what we expect. Run after 02c.
-- Reads only small tables.

SELECT
  (SELECT COUNT(*) FROM `npi-reconciliation.work.medicare_providers_2015`) AS medicare_npis,
  (SELECT COUNT(*) FROM `npi-reconciliation.work.nppes_base`)              AS base_rows,       -- must equal registry_rows
  COUNT(*)                                          AS registry_rows,
  COUNT(DISTINCT npi)                               AS registry_unique_npis,   -- must equal registry_rows
  COUNTIF(status = 'active')                        AS active,
  COUNTIF(status = 'deactivated')                   AS deactivated,
  COUNTIF(status = 'reactivated')                   AS reactivated,
  COUNTIF(primary_taxonomy_source = 'switch')       AS taxonomy_from_switch,
  COUNTIF(primary_taxonomy_source = 'fallback')     AS taxonomy_from_fallback,
  COUNTIF(status != 'deactivated' AND primary_taxonomy IS NULL)  AS active_taxonomy_missing,
  COUNTIF(primary_taxonomy IS NOT NULL AND taxonomy_classification IS NULL) AS taxonomy_unlabeled,
  COUNTIF(status != 'deactivated' AND entity_type_code IS NULL)  AS active_without_entity_type
FROM `npi-reconciliation.work.nppes_slim`;
