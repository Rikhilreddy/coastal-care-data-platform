-- Coastal Care Data Platform: bronze investigations
-- Answers the open questions in docs/profiling/desynpuf_findings.md before silver design.
-- Run: psql coastal_care -f sql/investigations/02_bronze_open_questions.sql

\timing off
\pset footer off

-- Supporting index for member/year lookups (safe to rerun).
CREATE INDEX IF NOT EXISTS ix_bronze_bene_member_year
    ON bronze.desynpuf_beneficiary (desynpuf_id, _file_year);

\echo
\echo '=== Q1a. Segment values present ==='
SELECT 'inpatient' AS source, segment, count(*) AS rows
FROM bronze.desynpuf_inpatient GROUP BY segment
UNION ALL
SELECT 'outpatient', segment, count(*)
FROM bronze.desynpuf_outpatient GROUP BY segment
ORDER BY source, segment;

\echo
\echo '=== Q1b. Multi-segment claims: do segments disagree on member or dates? ==='
WITH seg AS (
    SELECT 'inpatient' AS source, clm_id, desynpuf_id, clm_from_dt, clm_thru_dt
    FROM bronze.desynpuf_inpatient
    UNION ALL
    SELECT 'outpatient', clm_id, desynpuf_id, clm_from_dt, clm_thru_dt
    FROM bronze.desynpuf_outpatient
), per_claim AS (
    SELECT source, clm_id,
           count(*)                     AS segments,
           count(DISTINCT desynpuf_id)  AS members,
           count(DISTINCT clm_from_dt)  AS from_dates,
           count(DISTINCT clm_thru_dt)  AS thru_dates
    FROM seg
    GROUP BY source, clm_id
    HAVING count(*) > 1
)
SELECT source,
       count(*)                                  AS multi_segment_claims,
       count(*) FILTER (WHERE members > 1)       AS segments_differ_by_member,
       count(*) FILTER (WHERE from_dates > 1)    AS segments_differ_by_from_date,
       count(*) FILTER (WHERE thru_dates > 1)    AS segments_differ_by_thru_date
FROM per_claim
GROUP BY source
ORDER BY source;

\echo
\echo '=== Q2. Claim IDs present in both inpatient and outpatient ==='
SELECT count(*) AS clm_ids_in_both_files
FROM (SELECT DISTINCT clm_id FROM bronze.desynpuf_inpatient) i
JOIN (SELECT DISTINCT clm_id FROM bronze.desynpuf_outpatient) o USING (clm_id);

\echo
\echo '=== Q3. Orphan claims: member not enrolled in the claim year / never seen ==='
WITH claims AS (
    SELECT 'inpatient' AS source, desynpuf_id, left(clm_from_dt, 4) AS claim_year,
           COALESCE(clm_pmt_amt::numeric, 0) AS paid
    FROM bronze.desynpuf_inpatient
    UNION ALL
    SELECT 'outpatient', desynpuf_id, left(clm_from_dt, 4),
           COALESCE(clm_pmt_amt::numeric, 0)
    FROM bronze.desynpuf_outpatient
), flagged AS (
    SELECT c.*,
           NOT EXISTS (SELECT 1 FROM bronze.desynpuf_beneficiary b
                       WHERE b.desynpuf_id = c.desynpuf_id
                         AND b._file_year::text = c.claim_year) AS not_enrolled_that_year,
           NOT EXISTS (SELECT 1 FROM bronze.desynpuf_beneficiary b
                       WHERE b.desynpuf_id = c.desynpuf_id)      AS member_never_seen
    FROM claims c
)
SELECT source,
       count(*)                                          AS total_claims,
       count(*) FILTER (WHERE claim_year IS NULL)        AS missing_from_date,
       count(*) FILTER (WHERE not_enrolled_that_year)    AS not_enrolled_that_year,
       sum(paid) FILTER (WHERE not_enrolled_that_year)   AS paid_not_enrolled,
       count(*) FILTER (WHERE member_never_seen)         AS member_never_seen
FROM flagged
GROUP BY source
ORDER BY source;

\echo
\echo '=== Q4. Date sanity ==='
WITH claims AS (
    SELECT 'inpatient' AS source, clm_from_dt, clm_thru_dt FROM bronze.desynpuf_inpatient
    UNION ALL
    SELECT 'outpatient', clm_from_dt, clm_thru_dt FROM bronze.desynpuf_outpatient
)
SELECT source,
       count(*) FILTER (WHERE clm_from_dt IS NULL)                                AS null_from,
       count(*) FILTER (WHERE clm_thru_dt IS NULL)                                AS null_thru,
       count(*) FILTER (WHERE left(clm_from_dt, 4) NOT IN ('2008','2009','2010')) AS from_outside_2008_2010,
       count(*) FILTER (WHERE clm_thru_dt < clm_from_dt)                          AS thru_before_from,
       min(clm_from_dt) AS min_from,
       max(clm_thru_dt) AS max_thru
FROM claims
GROUP BY source
ORDER BY source;

\echo
\echo '=== Q5. Payment integrity: service after the member''s recorded death ==='
WITH death AS (
    SELECT desynpuf_id, min(bene_death_dt) AS death_dt
    FROM bronze.desynpuf_beneficiary
    WHERE bene_death_dt IS NOT NULL
    GROUP BY desynpuf_id
), claims AS (
    SELECT 'inpatient' AS source, desynpuf_id, clm_from_dt,
           COALESCE(clm_pmt_amt::numeric, 0) AS paid
    FROM bronze.desynpuf_inpatient
    UNION ALL
    SELECT 'outpatient', desynpuf_id, clm_from_dt,
           COALESCE(clm_pmt_amt::numeric, 0)
    FROM bronze.desynpuf_outpatient
)
SELECT c.source,
       count(*)                     AS claims_after_death,
       count(DISTINCT c.desynpuf_id) AS members_affected,
       sum(c.paid)                  AS paid_after_death
FROM claims c
JOIN death d USING (desynpuf_id)
WHERE c.clm_from_dt > d.death_dt
GROUP BY c.source
ORDER BY c.source;
