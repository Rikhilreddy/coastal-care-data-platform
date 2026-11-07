#!/usr/bin/env bash
# CI-1: rebuild and prove the whole platform from a synthetic fixture, end to end.
#   restore bronze/ref/audit fixture -> HIPAA roles -> dbt build (all tests)
#   -> access checks -> 837P out -> pyx12 -> 837P in -> 835 out -> pyx12 -> 835 in
#   -> ADT out -> python-hl7 -> ADT in (twice: idempotent) -> 834 out -> pyx12 -> 834 in
#   -> dbt build again (834 round trip, MPI on both feeds, member months).
# Any broken rule stops the run with a non-zero exit, so the pull request shows red.
# Uses only synthetic data (ci/fixtures). Run from the project root.
set -euo pipefail
export PG_HOST="${PG_HOST:-localhost}" PG_PORT="${PG_PORT:-5432}" PG_DB="${PG_DB:-coastal_care}"
export PGHOST="$PG_HOST" PGPORT="$PG_PORT" PGUSER="$PG_USER" PGPASSWORD="${PG_PASSWORD:-}" PGDATABASE="$PG_DB"
export DBT_PROFILES_DIR="$PWD/dbt"
step () { echo; echo "=== $*"; }
dbt_build () { (cd dbt && dbt build ${DBT_BUILD_ARGS:-} 2>&1 | tee /tmp/dbt.log | grep -E "ERROR|FAIL|Done" ; ! grep -qE "ERROR=[1-9]" /tmp/dbt.log); }
x12_check () {   # pyx12 exits 1 on a known 999-writer bug, so judge by its verdict line
    local bad=0
    while IFS= read -r f; do out=$(x12valid "$f" 2>&1 || true); grep -q ": OK$" <<< "$out" || { echo "INVALID $f"; echo "$out" | head -5; bad=1; }; done < <(find "$1" -name "*.x12")
    echo "$(find "$1" -name '*.x12' | wc -l) files checked by pyx12"; return $bad
}

step "1. restore synthetic fixture (bronze, ref, audit)"
psql -d postgres -qc "DROP DATABASE IF EXISTS $PG_DB" -c "CREATE DATABASE $PG_DB"
pg_restore --no-owner --no-privileges -d "$PG_DB" ci/fixtures/coastal_care_fixture.dump
rm -rf data/edi/outbound data/hl7/outbound

step "2. HIPAA roles"
psql -q -v ON_ERROR_STOP=1 -f security/10_roles_and_access.sql

step "2b. enrollment history (Synthea CSV fixture) -> bronze, twice (second run must skip)"
python ingestion/synthea_csv/load_bronze_enrollment.py --dir ci/fixtures/synthea_csv
python ingestion/synthea_csv/load_bronze_enrollment.py --dir ci/fixtures/synthea_csv | grep -q "SUCCESS 0 .*FAILED 0" \
    || { echo "second enrollment load was not idempotent"; exit 1; }

step "3. dbt build (models + data tests + unit tests; snapshot waits for enrollment)"
DBT_BUILD_ARGS="--exclude member_history+" dbt_build

step "3b. API ingestion: NPPES NPI registry (offline fixture), twice (second run: nothing new)"
python ingestion/nppes/load_bronze_nppes.py --fixture ci/fixtures/nppes_responses.json
python ingestion/nppes/load_bronze_nppes.py --fixture ci/fixtures/nppes_responses.json | grep -q "candidates=0" \
    || { echo "NPPES watermark did not prevent re-checking"; exit 1; }

step "4. access control proof"
./security/check_access.sh

step "5. 837P outbound -> validate -> inbound"
python edi/generate_837p.py
x12_check data/edi/outbound/837P
python edi/load_bronze_x12.py --dir data/edi/outbound/837P

step "6. 835 outbound -> validate -> inbound"
dbt_build
python edi/generate_835.py
x12_check data/edi/outbound/835
python edi/load_bronze_x12.py --dir data/edi/outbound/835

step "7. HL7 ADT outbound -> validate -> inbound (twice: second run must skip)"
python hl7/generate_adt.py
python - <<'PY'
import glob, hl7
n = 0
for f in glob.glob("data/hl7/outbound/adt/*.hl7"):
    for m in open(f, newline="").read().split("\n"):
        msg = hl7.parse(m); n += 1
        assert str(msg.segment("MSH")[12]) == "2.5.1", f
print(n, "ADT messages parsed by python-hl7")
PY
python hl7/load_bronze_hl7.py --dir data/hl7/outbound/adt
python hl7/load_bronze_hl7.py --dir data/hl7/outbound/adt | grep -q "SUCCESS 0 .*FAILED 0" \
    || { echo "second HL7 load was not idempotent"; exit 1; }

step "7b. 834 enrollment outbound -> validate -> inbound"
python edi/generate_834.py --from 2016-01
x12_check data/edi/outbound/834
python edi/load_bronze_x12.py --dir data/edi/outbound/834

step "7c. SCD-2: replay member history 2017-2025, then prove versions exist"
dbt build --project-dir dbt --profiles-dir dbt -s +member_enrollment --exclude member_history+ >/dev/null
./scripts/replay_member_history.sh 2017 2025
psql -qtAc "select count(*) from snapshots.member_history group by member_key having count(*) > 1 limit 1" | grep -q . \
    || { echo "SCD-2 history has no member with more than one version"; exit 1; }

step "8. dbt build on the round-tripped data (incremental models take only new rows)"
dbt_build
psql -c "select * from mpi.mpi_match_quality"
grep -q "assert_835_pending_claims.*PASS" /tmp/dbt.log || { echo "claims left without a 835"; exit 1; }
echo; echo "CI PASSED"
