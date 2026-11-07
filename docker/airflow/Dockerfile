# ORCH-2: Airflow 3 in Docker for the Coastal Care DAG.
# Airflow and the project's tools live in SEPARATE Python environments: dbt and the pipeline
# libraries go into /opt/coastal-venv so their versions never fight Airflow's pinned ones.
FROM apache/airflow:3.1.8-python3.11

USER root
RUN apt-get update -q && apt-get install -yq --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/*
RUN python -m venv /opt/coastal-venv && chown -R airflow: /opt/coastal-venv
USER airflow

COPY ci/requirements-ci.txt /tmp/requirements-coastal.txt
RUN /opt/coastal-venv/bin/pip install --no-cache-dir -r /tmp/requirements-coastal.txt
