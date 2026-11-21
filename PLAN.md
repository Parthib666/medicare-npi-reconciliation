# Project plan: medicare-npi-reconciliation

## 1. What it is, in simple terms

Every US healthcare provider has a 10-digit ID called an **NPI** (National Provider Identifier). The government keeps the official list of these IDs, with names, addresses, specialties and status, in a registry called **NPPES**.

When a provider bills Medicare, the claim carries their NPI. CMS publishes how much each NPI billed Medicare, broken down by procedure.

This project lines up those two sources, **who billed Medicare** and **what the official registry says about that ID**, and finds where they disagree:

- IDs that billed but aren't in the registry at all
- IDs that billed but were later shut off (deactivated)
- IDs that aren't valid NPIs (wrong check digit)
- The same ID shown as a person in one source and an organisation in the other
- Different state, ZIP code, name or specialty for the same ID

This is the kind of work a revenue cycle data-operations team does every day: checking that provider data matches before claims go out, because mismatched provider details are a common reason claims get rejected.

## 2. Target

**What you'll have at the end:**

1. A set of SQL files, one per check, that run in BigQuery against the public tables
2. A summary table: one row per check, with how many providers failed and how many Medicare dollars those providers represent
3. A Jupyter notebook with 4–5 charts explaining the findings
4. A README written as a step-by-step procedure (SOP) that someone else could follow to rerun the checks
5. A public GitHub repo containing all of the above

**Interview story it should support:** "I reconciled 2015 Medicare billing against the national NPI registry. I found X providers billing $Y who were later deactivated, Z with mismatched practice states, and documented which mismatches were real errors versus normal changes over time."

**Done means:** every check runs from a clean BigQuery session, the numbers in the README match the summary table, and the repo has no data files or credentials in it.

**Budget:** stay under 50 GB of query processing in total, which is about 5% of the free monthly 1 TiB.

## 3. Steps at a glance

| # | Step | Time | Output |
|---:|---|---|---|
| 1 | Pin the scope and key decisions | 15 min | Decisions section of README |
| 2 | Build a one-row-per-provider Medicare table | 30 min | `sql/01_medicare_providers.sql` |
| 3 | Build a slim registry table, with specialty names | 45 min | `sql/02_nppes_slim.sql` |
| 4 | Profile both tables | 30 min | `sql/03_profile.sql`, notes |
| 5 | Write the checks | 2 hrs | `sql/10_*.sql` to `sql/16_*.sql` |
| 6 | Combine into one summary table | 30 min | `sql/20_summary.sql` |
| 7 | Set up Python to query BigQuery | 30 min | `.venv`, `requirements.txt` |
| 8 | Build the notebook and charts | 1.5 hrs | `notebooks/analysis.ipynb`, `results/*.png` |
| 9 | Write the README as an SOP | 1 hr | `README.md` |
| 10 | Review and publish to GitHub | 30 min | Public repo |

Total: about 7–8 hours. A realistic split is steps 1–6 tonight and steps 7–10 the next night.

## 4. Each step in detail

### Step 1: Pin the scope and key decisions

Write these down at the top of the README before any SQL, so every later choice traces back to them:

- **Billing year: 2015 only** (`cms_medicare.physicians_and_other_supplier_2015`). It's the latest year available, and using one year avoids the column differences between 2012–13 and 2014–15.
- **Registry: `nppes.npi_raw`** (March 2026). It's the current registry, so it's what a real data-ops team would validate against. It records deactivations up to 2026, and it stores blanks as NULL rather than `''`. Query cost is about the same as `npi_optimized`, because BigQuery charges only for the columns read. Specialty names come from a join to `nppes.healthcare_provider_taxonomy_code_set` (step 3).
- **Time gap:** the billing is from 2015 and the registry from 2026. Any difference could be a data error or a normal change since 2015 (a provider moved, changed their name, retired). Every check must say which of those it's likely to be.
- **Fair-comparison point:** the name, address and entity columns in the Medicare file start with `nppes_`. CMS copied them from the registry in 2015. So a mismatch today mostly measures **what changed in the registry since 2015**, not an error in the Medicare file. Say this plainly in the README; it shows you understand the data.

### Step 2: Build a one-row-per-provider Medicare table

The 2015 Medicare table has about 9.5 million rows: one per provider, procedure code and place of service. The checks are about providers, so collapse it to one row per NPI.

Columns to keep or calculate:

