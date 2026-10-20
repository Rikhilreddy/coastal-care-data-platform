-- Coastal Care Data Platform: reference (code set) tables
-- Safe to rerun (idempotent).

-- ICD-10-CM code set (FY2027 order file). Includes non-billable header codes.
CREATE TABLE IF NOT EXISTS ref.icd10cm (
    icd10_code        TEXT     PRIMARY KEY,
    order_number      INTEGER  NOT NULL,
    is_billable       BOOLEAN  NOT NULL,
    short_desc        TEXT,
    long_desc         TEXT,
    code_set_version  TEXT     NOT NULL
);

-- CMS 2018 diagnosis GEM, forward direction (ICD-9-CM -> ICD-10-CM).
CREATE TABLE IF NOT EXISTS ref.gem_icd9_to_icd10 (
    icd9_code    TEXT      NOT NULL,
    icd10_code   TEXT,                -- NULL when no_map = true (source value 'NoDx')
    flags        CHAR(5)   NOT NULL,
    approximate  BOOLEAN   NOT NULL,
    no_map       BOOLEAN   NOT NULL,
    combination  BOOLEAN   NOT NULL,
    scenario     SMALLINT  NOT NULL,
    choice_list  SMALLINT  NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_gem_fwd_icd9 ON ref.gem_icd9_to_icd10 (icd9_code);

-- CMS 2018 diagnosis GEM, backward direction (ICD-10-CM -> ICD-9-CM).
-- Used for the reciprocal-match tie-break in the conversion spec.
CREATE TABLE IF NOT EXISTS ref.gem_icd10_to_icd9 (
    icd10_code   TEXT      NOT NULL,
    icd9_code    TEXT,                -- NULL when no_map = true
    flags        CHAR(5)   NOT NULL,
    approximate  BOOLEAN   NOT NULL,
    no_map       BOOLEAN   NOT NULL,
    combination  BOOLEAN   NOT NULL,
    scenario     SMALLINT  NOT NULL,
    choice_list  SMALLINT  NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_gem_bwd_icd10 ON ref.gem_icd10_to_icd9 (icd10_code);
CREATE INDEX IF NOT EXISTS ix_gem_bwd_icd9  ON ref.gem_icd10_to_icd9 (icd9_code);

-- ICD-9-CM diagnosis descriptions (CMS version 32, final release, Oct 2014).
-- Used for description similarity in the ICD-9 -> ICD-10 conversion.
CREATE TABLE IF NOT EXISTS ref.icd9cm (
    icd9_code         TEXT  PRIMARY KEY,
    long_desc         TEXT  NOT NULL,
    code_set_version  TEXT  NOT NULL
);

-- SME-reviewed conversion overrides (source: dbt/seeds/icd9_dx_overrides.csv).
-- Only APPROVED rows change conversion results.
CREATE TABLE IF NOT EXISTS ref.icd9_dx_override (
    icd9_code      TEXT  PRIMARY KEY,
    icd10_code     TEXT  NOT NULL,
    review_status  TEXT  NOT NULL CHECK (review_status IN ('PROPOSED', 'APPROVED', 'REJECTED')),
    rationale      TEXT  NOT NULL,
    reviewed_by    TEXT,
    review_date    DATE
);

-- HCPCS Level II codes (CMS quarterly alpha-numeric file).
-- Level I (CPT) codes are AMA-licensed and are not part of this file.
CREATE TABLE IF NOT EXISTS ref.hcpcs (
    hcpcs_code             TEXT  PRIMARY KEY,
    short_desc             TEXT,
    long_desc              TEXT,
    add_date               DATE,
    action_effective_date  DATE,
    termination_date       DATE,
    code_set_version       TEXT  NOT NULL
);
