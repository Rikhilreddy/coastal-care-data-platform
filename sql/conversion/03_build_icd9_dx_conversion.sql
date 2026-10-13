-- Coastal Care Data Platform: ICD-9-CM -> ICD-10-CM diagnosis conversion
-- Implements docs/mapping/icd9_to_icd10_conversion_spec.md (rules R1–R6 and tie-break).
-- Outputs: ref.icd9_dx_conversion, silver.dx_conversion_detail, plus a quality report.
-- Safe to rerun (full rebuild in one transaction).
--
-- Run: psql coastal_care -f sql/conversion/03_build_icd9_dx_conversion.sql | tee docs/mapping/conversion_quality_report.txt

\set ON_ERROR_STOP on
\pset footer off
\timing off

BEGIN;

DROP TABLE IF EXISTS ref.icd9_dx_conversion;
DROP TABLE IF EXISTS silver.dx_conversion_detail;

-- 1. Every format-valid ICD-9 diagnosis code used in legacy claims, with usage counts.
--    Position 0 = admitting diagnosis; principal = segment 1, position 1.
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
WHERE code ~ '^(\d{3,5}|V\d{2,4}|E\d{3,4})$'      -- placeholders like 'OTHER' are handled as exceptions (F5)
GROUP BY code;

-- 2. Candidate ICD-10 targets with tie-break features.
--    No-map rows excluded; combination codes use scenario 1 only (R6).
CREATE TEMP TABLE tmp_candidates ON COMMIT DROP AS
SELECT g.icd9_code, g.icd10_code, g.approximate, g.combination, g.scenario, g.choice_list,
       EXISTS (SELECT 1 FROM ref.gem_icd10_to_icd9 b
               WHERE b.icd10_code = g.icd10_code AND b.icd9_code = g.icd9_code) AS is_reciprocal,
       (i.icd10_code IS NOT NULL)                         AS is_valid_fy2027,
       COALESCE(i.is_billable, false)                     AS is_billable,
       COALESCE(i.long_desc ILIKE '%unspecified%', false) AS is_unspecified
FROM ref.gem_icd9_to_icd10 g
JOIN tmp_dx_usage u USING (icd9_code)
LEFT JOIN ref.icd10cm i ON i.icd10_code = g.icd10_code
WHERE NOT g.no_map
  AND (NOT g.combination OR g.scenario = 1);

-- 3. Deterministic ranking within each slot (code + scenario + choice list).
CREATE TEMP TABLE tmp_ranked ON COMMIT DROP AS
SELECT c.*,
       row_number() OVER w                                                   AS rnk,
       count(*)     OVER (PARTITION BY icd9_code, scenario, choice_list)    AS slot_candidates
FROM tmp_candidates c
WINDOW w AS (PARTITION BY icd9_code, scenario, choice_list
             ORDER BY is_reciprocal DESC, is_valid_fy2027 DESC, is_billable DESC,
                      is_unspecified DESC, icd10_code);

-- 4. Winner per slot, and which tie-break step separated it from the runner-up.
CREATE TEMP TABLE tmp_choice ON COMMIT DROP AS
SELECT r1.icd9_code, r1.scenario, r1.choice_list, r1.icd10_code, r1.approximate,
       r1.is_valid_fy2027, r1.is_billable, r1.slot_candidates,
       CASE
           WHEN r2.icd10_code IS NULL                    THEN 'SINGLE_CANDIDATE'
           WHEN r1.is_reciprocal   <> r2.is_reciprocal   THEN 'RECIPROCAL'
           WHEN r1.is_valid_fy2027 <> r2.is_valid_fy2027 THEN 'VALID_FY2027'
           WHEN r1.is_billable     <> r2.is_billable     THEN 'BILLABLE'
           WHEN r1.is_unspecified  <> r2.is_unspecified  THEN 'UNSPECIFIED'
           ELSE 'LOWEST_CODE'
       END AS decided_by
FROM tmp_ranked r1
LEFT JOIN tmp_ranked r2
       ON r2.icd9_code = r1.icd9_code AND r2.scenario = r1.scenario
      AND r2.choice_list = r1.choice_list AND r2.rnk = 2
WHERE r1.rnk = 1;

