-- FHIR-2 discovery: answer the open questions in docs/profiling/fhir_findings.md
-- before designing the FHIR -> silver mapping. Read-only.
-- JSONB operators used:  ->  returns JSON,  ->>  returns text,  #>> '{a,0,b}'  follows a path,
--                        jsonb_array_elements() turns a JSON array into rows.
-- Run: psql coastal_care -f sql/investigations/04_fhir_open_questions.sql | tee docs/profiling/fhir_open_questions.txt

\pset footer off
\timing off

\echo '--- Q1. Claim types and dollars (institutional / professional / pharmacy) ---'
SELECT resource #>> '{type,coding,0,code}'                   AS claim_type,
       count(*)                                              AS claims,
       round(sum((resource #>> '{total,value}')::numeric), 2) AS claim_total
FROM bronze.fhir_resource WHERE resource_type = 'Claim'
GROUP BY 1 ORDER BY 2 DESC;

\echo '--- Q2. Payer mix (who is billed) ---'
SELECT resource #>> '{insurance,0,coverage,display}'         AS payer,
       count(*)                                              AS claims,
       round(sum((resource #>> '{total,value}')::numeric), 2) AS claim_total
FROM bronze.fhir_resource WHERE resource_type = 'Claim'
GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

\echo '--- Q3. Claim <-> EOB pairing (EOB.claim.reference points to the Claim) ---'
-- Anti-joins (LEFT JOIN ... IS NULL), not NOT IN: NOT IN over 151K rows can fall back to
-- a row-by-row scan (the stuck-terminal lesson from SILVER-1).
WITH c AS (SELECT resource_id AS claim_id FROM bronze.fhir_resource WHERE resource_type = 'Claim'),
     e AS (SELECT regexp_replace(resource #>> '{claim,reference}', '^(urn:uuid:|Claim/)', '') AS claim_id
           FROM bronze.fhir_resource WHERE resource_type = 'ExplanationOfBenefit'),
     e1 AS (SELECT DISTINCT claim_id FROM e)
SELECT (SELECT count(*) FROM c)                                                    AS claims,
       (SELECT count(*) FROM e)                                                    AS eobs,
       (SELECT count(*) FROM c LEFT JOIN e1 USING (claim_id) WHERE e1.claim_id IS NULL) AS claims_without_eob,
       (SELECT count(*) FROM e1 LEFT JOIN c USING (claim_id) WHERE c.claim_id IS NULL)  AS eobs_without_claim,
       (SELECT count(*) FROM e) - (SELECT count(*) FROM e1)                        AS extra_eobs_same_claim;

\echo '--- Q4. What the payer paid vs what was billed ---'
WITH c AS (SELECT resource_id, (resource #>> '{total,value}')::numeric AS billed
           FROM bronze.fhir_resource WHERE resource_type = 'Claim'),
     e AS (SELECT regexp_replace(resource #>> '{claim,reference}', '^(urn:uuid:|Claim/)', '') AS claim_id,
                  (resource #>> '{payment,amount,value}')::numeric AS paid
           FROM bronze.fhir_resource WHERE resource_type = 'ExplanationOfBenefit')
SELECT round(sum(c.billed), 2)                          AS billed,
       round(sum(e.paid), 2)                            AS paid,
       round(100 * sum(e.paid) / nullif(sum(c.billed), 0), 1) AS pct_paid,
       count(*) FILTER (WHERE e.paid IS NULL)           AS eob_without_payment,
       count(*) FILTER (WHERE e.paid > c.billed)        AS paid_more_than_billed,
       count(*) FILTER (WHERE e.paid = 0)               AS zero_paid
FROM c JOIN e ON e.claim_id = c.resource_id;

\echo '--- Q5. Distinct SNOMED diagnosis codes (sizes CONV-4: SNOMED -> ICD-10-CM) ---'
SELECT count(DISTINCT resource #>> '{code,coding,0,code}') AS distinct_condition_codes,
       count(*)                                           AS conditions
FROM bronze.fhir_resource WHERE resource_type = 'Condition';

SELECT resource #>> '{code,coding,0,code}'    AS snomed_code,
       resource #>> '{code,coding,0,display}' AS description,
       count(*)                               AS conditions
FROM bronze.fhir_resource WHERE resource_type = 'Condition'
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 15;

\echo '--- Q6. Billed services on Claims by code system (sizes the 837 procedure crosswalk) ---'
SELECT i #>> '{productOrService,coding,0,system}'          AS code_system,
       count(DISTINCT i #>> '{productOrService,coding,0,code}') AS distinct_codes,
       count(*)                                           AS claim_lines
FROM bronze.fhir_resource r
CROSS JOIN LATERAL jsonb_array_elements(r.resource -> 'item') AS i
WHERE r.resource_type = 'Claim'
GROUP BY 1 ORDER BY 3 DESC;

\echo '--- Q7. Patients: demographics available for silver.member ---'
SELECT count(*)                                                AS patients,
       count(*) FILTER (WHERE resource ? 'deceasedDateTime')  AS deceased,
       min(resource ->> 'birthDate')                          AS earliest_birth,
       max(resource ->> 'birthDate')                          AS latest_birth,
       count(*) FILTER (WHERE resource ->> 'gender' = 'female') AS female,
       count(*) FILTER (WHERE resource ->> 'gender' = 'male')   AS male
FROM bronze.fhir_resource WHERE resource_type = 'Patient';

\echo '--- Q8. Claims per year, last 12 years (chooses the gold reporting window, H6) ---'
SELECT left(resource #>> '{billablePeriod,start}', 4) AS claim_year,
       count(*)                                       AS claims,
       count(DISTINCT resource #>> '{patient,reference}') AS patients_with_claims
FROM bronze.fhir_resource WHERE resource_type = 'Claim'
GROUP BY 1 ORDER BY 1 DESC LIMIT 12;
