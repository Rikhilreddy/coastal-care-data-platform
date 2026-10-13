-- Coastal Care Data Platform: follow-up on segment and claim-year findings
-- Run: psql coastal_care -f sql/investigations/03_segment_followup.sql

\pset footer off

\echo
\echo '=== F1. What do segment 2 rows carry? (dates, payments, diagnoses) ==='
SELECT 'inpatient' AS source, segment,
       count(*)                                     AS rows,
       count(clm_from_dt)                           AS rows_with_from_date,
       count(*) FILTER (WHERE COALESCE(clm_pmt_amt::numeric, 0) <> 0) AS rows_with_payment,
       sum(COALESCE(clm_pmt_amt::numeric, 0))       AS total_paid,
       count(icd9_dgns_cd_1)                        AS rows_with_primary_dx
FROM bronze.desynpuf_inpatient GROUP BY segment
UNION ALL
SELECT 'outpatient', segment, count(*), count(clm_from_dt),
       count(*) FILTER (WHERE COALESCE(clm_pmt_amt::numeric, 0) <> 0),
       sum(COALESCE(clm_pmt_amt::numeric, 0)), count(icd9_dgns_cd_1)
FROM bronze.desynpuf_outpatient GROUP BY segment
ORDER BY source, segment;

\echo
\echo '=== F2. Segment 2 rows with no matching segment 1 (orphan continuations) ==='
SELECT 'inpatient' AS source, count(*) AS orphan_segment_2,
       sum(COALESCE(clm_pmt_amt::numeric, 0)) AS orphan_paid
FROM bronze.desynpuf_inpatient s2
WHERE segment = '2'
  AND NOT EXISTS (SELECT 1 FROM bronze.desynpuf_inpatient s1
                  WHERE s1.clm_id = s2.clm_id AND s1.segment = '1')
UNION ALL
SELECT 'outpatient', count(*), sum(COALESCE(clm_pmt_amt::numeric, 0))
FROM bronze.desynpuf_outpatient s2
WHERE segment = '2'
  AND NOT EXISTS (SELECT 1 FROM bronze.desynpuf_outpatient s1
                  WHERE s1.clm_id = s2.clm_id AND s1.segment = '1');

\echo
\echo '=== F3. Claims starting in 2007: which year do they end in? ==='
SELECT source, left(clm_thru_dt, 4) AS thru_year, count(*) AS claims
FROM (
    SELECT 'inpatient' AS source, clm_from_dt, clm_thru_dt FROM bronze.desynpuf_inpatient
    UNION ALL
    SELECT 'outpatient', clm_from_dt, clm_thru_dt FROM bronze.desynpuf_outpatient
) c
WHERE left(clm_from_dt, 4) = '2007'
GROUP BY source, left(clm_thru_dt, 4)
ORDER BY source, thru_year;

\echo
\echo '=== F4. Re-run of enrollment match using thru-date year (segment 1 only) ==='
WITH claims AS (
    SELECT 'inpatient' AS source, desynpuf_id, left(clm_thru_dt, 4) AS claim_year
    FROM bronze.desynpuf_inpatient WHERE segment = '1'
    UNION ALL
    SELECT 'outpatient', desynpuf_id, left(clm_thru_dt, 4)
    FROM bronze.desynpuf_outpatient WHERE segment = '1'
)
SELECT source,
       count(*) AS segment_1_claims,
       count(*) FILTER (WHERE NOT EXISTS (
           SELECT 1 FROM bronze.desynpuf_beneficiary b
           WHERE b.desynpuf_id = c.desynpuf_id
             AND b._file_year::text = c.claim_year)) AS not_enrolled_in_thru_year
FROM claims c
GROUP BY source
ORDER BY source;