-- 5. One conversion row per distinct ICD-9 code (rules R1–R6).
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
SELECT u.icd9_code,
       p.icd10_code,
       CASE
           WHEN f.icd9_code IS NULL   THEN 'NOT_IN_GEM'          -- R1
           WHEN f.any_no_map          THEN 'NO_MAP'              -- R2
           WHEN f.any_combination     THEN 'COMBINATION'         -- R6
           WHEN p.slot_candidates > 1 THEN 'APPROXIMATE_MULTI'   -- R5
           WHEN p.approximate         THEN 'APPROXIMATE'         -- R4
           ELSE 'EXACT'                                          -- R3
       END                              AS gem_match_type,
       COALESCE(p.slot_candidates, 0)   AS candidate_count,
       p.decided_by,
       p.is_valid_fy2027                AS target_valid_fy2027,
       p.is_billable                    AS target_billable,
       u.dx_rows,
       u.principal_rows
FROM tmp_dx_usage u
LEFT JOIN gem_flags f      ON f.icd9_code = u.icd9_code
LEFT JOIN primary_choice p ON p.icd9_code = u.icd9_code AND NOT COALESCE(f.any_no_map, false);

ALTER TABLE ref.icd9_dx_conversion ADD PRIMARY KEY (icd9_code);

-- 6. Every ICD-10 code produced (combination codes yield several rows per ICD-9 code).
CREATE TABLE silver.dx_conversion_detail AS
SELECT icd9_code, scenario, choice_list, icd10_code, decided_by
FROM tmp_choice;

CREATE INDEX ON silver.dx_conversion_detail (icd9_code);

COMMIT;

-- ===================================================================== report
\echo
\echo '================ ICD-9 -> ICD-10 CONVERSION QUALITY REPORT ================'

\echo
\echo '--- R1. Coverage by match type (distinct codes, all diagnosis rows, principal diagnoses) ---'
SELECT gem_match_type,
       count(*)                                                          AS distinct_codes,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)                AS pct_codes,
       sum(dx_rows)                                                      AS dx_rows,
       round(100.0 * sum(dx_rows) / sum(sum(dx_rows)) OVER (), 1)        AS pct_dx_rows,
       round(100.0 * sum(principal_rows) / sum(sum(principal_rows)) OVER (), 1) AS pct_principal
FROM ref.icd9_dx_conversion
GROUP BY gem_match_type
ORDER BY dx_rows DESC;

\echo
\echo '--- R2. How multi-candidate conversions were decided ---'
SELECT gem_match_type, decided_by, count(*) AS distinct_codes, sum(dx_rows) AS dx_rows
FROM ref.icd9_dx_conversion
WHERE candidate_count > 1
GROUP BY gem_match_type, decided_by
ORDER BY gem_match_type, dx_rows DESC;

\echo
\echo '--- R3. Target validity in FY2027 ICD-10-CM ---'
SELECT count(*) FILTER (WHERE icd10_code IS NOT NULL)          AS converted_codes,
       count(*) FILTER (WHERE target_valid_fy2027 = false)     AS target_not_valid_fy2027,
       count(*) FILTER (WHERE target_billable = false)         AS target_not_billable
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
SELECT u.claim_type,
       count(*)    AS claims_affected,
       sum(p.amt)  AS paid_affected
FROM unconverted u
JOIN paid p USING (claim_type, clm_id)
GROUP BY u.claim_type
ORDER BY u.claim_type;

\echo
\echo '--- R5. Most-used multi-candidate conversions (review sample) ---'
SELECT c.icd9_code, c.icd10_code, left(i.long_desc, 70) AS icd10_description,
       c.candidate_count, c.decided_by, c.dx_rows
FROM ref.icd9_dx_conversion c
LEFT JOIN ref.icd10cm i ON i.icd10_code = c.icd10_code
WHERE c.gem_match_type = 'APPROXIMATE_MULTI'
ORDER BY c.dx_rows DESC
LIMIT 10;

\echo
\echo '--- R6. Codes used in claims but absent from GEMs (top 10 by use) ---'
SELECT icd9_code, dx_rows, principal_rows
FROM ref.icd9_dx_conversion
WHERE gem_match_type = 'NOT_IN_GEM'
ORDER BY dx_rows DESC
LIMIT 10;