| Column | How |
|---|---|
| `npi` | group by |
| `last_org_name`, `first_name`, `entity_code`, `state`, `zip5`, `provider_type` | `ANY_VALUE()`. Check in step 4 that each NPI really has only one value |
| `zip5` | `LEFT(nppes_provider_zip, 5)` |
| `services` | `SUM(line_srvc_cnt)` |
| `allowed_usd` | `SUM(line_srvc_cnt * average_medicare_allowed_amt)` |
| `paid_usd` | `SUM(line_srvc_cnt * average_medicare_payment_amt)` |
| `hcpcs_codes` | `COUNT(DISTINCT hcpcs_code)` |

First create a dataset named `work` in the project (Explorer → project `npi-reconciliation` → Create dataset, location US, to match the public data). Then save the table with ``CREATE TABLE `npi-reconciliation.work.medicare_providers_2015` AS SELECT ...``. The backticks are needed because the project ID contains a hyphen. The sandbox doesn't allow INSERT or UPDATE, but creating a table from a query is fine. It will be about 1 million rows and small.

Watch for: tables in the sandbox expire after 60 days, so the SQL files are the real record; the saved table is just a cache.

### Step 3: Build a slim registry table

**Goal:** one row per NPI from `nppes.npi_raw`, only for NPIs that billed Medicare in 2015, with only the columns the checks need, cleaned and labelled. Saved as `work.nppes_slim`.

`npi_raw` has 330 columns and 9.37 million rows. It holds specialty **codes** (e.g. `207R00000X`) but no readable names, so this step also joins the taxonomy lookup table.

It's split into files so the expensive scan of `npi_raw` runs only once:

| File | Does | Cost |
|---|---|---|
| `sql/02a_taxonomy_metadata.sql` | 3a: lookup table columns and copies | ~10 MB |
| `sql/02b_nppes_base.sql` | 3b, 3c, 3e: builds `work.nppes_base` from `npi_raw` | the one big scan |
| `sql/02c_nppes_slim.sql` | 3d: adds specialty names → `work.nppes_slim` | small |
| `sql/02d_validate_nppes.sql` | 3f: checks | small |

#### 3a. Look up the taxonomy table's columns (metadata only, ~10 MB billed)

`nppes` has an unversioned `healthcare_provider_taxonomy_code_set` plus 17 dated copies (`_090` to `_170`). Run:

```sql
SELECT table_name, column_name, data_type
FROM `bigquery-public-data.nppes.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name IN ('healthcare_provider_taxonomy_code_set',
                     'healthcare_provider_taxonomy_code_set_170')
ORDER BY table_name, ordinal_position;
```

Then compare the row counts of the two tables with `__TABLES__` (free). Use the unversioned table if it's at least as large as `_170`; otherwise use `_170`. Record the column names and the choice in SETUP.md.

The table should have a code column and descriptive columns such as grouping, classification and specialization, but confirm the actual names before writing 3d.

#### 3b. Select and clean the registry columns

From `npi_raw`, keep only:

| Group | Columns |
|---|---|
| ID and type | `npi`, `entity_type_code`, `replacement_npi` |
| Names | `provider_last_name_legal_name`, `provider_first_name`, `provider_organization_name_legal_business_name` |
| Practice location | `provider_business_practice_location_address_state_name`, `provider_business_practice_location_address_postal_code` |
| Specialty | `healthcare_provider_taxonomy_code_1` to `_15`, `healthcare_provider_primary_taxonomy_switch_1` to `_15` |
| Dates and status | `provider_enumeration_date`, `last_update_date`, `npi_deactivation_date`, `npi_deactivation_reason_code`, `npi_reactivation_date` |

Cleaning rules:
- Every text column: `NULLIF(TRIM(col), '')`, so blanks and NULLs count as the same thing
- Names: `UPPER()` as well
- Postal code: keep the first 5 characters as `zip5`

Filter to Medicare billers with `WHERE npi IN (SELECT npi FROM work.medicare_providers_2015)`. This makes the saved table small, but **doesn't reduce the query cost**: BigQuery still reads the chosen columns for all 9.37 million rows.

#### 3c. Work out one primary specialty per provider

A provider can list up to 15 specialty codes; the one marked `Y` in its matching `primary_taxonomy_switch_N` is the main one. Turn the 15 code/switch pairs into rows and pick the primary:

```sql
-- inside the npi_raw CTE
(SELECT t.code
 FROM UNNEST([
   STRUCT(healthcare_provider_taxonomy_code_1 AS code, healthcare_provider_primary_taxonomy_switch_1 AS sw),
   STRUCT(healthcare_provider_taxonomy_code_2, healthcare_provider_primary_taxonomy_switch_2),
   -- ... through _15
 ]) AS t WITH OFFSET pos
 WHERE NULLIF(TRIM(t.code), '') IS NOT NULL
 ORDER BY IF(t.sw = 'Y', 0, 1), pos
 LIMIT 1) AS primary_taxonomy
