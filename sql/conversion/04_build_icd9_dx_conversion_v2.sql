-- Coastal Care Data Platform: ICD-9-CM -> ICD-10-CM diagnosis conversion, v2
-- Implements docs/mapping/icd9_to_icd10_conversion_spec.md v2.
-- Changes from v1:
--   * R0  SME overrides (ref.icd9_dx_override, APPROVED rows only) win over every rule
--   * R1b Parent fallback: a code missing from GEMs maps via its residual child (...0, then ...9)
--   * Tie-break: valid FY2027 > billable > description similarity > reciprocal > lowest code
--     (the v1 "unspecified" keyword rule is removed)
--   * Regression report: every decision that changed versus the previous run
-- Outputs: ref.icd9_dx_conversion, silver.dx_conversion_detail, ref.icd9_dx_conversion_prev
-- Safe to rerun (full rebuild in one transaction).
--
-- Run: psql coastal_care -f sql/conversion/04_build_icd9_dx_conversion_v2.sql | tee docs/mapping/conversion_quality_report_v2.txt

\set ON_ERROR_STOP on
\pset footer off
\timing off

CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- trigram similarity for description matching

BEGIN;

-- 0. Keep the previous run for the regression comparison.
DROP TABLE IF EXISTS ref.icd9_dx_conversion_prev;
CREATE TABLE ref.icd9_dx_conversion_prev (icd9_code TEXT PRIMARY KEY, icd10_code TEXT,
                                          gem_match_type TEXT, decided_by TEXT);
DO $$
BEGIN
    IF to_regclass('ref.icd9_dx_conversion') IS NOT NULL THEN
        INSERT INTO ref.icd9_dx_conversion_prev
        SELECT icd9_code, icd10_code, gem_match_type, decided_by FROM ref.icd9_dx_conversion;
    END IF;
END $$;

DROP TABLE IF EXISTS ref.icd9_dx_conversion;
DROP TABLE IF EXISTS silver.dx_conversion_detail;

-- 1. Every format-valid ICD-9 diagnosis code used in legacy claims, with usage counts.
CREATE TEMP TABLE tmp_dx_usage ON COMMIT DROP AS
WITH claims AS (
    SELECT segment, admtng_icd9_dgns_cd AS a,
           icd9_dgns_cd_1 AS d1, icd9_dgns_cd_2 AS d2, icd9_dgns_cd_3 AS d3, icd9_dgns_cd_4 AS d4,
           icd9_dgns_cd_5 AS d5, icd9_dgns_cd_6 AS d6, icd9_dgns_cd_7 AS d7, icd9_dgns_cd_8 AS d8,
           icd9_dgns_cd_9 AS d9, icd9_dgns_cd_10 AS d10
    FROM bronze.desynpuf_inpatient
    UNION ALL
    SELECT segment, admtng_icd9_dgns_cd,
           icd9_dgns_cd_1, icd9_dgns_cd_2, icd9_dgns_cd_3, icd9_dgns_cd_4, icd9_dgns_cd_5,
           icd9_dgns_cd_6, icd9_dgns_cd_7, icd9_dgns_cd_8, icd9_dgns_cd_9, icd9_dgns_cd_10
    FROM bronze.desynpuf_outpatient
), dx AS (
    SELECT c.segment, v.pos, btrim(v.code) AS code
    FROM claims c
    CROSS JOIN LATERAL (VALUES (0, c.a), (1, c.d1), (2, c.d2), (3, c.d3), (4, c.d4), (5, c.d5),
                               (6, c.d6), (7, c.d7), (8, c.d8), (9, c.d9), (10, c.d10)) AS v(pos, code)
    WHERE v.code IS NOT NULL
)
SELECT code AS icd9_code,
       count(*)                                           AS dx_rows,
       count(*) FILTER (WHERE segment = '1' AND pos = 1)  AS principal_rows
FROM dx
WHERE code ~ '^(\d{3,5}|V\d{2,4}|E\d{3,4})$'
GROUP BY code;

-- 2. Resolve which GEM source code each claim code uses (R1b parent fallback).
--    A code valid in 2008 but later split into subcodes maps through its residual
--    child: the "...0" (unspecified) child first, then the "...9" (other) child.
CREATE TEMP TABLE tmp_resolved ON COMMIT DROP AS
WITH gem_codes AS (SELECT DISTINCT icd9_code FROM ref.gem_icd9_to_icd10)
SELECT u.icd9_code,
       COALESCE(self.icd9_code, c0.icd9_code, c9.icd9_code) AS gem_code,
       (self.icd9_code IS NULL AND COALESCE(c0.icd9_code, c9.icd9_code) IS NOT NULL) AS via_parent_fallback
