-- Check 14: different practice location
-- Rule: after standardising state values on both sides, compare state; where
--       the state matches, compare the 5-digit ZIP.
-- Why standardise: registry state is free text (step 4, Q5). It has 110
--       values against Medicare's 61, e.g. 'FLORIDA', 'P.R.', 'TOKYO'.
--       Comparing raw values would report false mismatches.
-- Standardising:
--   Medicare  'XX' -> UNKNOWN, 'ZZ' -> FOREIGN, other codes kept.
--   Registry  valid US codes kept; known variants mapped (table below);
--             NULL -> UNKNOWN; anything not listed -> UNMAPPED.
--   Rows with UNKNOWN or UNMAPPED on either side are not compared.
--   UNMAPPED should be zero; the second query below lists any, so new
--   variants are caught instead of silently counted as mismatches.
-- Deactivated registry records are excluded (decision 7).
-- Severity: info. Most differences are providers who moved after 2015.
--
-- Output: work.chk_14_location, one row per non-deactivated provider, with:
--   location_result = 'state_mismatch' | 'zip_mismatch' | 'match' | 'not_compared'
-- Keeping all rows (not just failures) gives the summary its denominator.

CREATE OR REPLACE TABLE `npi-reconciliation.work.chk_14_location` AS
WITH us_codes AS (
  SELECT code
  FROM UNNEST([
    'AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA','HI','ID','IL','IN','IA',
    'KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH','NJ',
    'NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN','TX','UT','VT',
    'VA','WA','WV','WI','WY',
    'DC',                                -- District of Columbia
    'PR','VI','GU','AS','MP',            -- territories
    'AA','AE','AP'                       -- military mail
  ]) AS code
),
-- Every non-standard registry value seen in step 4 (Q5), and what it means.
registry_fixes AS (
  SELECT raw, std
  FROM UNNEST([
    -- US states written out or with extra text
    STRUCT('ALABAMA' AS raw, 'AL' AS std),
    ('AK- ALASKA', 'AK'), ('FLORIDA', 'FL'), ('ILLINOIS', 'IL'),
    ('MICHIGAN', 'MI'), ('NC - NORTH CAROLINA', 'NC'), ('NEW JERSEY', 'NJ'),
    ('NEW MEXICO', 'NM'), ('VIRGINIA', 'VA'),
    -- US cities / territories written out
    ('SAN DIEGO', 'CA'),
    ('PUERTO RICO', 'PR'), ('P.R.', 'PR'), ('GUAYNABO', 'PR'),
    ('US VIRGIN ISLANDS', 'VI'), ('ST CROIX', 'VI'),
    ('SAIPAN', 'MP'),
    -- Can't tell which state
    ('APO', 'UNKNOWN'),          -- military mail, branch not given
    ('SAN JOSE', 'UNKNOWN'),     -- California or Costa Rica
    ('FORT BEND', 'UNKNOWN'),    -- probably Texas, not certain
    ('USA', 'UNKNOWN'),
    ('CE', 'UNKNOWN'),
    -- Outside the US
    ('ADANA', 'FOREIGN'), ('AHMADI', 'FOREIGN'), ('BAY OF PLENTY', 'FOREIGN'),
    ('BC', 'FOREIGN'), ('CENTRAL PROVINCE', 'FOREIGN'), ('EU', 'FOREIGN'),
    ('GALIL', 'FOREIGN'), ('ILE DE FRANCE', 'FOREIGN'), ('INCIRLIK', 'FOREIGN'),
    ('ISRAEL', 'FOREIGN'), ('ISTANBUL', 'FOREIGN'), ('KARNATAKA', 'FOREIGN'),
    ('KOREA', 'FOREIGN'), ('LANCASHIRE', 'FOREIGN'), ('NEWFOUNDLAND', 'FOREIGN'),
    ('OKINAWA', 'FOREIGN'), ('ON', 'FOREIGN'), ('ONTARIO', 'FOREIGN'),
    ('PORDENONE', 'FOREIGN'), ('PUNJAB', 'FOREIGN'), ('QUEBEC', 'FOREIGN'),
    ('RHEILAND-PFALZ', 'FOREIGN'), ('RHINELAND-PALATINATE', 'FOREIGN'),
    ('RIYADH', 'FOREIGN'), ('SAUDI ARABIA', 'FOREIGN'), ('SOR-TRONDELAG', 'FOREIGN'),
    ('TOKYO', 'FOREIGN'), ('UAE', 'FOREIGN'), ('WESTERN REGION', 'FOREIGN'),
    ('YAMAGATA', 'FOREIGN')
  ])
),
standardised AS (
  SELECT
    m.npi,
    m.entity_code,
    m.last_org_name,
    m.first_name,
    m.provider_type,
    m.services,
    m.allowed_usd,
    m.state      AS medicare_state_raw,
    n.state      AS registry_state_raw,
    m.zip5       AS medicare_zip5,
    n.zip5       AS registry_zip5,
    CASE
      WHEN m.state IS NULL OR m.state = 'XX' THEN 'UNKNOWN'
      WHEN m.state = 'ZZ'                    THEN 'FOREIGN'
      WHEN um.code IS NOT NULL               THEN m.state
      ELSE 'UNMAPPED'
    END AS medicare_state,
    CASE
      WHEN n.state IS NULL      THEN 'UNKNOWN'
      WHEN ur.code IS NOT NULL  THEN n.state
      WHEN f.std IS NOT NULL    THEN f.std
      ELSE 'UNMAPPED'
    END AS registry_state
  FROM `npi-reconciliation.work.medicare_providers_2015` AS m
  JOIN `npi-reconciliation.work.nppes_slim` AS n
    USING (npi)
  LEFT JOIN us_codes AS um ON um.code = m.state
  LEFT JOIN us_codes AS ur ON ur.code = n.state
  LEFT JOIN registry_fixes AS f ON f.raw = n.state
  WHERE n.status != 'deactivated'
)
SELECT
  *,
  CASE
    WHEN medicare_state IN ('UNKNOWN', 'UNMAPPED')
      OR registry_state IN ('UNKNOWN', 'UNMAPPED')       THEN 'not_compared'
    WHEN medicare_state != registry_state                 THEN 'state_mismatch'
    WHEN medicare_state = 'FOREIGN'                       THEN 'match'   -- both abroad; ZIPs not comparable
    WHEN medicare_zip5 IS NOT NULL AND registry_zip5 IS NOT NULL
     AND medicare_zip5 != registry_zip5                   THEN 'zip_mismatch'
    ELSE 'match'
  END AS location_result
FROM standardised;

-- Result 1: how many providers fall in each outcome.
SELECT
  location_result,
  COUNT(*)                 AS providers,
  ROUND(SUM(allowed_usd))  AS allowed_usd
FROM `npi-reconciliation.work.chk_14_location`
GROUP BY location_result
ORDER BY providers DESC;

-- Result 2: guard. Should return no rows. Any row is a registry state value
-- that needs adding to registry_fixes above.
SELECT
  registry_state_raw,
  COUNT(*) AS providers
FROM `npi-reconciliation.work.chk_14_location`
WHERE registry_state = 'UNMAPPED' OR medicare_state = 'UNMAPPED'
GROUP BY registry_state_raw
ORDER BY providers DESC;

-- Result 3: the 20 most common state-to-state moves (input for chart 4).
SELECT
  medicare_state  AS state_2015,
  registry_state  AS state_now,
  COUNT(*)        AS providers
FROM `npi-reconciliation.work.chk_14_location`
WHERE location_result = 'state_mismatch'
GROUP BY 1, 2
ORDER BY providers DESC
LIMIT 20;
