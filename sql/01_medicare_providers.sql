-- One row per NPI that billed Medicare in 2015.
-- Dollars: allowed amount = services x average allowed per service.
CREATE OR REPLACE TABLE `npi-reconciliation.work.medicare_providers_2015` AS
SELECT
  npi,
  ANY_VALUE(UPPER(NULLIF(TRIM(nppes_provider_last_org_name), ''))) AS last_org_name,
  ANY_VALUE(UPPER(NULLIF(TRIM(nppes_provider_first_name), '')))    AS first_name,
  ANY_VALUE(NULLIF(TRIM(nppes_entity_code), ''))                    AS entity_code,
  ANY_VALUE(NULLIF(TRIM(nppes_provider_state), ''))                 AS state,
  ANY_VALUE(LEFT(NULLIF(TRIM(nppes_provider_zip), ''), 5))          AS zip5,
  ANY_VALUE(NULLIF(TRIM(provider_type), ''))                        AS provider_type,

  -- For step 4: should all be 1. Anything above 1 means ANY_VALUE hid a conflict.
  COUNT(DISTINCT nppes_provider_last_org_name) AS n_names,
  COUNT(DISTINCT nppes_provider_state)         AS n_states,
  COUNT(DISTINCT provider_type)                AS n_provider_types,

  SUM(line_srvc_cnt)                                AS services,
  SUM(line_srvc_cnt * average_medicare_allowed_amt) AS allowed_usd,
  SUM(line_srvc_cnt * average_medicare_payment_amt) AS paid_usd,
  COUNT(DISTINCT hcpcs_code)                        AS hcpcs_codes
FROM `bigquery-public-data.cms_medicare.physicians_and_other_supplier_2015`
GROUP BY npi;
