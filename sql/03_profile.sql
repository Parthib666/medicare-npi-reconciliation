-- Step 4: profile both working tables before writing any checks.
-- Goal: know what "normal" looks like, and test the assumptions made in steps 2-3.
-- Reads only the small work tables. Run each query on its own and save its result
-- as the file named in its header.

-- =====================================================================
-- Q1. Medicare side  ->  results/03_q1_medicare_profile.json
-- One row. Tests the ANY_VALUE assumption from step 2 (n_* should be 1),
-- entity split, blank rates, value formats and the dollar distribution.
-- =====================================================================
SELECT
  COUNT(*)                                        AS providers,

  -- ANY_VALUE assumption: NPIs with more than one value in the raw rows
  COUNTIF(n_names > 1)                            AS npis_multi_name,
  COUNTIF(n_states > 1)                           AS npis_multi_state,
  COUNTIF(n_provider_types > 1)                   AS npis_multi_provider_type,

  -- Entity split
  COUNTIF(entity_code = 'I')                      AS individuals,
  COUNTIF(entity_code = 'O')                      AS organisations,
  COUNTIF(entity_code IS NULL OR entity_code NOT IN ('I', 'O')) AS entity_other,

  -- Blank rates
  COUNTIF(last_org_name IS NULL)                  AS blank_last_org_name,
  COUNTIF(entity_code = 'I' AND first_name IS NULL) AS individual_blank_first_name,
  COUNTIF(state IS NULL)                          AS blank_state,
  COUNTIF(zip5 IS NULL)                           AS blank_zip,
  COUNTIF(provider_type IS NULL)                  AS blank_provider_type,

  -- Formats
  COUNTIF(NOT REGEXP_CONTAINS(npi, r'^\d{10}$'))  AS npi_not_10_digits,
  COUNTIF(NOT REGEXP_CONTAINS(zip5, r'^\d{5}$'))  AS zip_not_5_digits,
  COUNT(DISTINCT state)                           AS distinct_states,
  COUNT(DISTINCT provider_type)                   AS distinct_provider_types,

  -- Dollars (allowed amount per provider)
  COUNTIF(allowed_usd <= 0)                       AS nonpositive_allowed,
  ROUND(MIN(allowed_usd), 2)                      AS min_allowed_usd,
  ROUND(APPROX_QUANTILES(allowed_usd, 100)[OFFSET(50)], 2) AS median_allowed_usd,
  ROUND(APPROX_QUANTILES(allowed_usd, 100)[OFFSET(99)], 2) AS p99_allowed_usd,
  ROUND(MAX(allowed_usd), 2)                      AS max_allowed_usd
FROM `npi-reconciliation.work.medicare_providers_2015`;