FROM tmp_dx_usage u
LEFT JOIN gem_codes self ON self.icd9_code = u.icd9_code
LEFT JOIN gem_codes c0   ON self.icd9_code IS NULL AND c0.icd9_code = u.icd9_code || '0'
LEFT JOIN gem_codes c9   ON self.icd9_code IS NULL AND c0.icd9_code IS NULL
                        AND c9.icd9_code = u.icd9_code || '9';

-- 3. Candidate ICD-10 targets with tie-break features.
--    Similarity compares the ICD-9 description (the claim code's own, else the fallback
--    child's) with each candidate's ICD-10 description. 0 when descriptions are unloaded.
CREATE TEMP TABLE tmp_candidates ON COMMIT DROP AS
SELECT r.icd9_code, g.icd10_code, g.approximate, g.combination, g.scenario, g.choice_list,
       EXISTS (SELECT 1 FROM ref.gem_icd10_to_icd9 b
               WHERE b.icd10_code = g.icd10_code AND b.icd9_code = r.gem_code) AS is_reciprocal,
       (i.icd10_code IS NOT NULL)                                          AS is_valid_fy2027,
       COALESCE(i.is_billable, false)                                      AS is_billable,
       round(COALESCE(similarity(COALESCE(d_own.long_desc, d_gem.long_desc), i.long_desc), 0)::numeric, 3)
                                                                           AS desc_similarity
FROM tmp_resolved r
JOIN ref.gem_icd9_to_icd10 g ON g.icd9_code = r.gem_code
LEFT JOIN ref.icd10cm i      ON i.icd10_code = g.icd10_code
LEFT JOIN ref.icd9cm d_own   ON d_own.icd9_code = r.icd9_code
LEFT JOIN ref.icd9cm d_gem   ON d_gem.icd9_code = r.gem_code
WHERE NOT g.no_map
  AND (NOT g.combination OR g.scenario = 1);

-- 4. Deterministic ranking within each slot.
CREATE TEMP TABLE tmp_ranked ON COMMIT DROP AS
SELECT c.*,
       row_number() OVER w                                                AS rnk,
       count(*)     OVER (PARTITION BY icd9_code, scenario, choice_list) AS slot_candidates
FROM tmp_candidates c
WINDOW w AS (PARTITION BY icd9_code, scenario, choice_list
             ORDER BY is_valid_fy2027 DESC, is_billable DESC, desc_similarity DESC,
                      is_reciprocal DESC, icd10_code);

-- 5. Winner per slot and the step that separated it from the runner-up.
CREATE TEMP TABLE tmp_choice ON COMMIT DROP AS
SELECT r1.icd9_code, r1.scenario, r1.choice_list, r1.icd10_code, r1.approximate,
       r1.is_valid_fy2027, r1.is_billable, r1.desc_similarity, r1.slot_candidates,
       CASE
           WHEN r2.icd10_code IS NULL                    THEN 'SINGLE_CANDIDATE'
           WHEN r1.is_valid_fy2027 <> r2.is_valid_fy2027 THEN 'VALID_FY2027'
           WHEN r1.is_billable     <> r2.is_billable     THEN 'BILLABLE'
           WHEN r1.desc_similarity <> r2.desc_similarity THEN 'DESC_SIMILARITY'
           WHEN r1.is_reciprocal   <> r2.is_reciprocal   THEN 'RECIPROCAL'
           ELSE 'LOWEST_CODE'
       END AS decided_by
FROM tmp_ranked r1
LEFT JOIN tmp_ranked r2
       ON r2.icd9_code = r1.icd9_code AND r2.scenario = r1.scenario
      AND r2.choice_list = r1.choice_list AND r2.rnk = 2
WHERE r1.rnk = 1;

-- 6. Apply APPROVED SME overrides (R0) to the first slot of each overridden code.
--    An override also applies to parent codes that convert THROUGH the overridden code
--    (e.g. an override on 78079 also governs parent 7807 via fallback), so one clinical
--    decision is applied consistently. A direct override on the claim code wins.
UPDATE tmp_choice c
SET icd10_code      = o.icd10_code,
    decided_by      = 'SME_OVERRIDE',
    is_valid_fy2027 = (i.icd10_code IS NOT NULL),
    is_billable     = COALESCE(i.is_billable, false)
FROM tmp_resolved r
JOIN ref.icd9_dx_override o ON o.review_status = 'APPROVED'
                           AND o.icd9_code = CASE WHEN EXISTS (SELECT 1 FROM ref.icd9_dx_override d
                                                               WHERE d.icd9_code = r.icd9_code
                                                                 AND d.review_status = 'APPROVED')
                                                  THEN r.icd9_code ELSE r.gem_code END
LEFT JOIN ref.icd10cm i ON i.icd10_code = o.icd10_code
WHERE r.icd9_code = c.icd9_code
  AND c.choice_list = (SELECT min(choice_list) FROM tmp_choice x WHERE x.icd9_code = c.icd9_code);

-- 7. One conversion row per distinct ICD-9 code (rules R0–R6).
CREATE TABLE ref.icd9_dx_conversion AS
WITH gem_flags AS (
    SELECT icd9_code, bool_or(no_map) AS any_no_map, bool_or(combination) AS any_combination
    FROM ref.gem_icd9_to_icd10
    GROUP BY icd9_code
), primary_choice AS (
    SELECT DISTINCT ON (icd9_code) *
    FROM tmp_choice
    ORDER BY icd9_code, choice_list
)
SELECT r.icd9_code,
       p.icd10_code,
       CASE
           WHEN r.gem_code IS NULL    THEN 'NOT_IN_GEM'          -- R1 (no fallback found)
           WHEN f.any_no_map          THEN 'NO_MAP'              -- R2
           WHEN r.via_parent_fallback THEN 'PARENT_FALLBACK'     -- R1b
           WHEN f.any_combination     THEN 'COMBINATION'         -- R6
           WHEN p.slot_candidates > 1 THEN 'APPROXIMATE_MULTI'   -- R5
           WHEN p.approximate         THEN 'APPROXIMATE'         -- R4
           ELSE 'EXACT'                                          -- R3
       END                              AS gem_match_type,
       r.gem_code                       AS gem_source_code,
       COALESCE(p.slot_candidates, 0)   AS candidate_count,
       p.decided_by,
       p.desc_similarity,
       p.is_valid_fy2027                AS target_valid_fy2027,
       p.is_billable                    AS target_billable,
       u.dx_rows,
       u.principal_rows
FROM tmp_resolved r
JOIN tmp_dx_usage u        ON u.icd9_code = r.icd9_code
LEFT JOIN gem_flags f      ON f.icd9_code = r.gem_code
LEFT JOIN primary_choice p ON p.icd9_code = r.icd9_code AND NOT COALESCE(f.any_no_map, false);

ALTER TABLE ref.icd9_dx_conversion ADD PRIMARY KEY (icd9_code);

-- 8. Every ICD-10 code produced (combination codes yield several rows per ICD-9 code).
CREATE TABLE silver.dx_conversion_detail AS
SELECT icd9_code, scenario, choice_list, icd10_code, decided_by
FROM tmp_choice;

CREATE INDEX ON silver.dx_conversion_detail (icd9_code);

COMMIT;

-- ===================================================================== report
\echo
\echo '============= ICD-9 -> ICD-10 CONVERSION QUALITY REPORT (v2) ============='

\echo
\echo '--- R0. Reference inputs ---'
SELECT (SELECT count(*) FROM ref.icd9cm)                                               AS icd9_descriptions,
       (SELECT count(*) FROM ref.icd9_dx_override WHERE review_status = 'APPROVED')    AS overrides_approved,
       (SELECT count(*) FROM ref.icd9_dx_override WHERE review_status = 'PROPOSED')    AS overrides_pending;

\echo
\echo '--- R1. Coverage by match type ---'
SELECT gem_match_type,
       count(*)                                                                 AS distinct_codes,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)                       AS pct_codes,
       sum(dx_rows)                                                             AS dx_rows,
       round(100.0 * sum(dx_rows) / sum(sum(dx_rows)) OVER (), 1)               AS pct_dx_rows,
       round(100.0 * sum(principal_rows) / sum(sum(principal_rows)) OVER (), 1) AS pct_principal
