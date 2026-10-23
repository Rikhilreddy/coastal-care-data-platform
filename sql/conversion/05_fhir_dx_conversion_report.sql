-- CONV-4 quality report: SNOMED CT -> ICD-10-CM conversion of FHIR diagnoses.
-- Rerun after every crosswalk review session to watch coverage rise.
-- Run: psql coastal_care -f sql/conversion/05_fhir_dx_conversion_report.sql | tee docs/mapping/fhir_dx_conversion_report.txt
\pset footer off
\timing off
\echo '============= SNOMED CT -> ICD-10-CM CONVERSION REPORT (CONV-4) ============='

\echo '--- C1. FHIR claim diagnoses by conversion outcome ---'
SELECT conversion_method,
       count(*)                                                        AS dx_rows,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)              AS pct_rows,
       count(*) FILTER (WHERE dx_role = 'PRINCIPAL')                   AS principal_rows
FROM silver.claim_diagnosis WHERE source_system = 'SYNTHEA_FHIR'
GROUP BY 1 ORDER BY 2 DESC;

\echo '--- C2. Crosswalk review progress (codes and the claim diagnoses they cover) ---'
SELECT x.review_status, x.review_priority,
       count(DISTINCT x.snomed_code)  AS codes,
       count(d.claim_id)              AS claim_dx_rows
FROM ref.snomed_icd10_crosswalk x
LEFT JOIN silver.claim_diagnosis d
  ON d.source_system = 'SYNTHEA_FHIR' AND d.source_code = x.snomed_code
GROUP BY 1, 2 ORDER BY 1, 2;

\echo '--- C3. SME worklist: PROPOSED codes ranked by claim diagnoses waiting on them ---'
SELECT x.snomed_code, left(x.snomed_description, 45) AS snomed_description, x.icd10_code AS proposed_icd10,
       x.category, x.sensitive, count(d.claim_id) AS claim_dx_rows
FROM ref.snomed_icd10_crosswalk x
JOIN silver.claim_diagnosis d ON d.source_system = 'SYNTHEA_FHIR' AND d.source_code = x.snomed_code
WHERE x.review_status = 'PROPOSED'
GROUP BY 1, 2, 3, 4, 5 ORDER BY 6 DESC LIMIT 20;

\echo '--- C4. Sensitive diagnoses (counts only; masked in gold) ---'
SELECT count(*) AS sensitive_dx_rows, count(DISTINCT claim_id) AS claims,
       count(DISTINCT source_code) AS distinct_codes
FROM silver.claim_diagnosis WHERE source_system = 'SYNTHEA_FHIR' AND is_sensitive;

\echo '--- C5. Billed dollars on FHIR claims whose PRINCIPAL diagnosis has no ICD-10 code ---'
SELECT coalesce(d.conversion_method, 'NO_DIAGNOSIS') AS principal_outcome,
       count(*) AS claims, round(sum(h.billed_amount), 2) AS billed
FROM silver.claim_header h
LEFT JOIN silver.claim_diagnosis d
  ON d.source_system = h.source_system AND d.claim_id = h.claim_id AND d.dx_role = 'PRINCIPAL'
WHERE h.source_system = 'SYNTHEA_FHIR' AND h.claim_type <> 'RX'
  AND d.icd10_code IS NULL
GROUP BY 1 ORDER BY 3 DESC;

\echo '--- C6. Principal-diagnosis ICD-10 coverage, all sources ---'
SELECT source_system,
       count(*)                                       AS principal_dx,
       count(icd10_code)                              AS with_icd10,
       round(100.0 * count(icd10_code) / count(*), 1) AS pct_with_icd10
FROM silver.claim_diagnosis WHERE dx_role = 'PRINCIPAL'
GROUP BY 1 ORDER BY 1;

\echo '--- C7. Unresolved Condition references (quarantined) ---'
SELECT count(*) AS unresolved_references
FROM quarantine.code_exception WHERE source_system = 'SYNTHEA_FHIR' AND reason_code = 'UNRESOLVED_REFERENCE';
