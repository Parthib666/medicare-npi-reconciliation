# NPI reconciliation: BigQuery setup

Checked in the Google Cloud console on 2026-11-20. Everything below comes from queries run against the live tables that day.

## Project

| Item | Value |
|---|---|
| Project ID | `npi-reconciliation` |
| Billing account | None linked (Billing page: "This project has no billing account") |
| BigQuery mode | Sandbox (badge shown in BigQuery Studio) |
| Query allowance | 1 TiB processed per month |
| Storage allowance | 10 GiB lifetime cap, not refunded when data is deleted |
| Starred in Explorer | `bigquery-public-data.cms_medicare`, `bigquery-public-data.nppes` |

The redesigned BigQuery Explorer has no option to star the whole `bigquery-public-data` project, so the two datasets were starred individually. Queries do not depend on starring; fully qualified names work either way.

Sandbox rules from Google's sandbox documentation that affect the project SQL:

- Tables, views and partitions in your own datasets expire after 60 days by default. Recreate or export anything you want to keep.
- DML statements (INSERT, UPDATE, DELETE, MERGE) are not supported, and neither are streaming inserts or the Data Transfer Service. Build result tables from SELECT queries instead.
- Because the storage cap is lifetime, rebuilding large tables repeatedly uses it up. Keep saved results small and query the public tables directly where possible.

## Python (for the notebook)

Set up 2026-11-21.

| Item | Value |
|---|---|
| Python | 3.14.6, in a project virtual environment `.venv/` (not committed) |
| Libraries | `requirements.txt`: google-cloud-bigquery 3.47.0, db-dtypes 1.9.0, pandas 3.1.1, matplotlib 3.11.2, pydata-google-auth 1.9.1, jupyter 1.1.1, ipykernel 7.4.0 |
| Notebook kernel | "Python (medicare-npi)", registered for VS Code and Jupyter |
| Sign-in | `notebooks/bq.py` uses `pydata-google-auth`: a browser sign-in the first time, then a saved token in the user profile. The Google Cloud CLI (`gcloud`) isn't needed |

Recreate on another PC:

```
python -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
.venv\Scripts\python.exe -m ipykernel install --user --name medicare-npi --display-name "Python (medicare-npi)"
```

Test the connection (opens the browser to sign in the first time):

```
.venv\Scripts\python.exe notebooks\bq.py
```

## Datasets and tables

### `bigquery-public-data.cms_medicare` (23 tables)

home_health_agencies_2013, home_health_agencies_2014, hospice_providers_2014, hospital_general_info, inpatient_charges_2011, inpatient_charges_2012, inpatient_charges_2013, inpatient_charges_2014, inpatient_charges_2015, nursing_facilities_2013, nursing_facilities_2014, outpatient_charges_2011, outpatient_charges_2012, outpatient_charges_2013, outpatient_charges_2014, outpatient_charges_2015, part_d_prescriber_2014, physicians_and_other_supplier_2012, physicians_and_other_supplier_2013, physicians_and_other_supplier_2014, physicians_and_other_supplier_2015, referring_durable_medical_equip_2013, referring_durable_medical_equip_2014

### `bigquery-public-data.nppes` (20 tables)

npi_optimized, npi_raw, healthcare_provider_taxonomy_code_set, and 17 versioned copies of it: healthcare_provider_taxonomy_code_set_090, _091, _100, _101, _110, _111, _120, _121, _130, _131, _140, _141, _150, _151, _160, _161, _170

## Size and freshness of the tables that matter

| Table | Rows | Size (GB) | Last modified |
|---|---:|---:|---|
| cms_medicare.physicians_and_other_supplier_2012 | 9,153,272 | 2.43 | 2018-09-21 |
| cms_medicare.physicians_and_other_supplier_2013 | 9,287,876 | 2.46 | 2018-09-22 |
| cms_medicare.physicians_and_other_supplier_2014 | 9,316,307 | 2.33 | 2018-09-22 |
| cms_medicare.physicians_and_other_supplier_2015 | 9,497,891 | 2.37 | 2018-09-22 |
| cms_medicare.part_d_prescriber_2014 | 24,120,618 | 3.78 | 2018-11-15 |
| nppes.npi_optimized | 5,943,659 | 12.48 | 2019-04-11 |
| nppes.npi_raw | 9,368,082 | 2.42 | 2026-03-31 |

