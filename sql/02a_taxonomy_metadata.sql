-- Step 3a: find the column names of the specialty (taxonomy) lookup table,
-- and which of its 18 copies is the most complete.
-- Metadata only: about 10 MB billed per query.

-- Query 1: columns of the unversioned table and the newest dated copy.
SELECT table_name, ordinal_position, column_name, data_type
FROM `bigquery-public-data.nppes.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name IN ('healthcare_provider_taxonomy_code_set',
                     'healthcare_provider_taxonomy_code_set_170')
ORDER BY table_name, ordinal_position;

-- Query 2: row count and last change of every copy (free).
SELECT
  table_id,
  row_count,
  DATE(TIMESTAMP_MILLIS(last_modified_time)) AS last_modified
FROM `bigquery-public-data.nppes.__TABLES__`
WHERE table_id LIKE 'healthcare_provider_taxonomy_code_set%'
ORDER BY table_id;