FROM ref.icd9_dx_conversion
GROUP BY gem_match_type
ORDER BY dx_rows DESC;

\echo
\echo '--- R2. How multi-candidate conversions were decided ---'
SELECT decided_by, count(*) AS distinct_codes, sum(dx_rows) AS dx_rows
FROM ref.icd9_dx_conversion
WHERE candidate_count > 1 OR decided_by = 'SME_OVERRIDE'
GROUP BY decided_by
ORDER BY dx_rows DESC;

\echo
\echo '--- R3. Target validity in FY2027 ICD-10-CM (overrides included) ---'
SELECT count(*) FILTER (WHERE icd10_code IS NOT NULL)      AS converted_codes,
       count(*) FILTER (WHERE target_valid_fy2027 = false) AS target_not_valid_fy2027,
       count(*) FILTER (WHERE target_billable = false)     AS target_not_billable
FROM ref.icd9_dx_conversion;

\echo
\echo '--- R4. Dollars on claims whose principal diagnosis is missing or not converted ---'
WITH principal AS (
    SELECT 'IP' AS claim_type, clm_id, btrim(icd9_dgns_cd_1) AS code
    FROM bronze.desynpuf_inpatient WHERE segment = '1'
    UNION ALL
    SELECT 'OP', clm_id, btrim(icd9_dgns_cd_1)
    FROM bronze.desynpuf_outpatient WHERE segment = '1'
), unconverted AS (
    SELECT p.claim_type, p.clm_id
    FROM principal p
    LEFT JOIN ref.icd9_dx_conversion c ON c.icd9_code = p.code
    WHERE c.icd10_code IS NULL
), paid AS (
    SELECT 'IP' AS claim_type, clm_id, sum(COALESCE(clm_pmt_amt::numeric, 0)) AS amt
    FROM bronze.desynpuf_inpatient GROUP BY clm_id
    UNION ALL
    SELECT 'OP', clm_id, sum(COALESCE(clm_pmt_amt::numeric, 0))
    FROM bronze.desynpuf_outpatient GROUP BY clm_id
)
SELECT u.claim_type, count(*) AS claims_affected, sum(p.amt) AS paid_affected
FROM unconverted u
JOIN paid p USING (claim_type, clm_id)
GROUP BY u.claim_type
ORDER BY u.claim_type;