`npi_optimized` is a 2019 snapshot. `npi_raw` was refreshed in March 2026 and has about 3.4 million more NPIs. Pick one deliberately before writing the reconciliation SQL.

## NPI columns and data types

NPI is `STRING` in every table that has it. No casting is needed to join.

| Table | Column | Type |
|---|---|---|
| cms_medicare.physicians_and_other_supplier_2012 to _2015 | npi | STRING |
| cms_medicare.part_d_prescriber_2014 | npi | STRING |
| cms_medicare.referring_durable_medical_equip_2013, _2014 | referring_npi | STRING |
| nppes.npi_optimized, nppes.npi_raw | npi | STRING |
| nppes.npi_optimized, nppes.npi_raw | replacement_npi | STRING |
| nppes.npi_optimized, nppes.npi_raw | npi_deactivation_reason_code | STRING |
| nppes.npi_optimized | npi_deactivation_reason_code_name | STRING |
| nppes.npi_optimized, nppes.npi_raw | npi_deactivation_date | DATE |
| nppes.npi_optimized, nppes.npi_raw | npi_reactivation_date | DATE |

## Columns: `cms_medicare.physicians_and_other_supplier_2015` (26 columns, in order)

| # | Column | Type |
|---:|---|---|
| 1 | npi | STRING |
| 2 | nppes_provider_last_org_name | STRING |
| 3 | nppes_provider_first_name | STRING |
| 4 | nppes_provider_mi | STRING |
| 5 | nppes_credentials | STRING |
| 6 | nppes_provider_gender | STRING |
| 7 | nppes_entity_code | STRING |
| 8 | nppes_provider_street1 | STRING |
| 9 | nppes_provider_street2 | STRING |
| 10 | nppes_provider_city | STRING |
| 11 | nppes_provider_zip | STRING |
| 12 | nppes_provider_state | STRING |
| 13 | nppes_provider_country | STRING |
| 14 | provider_type | STRING |
| 15 | medicare_participation_indicator | STRING |
| 16 | place_of_service | STRING |
| 17 | hcpcs_code | STRING |
| 18 | hcpcs_description | STRING |
| 19 | hcpcs_drug_indicator | STRING |
| 20 | line_srvc_cnt | FLOAT64 |
| 21 | bene_unique_cnt | INT64 |
| 22 | bene_day_srvc_cnt | INT64 |
| 23 | average_medicare_allowed_amt | FLOAT64 |
| 24 | average_submitted_chrg_amt | FLOAT64 |
| 25 | average_medicare_payment_amt | FLOAT64 |
| 26 | average_medicare_standard_amt | FLOAT64 |

The 2014 table has the same 26 columns in the same order.

The 2012 and 2013 tables have 28 columns. They lack `average_medicare_standard_amt` and add three FLOAT64 columns, each placed right after its matching average: `stdev_medicare_allowed_amt`, `stdev_submitted_chrg_amt`, `stdev_medicare_payment_amt`. A `UNION ALL` across years needs an explicit column list.

The `nppes_entity_code` column is STRING here, while `entity_type_code` in the NPPES tables is INT64. Cast one side before comparing them.

## Columns: `nppes.npi_optimized` (480 columns)

Grouped by pattern below. In the real table the numbered sets are interleaved (taxonomy_code_1, license_number_1, license_number_state_code_1, primary_taxonomy_switch_1, taxonomy_code_2, and so on). All numbered columns are STRING. The group counts add up to 480.

