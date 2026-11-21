-- Step 3b, 3c, 3e: registry records for every NPI that billed Medicare in 2015.
--
-- The one expensive query in step 3: it reads about 40 of npi_raw's 330 columns
-- across all 9.37M rows. Check the console's bytes estimate before running;
-- it should be well under 2.42 GB. Run once. Later steps read work.nppes_base,
-- never npi_raw.
--
-- Specialty names are added separately in 02c (a cheap join on small tables),
-- so this scan doesn't have to be repeated if the lookup choice changes.
--
-- Cleaning: text NULLIF(TRIM(x), '') so blank = missing; names and state
-- uppercased; postal code cut to 5 digits.

CREATE OR REPLACE TABLE `npi-reconciliation.work.nppes_base` AS
WITH registry AS (
  SELECT
    r.npi,
    r.entity_type_code,
    NULLIF(TRIM(r.replacement_npi), '') AS replacement_npi,

    UPPER(NULLIF(TRIM(r.provider_last_name_legal_name), ''))                   AS last_name,
    UPPER(NULLIF(TRIM(r.provider_first_name), ''))                             AS first_name,
    UPPER(NULLIF(TRIM(r.provider_organization_name_legal_business_name), ''))  AS org_name,

    UPPER(NULLIF(TRIM(r.provider_business_practice_location_address_state_name), '')) AS state,
    LEFT(NULLIF(TRIM(r.provider_business_practice_location_address_postal_code), ''), 5) AS zip5,

    r.provider_enumeration_date,
    r.last_update_date,
    r.npi_deactivation_date,
    NULLIF(TRIM(r.npi_deactivation_reason_code), '') AS npi_deactivation_reason_code,
    r.npi_reactivation_date,

    -- 3c. Primary specialty: the code whose switch is 'Y';
    -- if none is marked, the first code listed.
    (
      SELECT AS STRUCT TRIM(t.code) AS code, UPPER(TRIM(t.sw)) AS sw
      FROM UNNEST([
        STRUCT(r.healthcare_provider_taxonomy_code_1  AS code, r.healthcare_provider_primary_taxonomy_switch_1  AS sw),
        STRUCT(r.healthcare_provider_taxonomy_code_2,  r.healthcare_provider_primary_taxonomy_switch_2),
        STRUCT(r.healthcare_provider_taxonomy_code_3,  r.healthcare_provider_primary_taxonomy_switch_3),
        STRUCT(r.healthcare_provider_taxonomy_code_4,  r.healthcare_provider_primary_taxonomy_switch_4),
        STRUCT(r.healthcare_provider_taxonomy_code_5,  r.healthcare_provider_primary_taxonomy_switch_5),
        STRUCT(r.healthcare_provider_taxonomy_code_6,  r.healthcare_provider_primary_taxonomy_switch_6),
        STRUCT(r.healthcare_provider_taxonomy_code_7,  r.healthcare_provider_primary_taxonomy_switch_7),
        STRUCT(r.healthcare_provider_taxonomy_code_8,  r.healthcare_provider_primary_taxonomy_switch_8),
        STRUCT(r.healthcare_provider_taxonomy_code_9,  r.healthcare_provider_primary_taxonomy_switch_9),
        STRUCT(r.healthcare_provider_taxonomy_code_10, r.healthcare_provider_primary_taxonomy_switch_10),
        STRUCT(r.healthcare_provider_taxonomy_code_11, r.healthcare_provider_primary_taxonomy_switch_11),
        STRUCT(r.healthcare_provider_taxonomy_code_12, r.healthcare_provider_primary_taxonomy_switch_12),
        STRUCT(r.healthcare_provider_taxonomy_code_13, r.healthcare_provider_primary_taxonomy_switch_13),
        STRUCT(r.healthcare_provider_taxonomy_code_14, r.healthcare_provider_primary_taxonomy_switch_14),
        STRUCT(r.healthcare_provider_taxonomy_code_15, r.healthcare_provider_primary_taxonomy_switch_15)
      ]) AS t WITH OFFSET AS pos
      WHERE NULLIF(TRIM(t.code), '') IS NOT NULL
      ORDER BY IF(UPPER(TRIM(t.sw)) = 'Y', 0, 1), pos
      LIMIT 1
    ) AS primary_tax

  FROM `bigquery-public-data.nppes.npi_raw` AS r
  WHERE r.npi IN (
    SELECT npi FROM `npi-reconciliation.work.medicare_providers_2015`
  )
)
SELECT
  npi,
  entity_type_code,
  replacement_npi,
  last_name,
  first_name,
  org_name,
  state,
  zip5,
  provider_enumeration_date,
  last_update_date,
  npi_deactivation_date,
  npi_deactivation_reason_code,
  npi_reactivation_date,

  primary_tax.code AS primary_taxonomy,
  CASE
    WHEN primary_tax.code IS NULL THEN NULL
    WHEN primary_tax.sw = 'Y'     THEN 'switch'
    ELSE 'fallback'
  END AS primary_taxonomy_source,

  -- 3e. Status. Deactivated records keep only the NPI and dates, so the
  -- field-comparison checks (13-16) must exclude status = 'deactivated'.
  CASE
    WHEN npi_deactivation_date IS NULL THEN 'active'
    WHEN npi_reactivation_date >= npi_deactivation_date THEN 'reactivated'
    ELSE 'deactivated'
  END AS status
FROM registry;
