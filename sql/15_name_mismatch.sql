-- Check 15: different name
-- Rule: compare the Medicare name with the registry's legal name.
--   Individuals (entity I): Medicare last_org_name vs registry last_name.
--   Organisations (entity O): Medicare last_org_name vs registry org_name.
-- Normalising before comparing, so formatting differences don't count:
--   1. uppercase (already done in steps 2 and 3)
--   2. punctuation becomes a space:        "AMERATHON,LLC" -> "AMERATHON LLC"
--      (v1 deleted it, which glued words together so suffixes weren't found)
--   3. organisations only: drop legal suffixes and "THE":
--      INC, LLC, PC, PA, PLLC, LLP, LTD, CORP, CO, COMPANY ...
--   4. remove spaces:                      "ST MARY S"     -> "STMARYS"
-- Two names count as the same if any of these hold:
--   - one starts with the other (truncated names, added surnames:
--     "SMITH" vs "SMITHJONES")
--   - organisations only: one contains the other
--     ("CITYOFBALTIMOREMAYORAND..." contains "MAYORANDCITYCOUNCILOFBALTIMORE")
--   - both are 8+ characters and differ by at most 2 edits (typos, plurals:
--     "ACCUPATHDIAGNOSTICS" vs "ACCUPATHDIAGNOSTIC")
-- Names missing on either side are not compared.
-- Deactivated registry records are excluded (decision 7).
-- Severity: info. Usually a name change (marriage) or an organisation renamed
--           or bought after 2015.
-- Output: work.chk_15_name_mismatch, one row per failing NPI.

CREATE OR REPLACE TABLE `npi-reconciliation.work.chk_15_name_mismatch` AS
WITH names AS (
  SELECT
    m.npi,
    m.entity_code,
    m.state,
    m.provider_type,
    m.services,
    m.allowed_usd,
    m.last_org_name                                          AS medicare_name,
    IF(m.entity_code = 'O', n.org_name, n.last_name)         AS registry_name,
    m.first_name                                             AS medicare_first_name,
    n.first_name                                             AS registry_first_name
  FROM `npi-reconciliation.work.medicare_providers_2015` AS m
  JOIN `npi-reconciliation.work.nppes_slim` AS n
    USING (npi)
  WHERE n.status != 'deactivated'
),
normalised AS (
  SELECT
    *,
    REGEXP_REPLACE(
      IF(entity_code = 'O',
         REGEXP_REPLACE(REGEXP_REPLACE(medicare_name, r'[^A-Z0-9 ]', ' '),
           r'\b(THE|INC|INCORPORATED|LLC|PC|PA|PLLC|LLP|LTD|CORP|CORPORATION|CO|COMPANY)\b', ''),
         REGEXP_REPLACE(medicare_name, r'[^A-Z0-9 ]', ' ')),
      r' ', '') AS medicare_key,
    REGEXP_REPLACE(
      IF(entity_code = 'O',
         REGEXP_REPLACE(REGEXP_REPLACE(registry_name, r'[^A-Z0-9 ]', ' '),
           r'\b(THE|INC|INCORPORATED|LLC|PC|PA|PLLC|LLP|LTD|CORP|CORPORATION|CO|COMPANY)\b', ''),
         REGEXP_REPLACE(registry_name, r'[^A-Z0-9 ]', ' ')),
      r' ', '') AS registry_key
  FROM names
  WHERE medicare_name IS NOT NULL
    AND registry_name IS NOT NULL
)
SELECT *
FROM normalised
WHERE medicare_key != ''
  AND registry_key != ''
  -- prefix match
  AND NOT STARTS_WITH(medicare_key, registry_key)
  AND NOT STARTS_WITH(registry_key, medicare_key)
  -- organisations: containment
  AND NOT (entity_code = 'O'
           AND (STRPOS(medicare_key, registry_key) > 0
             OR STRPOS(registry_key, medicare_key) > 0))
  -- near match: up to 2 edits on names of 8+ characters
  AND NOT (LENGTH(medicare_key) >= 8
           AND LENGTH(registry_key) >= 8
           AND EDIT_DISTANCE(medicare_key, registry_key) <= 2);

-- Show the result: counts by entity type, plus 20 examples to sanity-check
-- that the normalising isn't hiding or creating mismatches.
SELECT
  entity_code,
  COUNT(*)                 AS providers,
  ROUND(SUM(allowed_usd))  AS allowed_usd
FROM `npi-reconciliation.work.chk_15_name_mismatch`
GROUP BY entity_code;

SELECT entity_code, medicare_name, registry_name, medicare_key, registry_key
FROM `npi-reconciliation.work.chk_15_name_mismatch`
WHERE entity_code = 'O'
ORDER BY allowed_usd DESC
LIMIT 20;

SELECT entity_code, medicare_name, registry_name, medicare_first_name, registry_first_name
FROM `npi-reconciliation.work.chk_15_name_mismatch`
WHERE entity_code = 'I'
ORDER BY allowed_usd DESC
LIMIT 20;