Identity and names:
npi STRING, entity_type_code INT64, entity_type_code_name STRING, replacement_npi STRING, employer_identification_number_ein STRING, provider_organization_name_legal_business_name STRING, provider_last_name_legal_name STRING, provider_first_name STRING, provider_middle_name STRING, provider_name_prefix_text STRING, provider_name_suffix_text STRING, provider_credential_text STRING, provider_other_organization_name STRING, provider_other_organization_name_type_code INT64, provider_other_organization_name_type_code_name STRING, provider_other_last_name STRING, provider_other_first_name STRING, provider_other_middle_name STRING, provider_other_name_prefix_text STRING, provider_other_name_suffix_text STRING, provider_other_credential_text STRING, provider_other_last_name_type_code INT64, provider_other_last_name_type_code_name STRING

Mailing address (all STRING):
provider_first_line_business_mailing_address, provider_second_line_business_mailing_address, provider_business_mailing_address_city_name, provider_business_mailing_address_state_name, provider_business_mailing_address_state_name_name, provider_business_mailing_address_postal_code, provider_business_mailing_address_country_code_if_outside_us, provider_business_mailing_address_country_code_if_outside_us_name, provider_business_mailing_address_telephone_number, provider_business_mailing_address_fax_number

Practice location (all STRING):
provider_first_line_business_practice_location_address, provider_second_line_business_practice_location_address, provider_business_practice_location_address_city_name, provider_business_practice_location_address_state_name, provider_business_practice_location_address_state_name_name, provider_business_practice_location_address_postal_code, provider_business_practice_location_address_country_code_if_outside_us, provider_business_practice_location_address_country_code_if_outside_us_name, provider_business_practice_location_address_telephone_number, provider_business_practice_location_address_fax_number

Dates and status:
provider_enumeration_date DATE, last_update_date DATE, npi_deactivation_reason_code STRING, npi_deactivation_reason_code_name STRING, npi_deactivation_date DATE, npi_reactivation_date DATE, provider_gender_code STRING, provider_gender_code_name STRING

Authorized official (all STRING):
authorized_official_last_name, authorized_official_first_name, authorized_official_middle_name, authorized_official_title_or_position, authorized_official_telephone_number, authorized_official_name_prefix_text, authorized_official_name_suffix_text, authorized_official_credential_text

Organization flags (all STRING):
is_sole_proprietor, is_sole_proprietor_name, is_organization_subpart, is_organization_subpart_name, parent_organization_lbn, parent_organization_tin

Numbered sets:

| Pattern | N range | Columns |
|---|---|---:|
| healthcare_provider_taxonomy_code_N | 1 to 15 | 15 |
| provider_license_number_N | 1 to 15 | 15 |
| provider_license_number_state_code_N | 1 to 15 | 15 |
| healthcare_provider_primary_taxonomy_switch_N | 1 to 15 | 15 |
| healthcare_provider_primary_taxonomy_switch_N_name | 1 to 15 | 15 |
| healthcare_provider_taxonomy_group_N | 1 to 15 | 15 |
| healthcare_provider_taxonomy_N_classification | 1 to 15 | 15 |
| healthcare_provider_taxonomy_N_definition | 1 to 15 | 15 |
| healthcare_provider_taxonomy_N_grouping | 1 to 15 | 15 |
| healthcare_provider_taxonomy_N_notes | 1 to 15 | 15 |
| healthcare_provider_taxonomy_N_specialization | 1 to 15 | 15 |
| other_provider_identifier_N | 1 to 50 | 50 |
| other_provider_identifier_type_code_N | 1 to 50 | 50 |
| other_provider_identifier_type_code_N_name | 1 to 50 | 50 |
| other_provider_identifier_state_N | 1 to 50 | 50 |
| other_provider_identifier_issuer_N | 1 to 50 | 50 |

## Columns: `nppes.npi_raw` (330 columns)

329 columns have the same names and types as in `npi_optimized`. The one extra column is `certification_date DATE` (column 330).

`npi_optimized` has 151 columns that `npi_raw` lacks: the `_name` label columns (such as `entity_type_code_name`, `provider_gender_code_name`, `other_provider_identifier_type_code_N_name`) and the taxonomy description sets (`healthcare_provider_taxonomy_N_classification`, `_definition`, `_grouping`, `_notes`, `_specialization`). With `npi_raw`, those labels have to come from a join to `nppes.healthcare_provider_taxonomy_code_set`.