\echo
\echo '--- R5. Most-used multi-candidate conversions (SME review sample) ---'
SELECT c.icd9_code, left(d.long_desc, 40) AS icd9_description, c.icd10_code,
       left(i.long_desc, 45) AS icd10_description, c.decided_by, c.desc_similarity, c.dx_rows
FROM ref.icd9_dx_conversion c
LEFT JOIN ref.icd9cm d  ON d.icd9_code = c.icd9_code
LEFT JOIN ref.icd10cm i ON i.icd10_code = c.icd10_code
WHERE c.candidate_count > 1
ORDER BY c.dx_rows DESC
LIMIT 15;

\echo
\echo '--- R6. Parent fallback conversions (top 10 by use) ---'
SELECT c.icd9_code, c.gem_source_code, c.icd10_code, left(i.long_desc, 50) AS icd10_description, c.dx_rows
FROM ref.icd9_dx_conversion c
LEFT JOIN ref.icd10cm i ON i.icd10_code = c.icd10_code
WHERE c.gem_match_type = 'PARENT_FALLBACK'
ORDER BY c.dx_rows DESC
LIMIT 10;

\echo
\echo '--- R7. Still not in GEM after fallback (top 10 by use) ---'
SELECT icd9_code, dx_rows, principal_rows
FROM ref.icd9_dx_conversion
WHERE gem_match_type = 'NOT_IN_GEM'
ORDER BY dx_rows DESC
LIMIT 10;

\echo
\echo '--- R8. Regression versus previous run: decisions that changed ---'
SELECT count(*)                                       AS codes_changed,
       COALESCE(sum(n.dx_rows), 0)                    AS dx_rows_affected
FROM ref.icd9_dx_conversion n
JOIN ref.icd9_dx_conversion_prev o USING (icd9_code)
WHERE n.icd10_code IS DISTINCT FROM o.icd10_code;

SELECT n.icd9_code, o.icd10_code AS previous, n.icd10_code AS current,
       n.decided_by AS decided_by_now, n.dx_rows
FROM ref.icd9_dx_conversion n
JOIN ref.icd9_dx_conversion_prev o USING (icd9_code)
WHERE n.icd10_code IS DISTINCT FROM o.icd10_code
ORDER BY n.dx_rows DESC
LIMIT 15;
