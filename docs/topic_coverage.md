# Topic coverage: where each data engineering topic lives in this project

## Data engineering topics

| Topic | Implementation | Files |
|---|---|---|
| Medallion architecture | bronze → staging → silver (+ quarantine) → gold; snapshots; audit | `dbt/models/*`, `sql/` |
| OLTP vs OLAP, dimensional modeling | Normalized silver; gold star schema (facts and dimensions) | `dbt/models/gold/` |
| Star schema | `fct_claim`, `dim_member`, `dim_date`, marts | `dbt/models/gold/` |
| **SCD Type 2** | dbt snapshot (check strategy, business-dated versions), `dim_member_history`, replay backfill | `dbt/snapshots/member_history.yml`, `scripts/replay_member_history.sh` |
| SQL window functions, CTEs | X12 loop context (running counts), MPI ranking (`row_number`, `lead`), gaps-and-islands stays | `stg_x12__*`, `mpi_link`, `fct_inpatient_stay` |
| Python OOP | Value object, abstract base class, two transports, client, loader (single responsibility, dependency injection); X12 `Builder` | `ingestion/nppes/load_bronze_nppes.py`, `edi/generate_837p.py` |
| Config-driven pipeline | FHIR loader driven by YAML | `ingestion/fhir/fhir_sources.yaml` |
| **API ingestion** | CMS NPPES NPI Registry: rate limit, retries with backoff, raw JSON in bronze | `ingestion/nppes/` |
| Modular ETL (extract / transform / load) | Loaders (E/L), dbt (T), generators (outbound) | `ingestion/`, `edi/`, `hl7/`, `dbt/` |
| Idempotent loads and upserts | SHA-256 file manifest, delete+insert per file, `ON CONFLICT` upserts | every loader |
| **Watermark incremental loading** | dbt incremental model (`_loaded_at` watermark); Python watermark table | `hl7_adt_event.sql`, `audit.etl_watermark` |
| Declarative vs imperative | dbt models and tests (declarative); Python loaders and generators (imperative) | |
| Orchestration | Airflow 3 DAG, 15 tasks, dependencies and retries | `orchestration/dags/coastal_care_daily.py` |
| Cron scheduling | `schedule="15 2 * * *"` | DAG |
| **Docker-based Airflow** | Compose: Airflow + metadata Postgres, separate tool venv | `docker-compose.yml`, `docker/airflow/Dockerfile` |
| Logging and retry | Python logging; HTTP retries with backoff; Airflow retries | |
| Automated data quality gates | About 175 dbt tests; failures stop downstream tasks | `dbt/tests/`, `schema.yml` |
| Reconciliation | Row, control-total and dollar reconciliation in every loader and layer | loaders, `assert_*` tests |
| Data governance | Crosswalk approvals (PROPOSED / APPROVED / REJECTED), HIPAA roles, masked views, findings log | `security/`, `docs/` |
| CI/CD | GitHub Actions with a Postgres service and a synthetic fixture | `.github/workflows/ci.yml`, `ci/` |
| PostgreSQL | All storage; roles and grants | |

## Healthcare topics
| Topic | Files |
|---|---|
| ETL / data conversion | ICD-9 → ICD-10 GEMs, SNOMED → ICD-10 crosswalk |
| Source-to-target mapping | `docs/mapping/` |
| HIPAA | `security/`, dbt grants, de-identified gold |
| HL7 v2 and FHIR R4 | `hl7/`, `ingestion/fhir/` |
| EDI 837P / 835 / 834 | `edi/` |
| HCPCS/CPT, ICD-10 | `ref` schema, `code_exception` |
