"""
Coastal Care Data Platform: daily pipeline (Apache Airflow 3, open source).   ORCH-1

Order matters and is enforced by the task graph:

  load_fhir       ─┐
  load_enrollment ─┤
  load_x12        ─┼─> dbt_build ─> access_check ─> generate_837p ─> load_837p_roundtrip ─┐
  load_hl7        ─┘           └──> generate_834 ─> load_834 ─────────────────────────────┤
                  dbt_build_final <─ load_835 <─ generate_835 <─ dbt_build_edi <──────────┘

* Bronze loaders are idempotent (SHA-256 manifest): a retry or a re-run never duplicates rows.
* dbt build runs models AND tests together, so a failed reconciliation stops everything
  downstream: no 837 is generated from data that did not reconcile.
* Credentials come from the environment (.env / Airflow connection), never from this file.
* DE-SynPUF and the CMS reference sets are static releases, loaded once, not daily.
* load_nppes_registry calls a free public API (NPPES): rate-limited, retried, watermarked.
* Runs locally (`airflow dags test`) or in Docker (docker-compose.yml at the project root).

Local run (no scheduler needed):
    export COASTAL_HOME=$PWD AIRFLOW__CORE__DAGS_FOLDER=$PWD/orchestration/dags
    airflow dags test coastal_care_daily 2026-11-03
"""
from __future__ import annotations

import os
from datetime import datetime, timedelta

from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

HOME = os.environ.get("COASTAL_HOME", "/opt/coastal_care")
PY = os.environ.get("COASTAL_PYTHON", "python")
DBT = f"cd {HOME}/dbt && DBT_PROFILES_DIR={HOME}/dbt {os.environ.get('COASTAL_DBT', 'dbt')}"


def sh(cmd: str) -> str:
    """Every task runs from the project root. Locally the project's .env supplies the database
    settings; in Docker, docker-compose.yml supplies them (PG_HOST must stay host.docker.internal,
    so .env is NOT re-read there, or it would point back to the container's own localhost)."""
    load_env = "" if os.environ.get("COASTAL_IN_DOCKER") else "if [ -f .env ]; then set -a; . ./.env; set +a; fi; "
    return f"set -euo pipefail; cd {HOME}; {load_env}{cmd}"


def when(test: str, cmd: str, skipped: str) -> str:
    """Run cmd only if test passes. Unlike `test && cmd || echo`, a FAILING cmd still fails the task."""
    return f"if {test}; then {cmd}; else echo '{skipped}'; fi"


with DAG(
    dag_id="coastal_care_daily",
    description="Bronze loads -> dbt build + tests -> HIPAA access check -> 837P/835 EDI",
    schedule="15 2 * * *",                        # 02:15 daily, after the overnight file drops
    start_date=datetime(2026, 11, 1),
    catchup=False,
    max_active_runs=1,                            # never two runs writing bronze at once
    default_args={"retries": int(os.environ.get("COASTAL_RETRIES", "2")), "retry_delay": timedelta(minutes=5), "owner": "data-engineering"},
    tags=["healthcare", "hipaa", "edi", "fhir", "hl7"],
) as dag:
    load_fhir = BashOperator(task_id="load_fhir",
                             bash_command=sh(when("ls data/source/synthea/fhir/*.json >/dev/null 2>&1",
                                                   f"{PY} ingestion/fhir/load_bronze_fhir.py", "no FHIR bundles today")))
    load_enrollment = BashOperator(task_id="load_enrollment", bash_command=sh(
        when("[ -f data/source/synthea/csv/payer_transitions.csv ]",
             f"{PY} ingestion/synthea_csv/load_bronze_enrollment.py", "no enrollment export today")))
    load_x12 = BashOperator(task_id="load_x12_inbound",
                            bash_command=sh(when("[ -d data/edi/inbound ]",
                                                 f"{PY} edi/load_bronze_x12.py --dir data/edi/inbound", "no inbound X12 today")))
    load_hl7 = BashOperator(task_id="load_hl7_inbound",
                            bash_command=sh(when("[ -d data/hl7/inbound ]",
                                                 f"{PY} hl7/load_bronze_hl7.py --dir data/hl7/inbound", "no inbound HL7 today")))

    dbt_build = BashOperator(task_id="dbt_build", bash_command=sh(f"{DBT} build"))
    # API-1: verify provider NPIs against the CMS NPPES registry (incremental by watermark)
    load_nppes = BashOperator(task_id="load_nppes_registry",
                              bash_command=sh(f"{PY} ingestion/nppes/load_bronze_nppes.py --limit 200"))
    access_check = BashOperator(task_id="hipaa_access_check", bash_command=sh("bash security/check_access.sh && echo access-ok"))
    # (a bash_command ending in .sh is treated by Airflow as a template FILE, hence the echo)

    # Claims window: service months from 45 days back (late claims), or the month given in the
    # run conf for a backfill:  airflow dags test coastal_care_daily -c '{"from_month": "2017-01"}'
    window = "{{ dag_run.conf.get('from_month') or macros.ds_add(ds, -45)[:7] }}"
    generate_837p = BashOperator(task_id="generate_837p",
                                 bash_command=sh(f"{PY} edi/generate_837p.py --from {window}"))
    load_837p = BashOperator(task_id="load_837p_roundtrip", bash_command=sh(
        when("ls data/edi/outbound/837P/*/*.x12 >/dev/null 2>&1",
             f"{PY} edi/load_bronze_x12.py --dir data/edi/outbound/837P", "no 837P files in window")))
    dbt_build_edi = BashOperator(task_id="dbt_build_edi", bash_command=sh(f"{DBT} build -s path:models/edi"))
    generate_835 = BashOperator(task_id="generate_835", bash_command=sh(f"{PY} edi/generate_835.py --from {window}"))
    load_835 = BashOperator(task_id="load_835", bash_command=sh(
        when("ls data/edi/outbound/835/*/*.x12 >/dev/null 2>&1",
             f"{PY} edi/load_bronze_x12.py --dir data/edi/outbound/835", "no 835 files in window")))
    dbt_build_final = BashOperator(task_id="dbt_build_final", bash_command=sh(f"{DBT} build"))
    generate_834 = BashOperator(task_id="generate_834", bash_command=sh(f"{PY} edi/generate_834.py --from 2016-01"))
    load_834 = BashOperator(task_id="load_834", bash_command=sh(
        when("ls data/edi/outbound/834/*.x12 >/dev/null 2>&1",
             f"{PY} edi/load_bronze_x12.py --dir data/edi/outbound/834", "no 834 files")))

    [load_fhir, load_enrollment, load_x12, load_hl7] >> dbt_build >> access_check >> generate_837p >> load_837p
    access_check >> generate_834 >> load_834 >> dbt_build_edi
    dbt_build >> load_nppes >> dbt_build_final
    load_837p >> dbt_build_edi >> generate_835 >> load_835 >> dbt_build_final
