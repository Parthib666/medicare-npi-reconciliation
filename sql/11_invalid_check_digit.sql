-- Check 11: not a valid NPI
-- Rule: the NPI must be 10 digits, and its last digit must be the correct
--       check digit. NPIs use the Luhn formula applied to "80840" followed by
--       the NPI (80840 is the prefix for US health identifiers). The full
--       15-digit string is valid when its Luhn sum is divisible by 10.
-- Luhn sum: reading from the right, keep the 1st, 3rd, 5th... digits as they
--       are; double the 2nd, 4th, 6th...; if doubling gives more than 9,
--       subtract 9. Add everything up.
-- Severity: high. An invalid NPI can't be a real ID.
-- Expected: 0. Step 4 found every NPI is 10 digits; this checks the digits
--           themselves.
-- Output: work.chk_11_invalid_check_digit, one row per failing NPI.
--
-- Test the formula first (optional): 1234567893 is the example of a valid NPI
-- used in CMS's documentation, so luhn_ok should be TRUE for it and FALSE
-- for 1234567890:
--
-- SELECT npi,
--   MOD((SELECT SUM(IF(MOD(pos, 2) = 1,
--                      CAST(ch AS INT64) * 2 - IF(CAST(ch AS INT64) * 2 > 9, 9, 0),
--                      CAST(ch AS INT64)))
--        FROM UNNEST(SPLIT(REVERSE(CONCAT('80840', npi)), '')) AS ch WITH OFFSET AS pos), 10) = 0 AS luhn_ok
-- FROM UNNEST(['1234567893', '1234567890']) AS npi;

CREATE OR REPLACE TABLE `npi-reconciliation.work.chk_11_invalid_check_digit` AS
WITH scored AS (
  SELECT
    m.npi,
    m.entity_code,
    m.last_org_name,
    m.first_name,
    m.state,
    m.provider_type,
    m.services,
    m.allowed_usd,
    REGEXP_CONTAINS(m.npi, r'^\d{10}$') AS is_10_digits,
    IF(
      REGEXP_CONTAINS(m.npi, r'^\d{10}$'),
      (
        SELECT SUM(IF(MOD(pos, 2) = 1,
                      CAST(ch AS INT64) * 2 - IF(CAST(ch AS INT64) * 2 > 9, 9, 0),
                      CAST(ch AS INT64)))
        FROM UNNEST(SPLIT(REVERSE(CONCAT('80840', m.npi)), '')) AS ch WITH OFFSET AS pos
      ),
      NULL
    ) AS luhn_sum
  FROM `npi-reconciliation.work.medicare_providers_2015` AS m
)
SELECT
  * EXCEPT (luhn_sum),
  luhn_sum,
  CASE
    WHEN NOT is_10_digits          THEN 'not_10_digits'
    WHEN MOD(luhn_sum, 10) != 0    THEN 'bad_check_digit'
  END AS failure
FROM scored
WHERE NOT is_10_digits
   OR MOD(luhn_sum, 10) != 0;

-- Show the result.
SELECT
  (SELECT COUNT(*) FROM `npi-reconciliation.work.medicare_providers_2015`) AS npis_checked,
  COUNT(*) AS npis_failed
FROM `npi-reconciliation.work.chk_11_invalid_check_digit`;