```

This picks the code marked `Y`; if none is marked, it falls back to the first listed code. Add a `primary_taxonomy_source` column (`switch` or `fallback`) so step 4 can count how often the fallback happens.

#### 3d. Add the specialty name

`LEFT JOIN` the taxonomy table from 3a on `primary_taxonomy` = its code column. Add `taxonomy_grouping`, `taxonomy_classification` and `taxonomy_specialization` (or whatever 3a shows they're called).

Use a LEFT JOIN so a code missing from the lookup doesn't drop the provider. Step 4 counts codes with no label.

#### 3e. Add a status column

| `status` | Rule |
|---|---|
| `deactivated` | `npi_deactivation_date` is set, and `npi_reactivation_date` is empty or earlier than the deactivation |
| `reactivated` | both are set, and reactivation is on or after deactivation |
| `active` | no deactivation date |

**Warning:** deactivated records in `npi_raw` keep only the NPI and the dates (SETUP.md, sample join). Name, entity type, state and specialty are all NULL. Checks 13–16 must therefore exclude `status = 'deactivated'`, otherwise every deactivated ID shows up as a false name, state or entity mismatch. Those providers are already counted in check 12.

#### 3f. Save, and confirm

1. Before running, read the console's bytes estimate. Expect well under 2.42 GB, because only about 40 of the 330 columns are read. If it's higher, a column list is wrong.
2. Run it as ``CREATE OR REPLACE TABLE `npi-reconciliation.work.nppes_slim` AS ...``
3. Confirm:
   - row count is at most the row count of `work.medicare_providers_2015`
   - `npi` is unique: `COUNT(*) = COUNT(DISTINCT npi)`
4. Run it once. Steps 4–8 read `work.nppes_slim`, never `npi_raw` again.

### Step 4: Profile both tables

Before checking for problems, know what normal looks like. One query file, several small queries:

- Row counts: Medicare providers, registry rows, how many match on NPI
- Does any NPI have more than one name, state or provider type in the Medicare data? (This tests the `ANY_VALUE` assumption from step 2.)
- Entity split: individuals vs organisations in each source
- Blank rate for each column used in the checks
- Range of `provider_enumeration_date` and `npi_deactivation_date`

Write 3–5 bullet points of findings. They become the "About the data" section of the README.

### Step 5: Write the checks

One file per check. Each saves a table `work.chk_NN_*` with one row per failing NPI (the NPI, the values from both sides, and `allowed_usd` so the impact can be measured in dollars), then shows a short result. Check 14 is the exception: it keeps every compared provider with a `location_result` column, so the summary has a denominator.

Run the files in number order (10–17). Each file has more than one statement; run the whole file and use **View results** for each.

| File | Check | Rule | Likely meaning |
|---|---|---|---|
| `10_not_in_registry.sql` | ID not in registry | Medicare NPI with no row in `nppes_slim` | Real error, or a record later removed. Expect very few |
| `11_invalid_check_digit.sql` | Not a valid NPI | Fails the NPI check digit (Luhn on `80840` + first 9 digits) | Real data error. Expect zero; a zero result is still worth reporting |
| `12_deactivated.sql` | Billed, later deactivated | `status = 'deactivated'`. Three groups (from step 4): deactivated **before 2015** (13 NPIs: billed long after deactivation, high), **during 2015** (751: billing year and deactivation overlap, and the yearly data can't show which came first, medium), **after 2015** (34,253: normal churn, info). Reason codes are blank, so no split by cause | The before-2015 group is the red flag |
| `13_entity_mismatch.sql` | Person vs organisation | Medicare `entity_code` (`I`/`O`) vs registry `entity_type_code` (`1`/`2`), non-deactivated only | Step 4 already shows **0 mismatches**. Keep the check and report the zero |
| `14_state_mismatch.sql` | Different state | Standardise the registry state first: full names → codes (`FLORIDA` → `FL`, `PUERTO RICO`/`P.R.`/`GUAYNABO` → `PR`, `ST CROIX`/`US VIRGIN ISLANDS` → `VI`, `SAIPAN` → `MP`, `AK- ALASKA` → `AK`, etc.), foreign regions → `FOREIGN`, unresolvable values (`SAN JOSE`, `FORT BEND`, `USA`) → `UNKNOWN`. Medicare `XX` → `UNKNOWN`, `ZZ` → `FOREIGN`. Exclude `UNKNOWN` on either side. Then compare state, and 5-digit ZIP within matching states | Mostly providers who moved since 2015 |
| `17_issued_after_billing.sql` | Billed before the ID existed | `provider_enumeration_date > '2015-12-31'` (2 NPIs in step 4). Look up both by hand and record what you find | Real error or a re-issued record; high until explained |
| `15_name_mismatch.sql` | Different name | Individuals: last name. Organisations: legal business name. Compare uppercased and with punctuation removed so "ST. MARY'S" matches "ST MARYS" | Marriage or name change, or organisation renamed |
| `16_specialty_mismatch.sql` | Unusual specialty | Data-driven instead of a hand-built mapping: for each Medicare provider type with ≥100 comparable providers, flag providers whose registry taxonomy classification is held by <1% of that type | Specialty changed, or one source is wrong; indicative only |

Write the rule in a comment at the top of each file in plain English, then the SQL. The README will reuse these comments.

### Step 6: Combine into one summary table

`20_summary.sql` runs each check as a CTE and stacks the results with `UNION ALL` into `work.dq_summary`:

| check_id | check_name | severity | providers_checked | providers_failed | pct_failed | allowed_usd_affected |
|---|---|---|---|---|---|---|

Severity:
- **High:** real errors (10, 11, 13, 17, 12 deactivated before 2015)
- **Medium:** could be either (16, 12 deactivated during 2015)
- **Info:** normal change over time (14, 15, 12 after 2015)

This is the table the notebook and README are built from.

### Step 7: Set up Python to query BigQuery

> **As built:** the Google Cloud CLI was replaced by `pydata-google-auth`, which signs in through the browser from Python directly. See SETUP.md → Python. The original plan is below for reference.

Install on the PC:

1. Google Cloud CLI (`gcloud`), then sign in once:
   `gcloud auth application-default login`
2. In the project folder:
   ```
   python -m venv .venv
   .venv\Scripts\Activate.ps1
   pip install google-cloud-bigquery db-dtypes pandas matplotlib jupyter ipykernel
   pip freeze > requirements.txt
   ```
3. Test: run `SELECT 1` from Python with project `npi-reconciliation`.

Python 3.14 is new; if any library won't install, create the virtual environment with Python 3.12 instead (`py -3.12 -m venv .venv`).

### Step 8: Build the notebook and charts

The notebook reads only the small saved tables (`dq_summary` and the per-check results), not the big public tables, so rerunning it is cheap.

Charts (one point each):

1. **Failures by check:** horizontal bar of `providers_failed`, coloured by severity
2. **Dollars at stake:** horizontal bar of `allowed_usd_affected` by check
3. **Deactivations over time:** count of 2015 billers by year of deactivation, with a line marking the end of 2015
4. **State mismatches:** top 10 state-to-state moves (e.g. NY → FL)
5. **Mismatch rate by provider type:** top 15 provider types by `pct_failed`

Save each as a PNG in `results/` for the README. Under each chart in the notebook, write one sentence on what it shows.

### Step 9: Write the README as an SOP

Sections:

1. **Purpose:** two sentences from section 1 of this plan
2. **Key findings:** 3–5 bullets with real numbers, plus the two most important charts
3. **Data sources:** tables, years, the 2015 vs 2026 time-gap caveat
4. **Decisions:** from step 1
5. **How to run it:** numbered steps a new teammate could follow, in order
6. **Check reference:** one row per check: rule, severity, likely cause, what to do if it fails
7. **Limitations:** time gap, specialty mapping is rough, sandbox tables expire after 60 days

### Step 10: Review and publish to GitHub

Before pushing:

- Rerun every SQL file in order and confirm the summary numbers match the README
- `.gitignore` contains `.venv/`, `data/`, `.ipynb_checkpoints/` and any credentials file
- Clear notebook outputs that contain long row-level tables; keep the charts
- Search the repo for the project's credentials or personal email before committing

Then:

```
git init
git add .
git commit -m "NPI reconciliation: Medicare 2015 vs NPPES registry"
```

Create an empty public repo on GitHub named `medicare-npi-reconciliation` and push to it. Pin it on your GitHub profile.

## Folder layout

```
medicare-npi-reconciliation/
├── sql/
│   ├── 01_medicare_providers.sql
│   ├── 02_nppes_slim.sql
│   ├── 03_profile.sql
│   ├── 10_not_in_registry.sql ... 16_specialty_mismatch.sql
│   └── 20_summary.sql
├── notebooks/
│   └── analysis.ipynb
├── results/          # chart PNGs, small CSV exports
├── .gitignore
├── requirements.txt
├── PLAN.md
├── README.md
└── SETUP.md
```