## Taxonomy lookup (`nppes.healthcare_provider_taxonomy_code_set`)

Checked 2026-11-21 with `sql/02a_taxonomy_metadata.sql`. Raw output in `results/02a_*.json`.

Columns (all STRING, same in every copy): `code`, `grouping`, `classification`, `specialization`, `definition`, `notes`. `grouping` is a reserved word in BigQuery and must be written `` `grouping` ``.

| Table | Codes | Last modified |
|---|---:|---|
| healthcare_provider_taxonomy_code_set (unversioned) | 853 | 2020-03-25 |
| _170 (newest dated copy) | 851 | 2017-09-13 |
| _090 (oldest) | 809 | 2017-09-13 |

**Chosen: the unversioned table.** It has the most codes and is the newest. It's still from 2020 while `npi_raw` is from 2026, so codes added after 2020 will have no name; `02d` counts them.

## Test queries run

Figures come from `region-us.INFORMATION_SCHEMA.JOBS_BY_USER` for this project. MB here means MiB, the unit the console uses.

| Query | Processed | Billed |
|---|---:|---:|
| List tables in both datasets (INFORMATION_SCHEMA.TABLES) | 20 MB | 10 MB |
| Column names and types, physician tables and npi_optimized (INFORMATION_SCHEMA.COLUMNS) | 20 MB | 10 MB |
| Every column with "npi" in its name, both datasets | 20 MB | 10 MB |
| Row counts and sizes (`__TABLES__`) | 0 B | 0 B |
| Column names and types, npi_raw | 10 MB | 10 MB |
| 10-row sample join, physicians 2015 to npi_optimized on npi | 703.9 MB | 244.0 MB |
| Lookup of one NPI in npi_optimized and npi_raw | 504.6 MB | 505.0 MB |
| Total | 1,278.5 MB | 789.0 MB |

Billed total is about 0.08% of the 1 TiB monthly allowance. The job-history check itself was estimated at 0 B.

Each INFORMATION_SCHEMA query was billed 10 MB regardless of whether it read one dataset or two. The console's pre-run estimate shows bytes processed, which can be higher than bytes billed, as the sample join shows.

### Sample join

```sql
SELECT p.npi, p.nppes_provider_last_org_name, p.nppes_provider_state, p.provider_type, p.hcpcs_code,
       n.provider_last_name_legal_name, n.provider_organization_name_legal_business_name,
       n.provider_business_practice_location_address_state_name, n.healthcare_provider_taxonomy_code_1
FROM `bigquery-public-data.cms_medicare.physicians_and_other_supplier_2015` AS p
JOIN `bigquery-public-data.nppes.npi_optimized` AS n
  ON p.npi = n.npi
LIMIT 10
```

The join ran without casting. All 10 rows were NPI 1265411862 (MOYSAENKO, OH, Internal Medicine) with different HCPCS codes, and every NPPES-side column came back as an empty string.

A follow-up lookup showed why. NPPES records this NPI as deactivated on 2017-02-14, and a deactivated record keeps only the NPI and the deactivation date:

| Source | npi | entity_type_code | provider_last_name_legal_name | npi_deactivation_date | last_update_date |
|---|---|---|---|---|---|
| npi_optimized | 1265411862 | NULL | `''` (empty string) | 2017-02-14 | NULL |
| npi_raw | 1265411862 | NULL | NULL | 2017-02-14 | NULL |

## Notes for the project SQL

1. Join on `npi` directly. Both sides are STRING.
2. A matched NPI is not necessarily an active provider. Check `npi_deactivation_date` and `npi_reactivation_date` before treating a match as valid.
3. On the row checked, `npi_optimized` stored a blank name as `''` while `npi_raw` stored `NULL`. Wrap NPPES text columns in `NULLIF(col, '')` so blank and missing are treated the same.
4. The Medicare physician data covers 2012 to 2015. `npi_optimized` is from 2019 and `npi_raw` from 2026, so neither matches the Medicare years exactly.
5. Select only the columns you need. `npi_optimized` is 12.48 GB across 480 columns, and BigQuery bills by columns scanned.
