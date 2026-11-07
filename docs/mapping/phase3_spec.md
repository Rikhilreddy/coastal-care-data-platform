# Phase 3: SCD Type 2, incremental loading, API ingestion, Docker Airflow

## SCD-2: member history (`dbt/snapshots/member_history.yml`)
| Piece | What it does |
|---|---|
| `silver.member_attributes_asof` (ephemeral) | A member's tracked attributes on a date: city, state, ZIP3 and the plan enrolled on that date (from the 834). Street address and full ZIP are excluded (HIPAA minimum necessary) |
| Snapshot `snapshots.member_history` | dbt **check** strategy on those columns. When one changes, the current row is closed (`dbt_valid_to`) and a new version opens. `updated_at = as_of_ts`, so versions carry business dates, not run times |
| `gold.dim_member_history` | The SCD-2 dimension: `valid_from`, `valid_to`, `is_current`, `version` |
| `scripts/replay_member_history.sh` | Backfill: replays Jan 1 of each year (snapshots only move forward) |
| `assert_member_history_scd2` | Exactly one current version per member; versions never overlap or leave gaps |

**Point-in-time join** (what was true on the claim date):
```sql
join gold.dim_member_history h
  on h.member_key = f.member_key
 and f.service_date >= h.valid_from
 and f.service_date <  coalesce(h.valid_to, '9999-12-31')
```
Test fixture result: 422 members, 1,552 versions, an average of 3.68 per member. Example member: MEDICARE → NOT ENROLLED → DUAL ELIGIBLE → MEDICAID → CIGNA HEALTH.

## Incremental loading with a watermark
**1. dbt: `hl7.hl7_adt_event` is `materialized='incremental'`**
- **Watermark:** `_loaded_at > max(_loaded_at)` already in the table.
- **`unique_key = message_control_id`** with `delete+insert`: a file the hospital re-sends replaces its own messages.
- **Proof:**
  - The second run inserts 0 rows.
  - Re-sending one file reprocesses exactly its 12 messages.
  - `assert_adt_incremental_complete` checks bronze = table, with nothing missed and nothing left over.
- `--full-refresh` rebuilds from scratch.

**2. Python: NPPES loader.** `audit.etl_watermark` stores the load time of the newest claim batch already fully processed.
- A run checks only NPIs on claim batches loaded after the watermark, plus NPIs never checked.
- The watermark moves only when that work is fully done, so a run cut short by `--limit` or an outage resumes where it stopped.

## API ingestion: CMS NPPES NPI Registry (`ingestion/nppes/load_bronze_nppes.py`)
The API is free, public and needs no key. One class per job:

| Class | Responsibility |
|---|---|
| `NPI` | Value object: format (10 digits, starts with 1 or 2) and Luhn check digit with prefix 80840, no network |
| `Transport` (abstract) | "Get the JSON for an NPI" |
| `HttpTransport` | The real API: timeout, rate limit of 3 requests per second, retries with exponential backoff on 429 and 5xx |
| `FixtureTransport` | Canned responses for CI and offline tests (dependency injection) |
| `NppesClient` | Turns a response into `FOUND` / `NOT_FOUND` / `API_ERROR`. Malformed NPIs and NPIs failing the check digit are recorded **without** calling the API |
| `NppesLoader` | Selects the work (watermark), calls the client, writes bronze and the watermark in one transaction |

- **Flow:** `bronze.nppes_npi_lookup` (raw JSON as returned) → `silver.provider_registry` (latest answer per NPI: name, entity type, status, primary taxonomy) → `gold.mart_data_quality`.
- **Findings:**
  - Synthea's rendering NPIs (`9999…`) are reported as `INVALID_FORMAT`, because real NPIs start with 1 or 2. This closes H33 with evidence.

## Docker Airflow (`docker-compose.yml`, `docker/airflow/Dockerfile`)
- **Image:** Airflow 3.1.8 plus a **separate venv** (`/opt/coastal-venv`) for dbt and the pipeline libraries, so their versions never conflict with Airflow's.
- **Services:**
  - `airflow-db`: Postgres 16, for Airflow's own metadata.
  - `airflow`: `standalone` with LocalExecutor, UI on http://localhost:8080.
- **Project data:** stays in the host Postgres, reached at `host.docker.internal` with the credentials from `.env`.
- **Mount:** the project is mounted, so DAG edits are live.
- **`.dockerignore`:** `data/`, `.env` and `.git` never enter an image.
- **DAG:** now 15 tasks, adding `load_nppes_registry`. All 15 succeeded in `airflow dags test`.

## CI additions (`ci/run_ci.sh`)
| Step | Proves |
|---|---|
| 3b | The NPPES loader runs twice offline; the second run must find 0 candidates (watermark) |
| 7c | Member history replays 2017–2025; at least one member must have several versions (SCD-2) |
| 8 | The final build runs the incremental model on new rows only, then the completeness test |