-- =====================================================================
-- Q2. Registry side  ->  results/03_q2_registry_profile.json
-- One row. Field checks use only non-deactivated records (decision 7).
-- =====================================================================
SELECT
  COUNT(*)                                                   AS registry_rows,
  COUNTIF(status != 'deactivated')                           AS compared_rows,

  -- Entity split (non-deactivated)
  COUNTIF(status != 'deactivated' AND entity_type_code = 1)  AS individuals,
  COUNTIF(status != 'deactivated' AND entity_type_code = 2)  AS organisations,
  COUNTIF(status != 'deactivated' AND (entity_type_code IS NULL OR entity_type_code NOT IN (1, 2))) AS entity_other,

  -- Blank rates (non-deactivated)
  COUNTIF(status != 'deactivated' AND entity_type_code = 1 AND last_name IS NULL)  AS individual_blank_last_name,
  COUNTIF(status != 'deactivated' AND entity_type_code = 1 AND first_name IS NULL) AS individual_blank_first_name,
  COUNTIF(status != 'deactivated' AND entity_type_code = 2 AND org_name IS NULL)   AS organisation_blank_name,
  COUNTIF(status != 'deactivated' AND state IS NULL)                               AS blank_state,
  COUNTIF(status != 'deactivated' AND zip5 IS NULL)                                AS blank_zip,
  COUNTIF(status != 'deactivated' AND NOT REGEXP_CONTAINS(zip5, r'^\d{5}$'))       AS zip_not_5_digits,
  COUNT(DISTINCT IF(status != 'deactivated', state, NULL))                         AS distinct_states,

  -- Enumeration (when the NPI was issued). Issued after 2015 but billed in 2015 would be a red flag.
  MIN(provider_enumeration_date)                             AS first_enumeration,
  MAX(provider_enumeration_date)                             AS last_enumeration,
  COUNTIF(provider_enumeration_date > DATE '2015-12-31')     AS enumerated_after_2015,
  COUNTIF(status != 'deactivated' AND provider_enumeration_date IS NULL) AS blank_enumeration_date,

  -- Deactivation timing
  MIN(npi_deactivation_date)                                 AS first_deactivation,
  MAX(npi_deactivation_date)                                 AS last_deactivation,
  COUNTIF(status = 'deactivated' AND npi_deactivation_date <= DATE '2015-12-31') AS deactivated_by_end_2015,
  COUNTIF(status = 'deactivated' AND npi_deactivation_date >  DATE '2015-12-31') AS deactivated_after_2015,
  COUNTIF(replacement_npi IS NOT NULL)                       AS has_replacement_npi,

  -- Registry freshness
  MIN(last_update_date)                                      AS oldest_update,
  MAX(last_update_date)                                      AS newest_update
FROM `npi-reconciliation.work.nppes_slim`;


-- =====================================================================
-- Q3. Entity type, both sides  ->  results/03_q3_entity_crosstab.json
-- Preview of check 13. Rows with registry_status NULL are the NPIs not
-- found in the registry.
-- =====================================================================
SELECT
  m.entity_code                          AS medicare_entity,      -- I / O
  CAST(n.entity_type_code AS STRING)     AS registry_entity,      -- 1 / 2
  n.status                               AS registry_status,
  COUNT(*)                               AS providers,
  ROUND(SUM(m.allowed_usd))              AS allowed_usd
FROM `npi-reconciliation.work.medicare_providers_2015` AS m
LEFT JOIN `npi-reconciliation.work.nppes_slim` AS n
  USING (npi)
GROUP BY 1, 2, 3
ORDER BY providers DESC;


-- =====================================================================
-- Q4. Deactivations by year and reason  ->  results/03_q4_deactivations.json
-- Input for check 12 and chart 3. Reason codes in NPPES:
-- DT = death, DB = disbandment, FR = fraud, OT = other.
-- Includes reactivated NPIs, shown separately by status.
-- =====================================================================
SELECT
  EXTRACT(YEAR FROM n.npi_deactivation_date)  AS deactivation_year,
  n.npi_deactivation_reason_code              AS reason,
  n.status,
  COUNT(*)                                    AS providers,
  ROUND(SUM(m.allowed_usd))                   AS allowed_usd
FROM `npi-reconciliation.work.nppes_slim` AS n
JOIN `npi-reconciliation.work.medicare_providers_2015` AS m
  USING (npi)
WHERE n.npi_deactivation_date IS NOT NULL
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;


-- =====================================================================
-- Q5. State values on each side  ->  results/03_q5_state_values.json
-- Shows codes that exist on only one side (e.g. territories, military,
-- foreign or "unknown" codes), which check 14 must handle.
-- =====================================================================
WITH medicare AS (
  SELECT state, COUNT(*) AS providers
  FROM `npi-reconciliation.work.medicare_providers_2015`
  GROUP BY state
),
registry AS (
  SELECT state, COUNT(*) AS providers
  FROM `npi-reconciliation.work.nppes_slim`
  WHERE status != 'deactivated'
  GROUP BY state
)
SELECT
  COALESCE(m.state, r.state)  AS state,
  m.providers                 AS medicare_providers,
  r.providers                 AS registry_providers
FROM medicare AS m
FULL OUTER JOIN registry AS r
  ON m.state = r.state
ORDER BY state;
