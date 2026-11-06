-- SEC-1: HIPAA access control (minimum necessary), role-based, enforced by PostgreSQL.
-- Run ONCE as the database owner BEFORE `dbt build` (dbt grants need the roles to exist):
--   psql -d coastal_care -f security/10_roles_and_access.sql
-- Re-runnable. Roles are NOLOGIN groups; people get a LOGIN role that is a member of one group.
--
--   cc_analyst    gold only: de-identified star schema and marts
--   cc_steward    + MPI and the restricted identity table (data stewards resolving REVIEW matches)
--   cc_engineer   + bronze, staging, silver, quarantine, edi, hl7 (builds and debugs pipelines), no identities
--   cc_auditor    audit schema only (load manifests, approvals): proves who loaded what, when
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cc_analyst')  THEN CREATE ROLE cc_analyst  NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cc_steward')  THEN CREATE ROLE cc_steward  NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cc_engineer') THEN CREATE ROLE cc_engineer NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cc_auditor')  THEN CREATE ROLE cc_auditor  NOLOGIN; END IF;
END $$;

-- Nobody gets anything by default.
DO $$ BEGIN
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO cc_analyst, cc_steward, cc_engineer, cc_auditor', current_database());
END $$;
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Analysts: gold only.
CREATE SCHEMA IF NOT EXISTS gold;
GRANT USAGE ON SCHEMA gold TO cc_analyst, cc_steward, cc_engineer;

-- Table-level SELECT grants on dbt models are applied BY DBT on every build (dbt_project.yml
-- +grants), because dbt rebuilds tables and a rebuilt table loses manual grants.
-- Identifier-bearing models (member_identity, stg_fhir__patient, hl7_adt_event, raw X12
-- segments, inbound 837 claims) are granted to cc_steward only; engineers get
-- silver.member_identity_masked instead. This script creates roles and schema access only.
DO $$
DECLARE s text;
BEGIN
    FOREACH s IN ARRAY ARRAY['staging', 'silver', 'quarantine', 'edi', 'hl7', 'ref'] LOOP
        EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', s);     -- dbt fills them later
        EXECUTE format('GRANT USAGE ON SCHEMA %I TO cc_engineer, cc_steward', s);
    END LOOP;
    GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cc_engineer;        -- code sets: not PHI
END $$;
-- bronze holds FHIR/HL7/X12 exactly as received, identifiers included: loaders only (owner).
REVOKE ALL ON ALL TABLES IN SCHEMA bronze FROM cc_engineer, cc_analyst;

-- Stewards: the identity table and the MPI.
CREATE SCHEMA IF NOT EXISTS mpi;
GRANT USAGE ON SCHEMA mpi TO cc_steward;

-- Auditors: the audit trail only.
CREATE SCHEMA IF NOT EXISTS audit;
GRANT USAGE ON SCHEMA audit TO cc_auditor;
GRANT SELECT ON ALL TABLES IN SCHEMA audit TO cc_auditor;
ALTER DEFAULT PRIVILEGES IN SCHEMA audit GRANT SELECT ON TABLES TO cc_auditor;
-- The MPI answer key is test data about identities: stewards and auditors only.
DO $$ BEGIN
    IF to_regclass('audit.mpi_test_truth') IS NOT NULL THEN
        REVOKE ALL ON audit.mpi_test_truth FROM cc_engineer, cc_analyst;
    END IF;
END $$;
