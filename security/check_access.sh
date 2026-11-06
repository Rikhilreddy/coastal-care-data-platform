#!/usr/bin/env bash
# SEC-1 proof: each role can read what it needs and is DENIED what it must not see.
# Uses SET ROLE inside one session as the database owner (no passwords needed).
# Exit code 1 if any rule is broken, so CI can run it.
set -u
DB="${PG_DB:-coastal_care}"
fail=0
check () {   # role  table  expected(ALLOW|DENY)
    if psql -d "$DB" -qAt -v ON_ERROR_STOP=1 -c "SET ROLE $1; SELECT 1 FROM $2 LIMIT 1;" >/dev/null 2>&1; then got=ALLOW; else got=DENY; fi
    if [ "$got" = "$3" ]; then echo "ok    $1  $3  $2"; else echo "FAIL  $1  expected $3 got $got  $2"; fail=1; fi
}
check cc_analyst  gold.fct_claim                     ALLOW
check cc_analyst  silver.claim_header                DENY
check cc_analyst  silver.member_identity             DENY
check cc_analyst  mpi.mpi_link                       DENY
check cc_engineer silver.claim_header                ALLOW
check cc_engineer silver.member_identity             DENY
check cc_engineer silver.member_identity_masked      ALLOW
check cc_engineer bronze.fhir_resource               DENY
check cc_engineer bronze.hl7_segment                 DENY
check cc_engineer audit.mpi_test_truth               DENY
check cc_steward  silver.member_identity             ALLOW
check cc_steward  mpi.mpi_link                       ALLOW
check cc_engineer hl7.hl7_adt_event                  DENY
check cc_engineer staging.stg_fhir__patient          DENY
check cc_engineer staging.stg_x12__837p_segment      DENY
check cc_engineer gold.mart_pmpm                     ALLOW
check cc_auditor  audit.load_manifest                ALLOW
check cc_auditor  gold.fct_claim                     DENY
exit $fail
