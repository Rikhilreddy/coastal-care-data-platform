-- EDI-1 discovery: what does an X12 837 need that the FHIR claims do (or do not) provide?
-- An 837 must carry: billing provider (name, NPI, address), rendering provider NPI,
-- subscriber/payer, ICD-10 diagnoses, and a CPT/HCPCS code on every service line.
-- Read-only. Shows structure (keys, code systems, counts), not patient values.
-- Run: psql coastal_care -f sql/investigations/05_edi_discovery.sql | tee docs/profiling/edi_discovery.txt
\pset footer off
\timing off

\echo '--- E1. Claim: top-level fields and how often they appear ---'
SELECT k AS claim_field, count(*) AS claims
FROM bronze.fhir_resource r, jsonb_object_keys(r.resource) AS k
WHERE r.resource_type = 'Claim'
GROUP BY 1 ORDER BY 2 DESC, 1;

\echo '--- E2. Claim: sub-fields of item[], careTeam[], insurance[] (first element) ---'
SELECT 'item' AS element, k AS field, count(*) AS claims
FROM bronze.fhir_resource r, jsonb_object_keys(r.resource -> 'item' -> 0) AS k
WHERE r.resource_type = 'Claim' GROUP BY 1, 2
UNION ALL
SELECT 'careTeam', k, count(*)
FROM bronze.fhir_resource r, jsonb_object_keys(r.resource -> 'careTeam' -> 0) AS k
WHERE r.resource_type = 'Claim' AND jsonb_typeof(r.resource -> 'careTeam') = 'array' GROUP BY 1, 2
UNION ALL
SELECT 'insurance', k, count(*)
FROM bronze.fhir_resource r, jsonb_object_keys(r.resource -> 'insurance' -> 0) AS k
WHERE r.resource_type = 'Claim' GROUP BY 1, 2
ORDER BY 1, 3 DESC;

\echo '--- E3. How Claims point to providers (reference patterns) ---'
SELECT regexp_replace(resource #>> '{provider,reference}', '[|?/:][^|?/:]*$', '|<id>') AS provider_reference_pattern,
       count(*) AS claims
FROM bronze.fhir_resource WHERE resource_type = 'Claim'
GROUP BY 1 ORDER BY 2 DESC LIMIT 5;

\echo '--- E4. ExplanationOfBenefit: careTeam, total categories, adjudication categories ---'
SELECT 'eob_field' AS what, k AS value, count(*) AS n
FROM bronze.fhir_resource r, jsonb_object_keys(r.resource) AS k
WHERE r.resource_type = 'ExplanationOfBenefit' GROUP BY 1, 2
UNION ALL
SELECT 'total.category', t #>> '{category,coding,0,code}', count(*)
FROM bronze.fhir_resource r, jsonb_array_elements(r.resource -> 'total') AS t
WHERE r.resource_type = 'ExplanationOfBenefit' AND jsonb_typeof(r.resource -> 'total') = 'array' GROUP BY 1, 2
UNION ALL
SELECT 'item.adjudication.category', a #>> '{category,coding,0,code}', count(*)
FROM bronze.fhir_resource r,
     jsonb_array_elements(r.resource -> 'item') AS i,
     jsonb_array_elements(i -> 'adjudication') AS a
WHERE r.resource_type = 'ExplanationOfBenefit' AND jsonb_typeof(i -> 'adjudication') = 'array' GROUP BY 1, 2
ORDER BY 1, 3 DESC;

\echo '--- E5. Do Organizations and Practitioners carry NPIs? (identifier systems) ---'
SELECT r.resource_type, i ->> 'system' AS identifier_system, count(*) AS resources
FROM bronze.fhir_resource r, jsonb_array_elements(r.resource -> 'identifier') AS i
WHERE r.resource_type IN ('Organization', 'Practitioner') AND jsonb_typeof(r.resource -> 'identifier') = 'array'
GROUP BY 1, 2 ORDER BY 1, 3 DESC;

SELECT resource_type,
       count(*)                                                    AS resources,
       count(*) FILTER (WHERE resource #>> '{address,0,city}' IS NOT NULL) AS with_address,
       count(*) FILTER (WHERE resource ? 'name')                    AS with_name
FROM bronze.fhir_resource WHERE resource_type IN ('Organization', 'Practitioner', 'Location')
GROUP BY 1;

\echo '--- E6. Claim line codes (non-pharmacy): how many SNOMED codes cover 80/90/95/99% of lines ---'
WITH lines AS (
    SELECT i #>> '{productOrService,coding,0,system}' AS code_system,
           i #>> '{productOrService,coding,0,code}'   AS code
    FROM bronze.fhir_resource r, jsonb_array_elements(r.resource -> 'item') AS i
    WHERE r.resource_type = 'Claim' AND r.resource #>> '{type,coding,0,code}' <> 'pharmacy'
),
ranked AS (
    SELECT code, count(*) AS n,
           sum(count(*)) OVER (ORDER BY count(*) DESC, code) / sum(count(*)) OVER () AS cum_share
    FROM lines WHERE code_system = 'http://snomed.info/sct'
    GROUP BY code
)
SELECT (SELECT count(*) FROM ranked)                              AS snomed_codes,
       (SELECT sum(n) FROM ranked)                                AS snomed_lines,
       (SELECT count(*) FROM ranked WHERE cum_share <= 0.80) + 1  AS codes_for_80pct,
       (SELECT count(*) FROM ranked WHERE cum_share <= 0.90) + 1  AS codes_for_90pct,
       (SELECT count(*) FROM ranked WHERE cum_share <= 0.95) + 1  AS codes_for_95pct,
       (SELECT count(*) FROM ranked WHERE cum_share <= 0.99) + 1  AS codes_for_99pct;

\echo '--- E7. Top 25 non-pharmacy SNOMED line codes (first line = the encounter itself?) ---'
SELECT i #>> '{productOrService,coding,0,code}'    AS snomed_code,
       left(i #>> '{productOrService,coding,0,display}', 55) AS display,
       count(*)                                    AS lines,
       count(*) FILTER (WHERE (i ->> 'sequence') = '1') AS as_first_line
FROM bronze.fhir_resource r, jsonb_array_elements(r.resource -> 'item') AS i
WHERE r.resource_type = 'Claim' AND r.resource #>> '{type,coding,0,code}' <> 'pharmacy'
  AND i #>> '{productOrService,coding,0,system}' = 'http://snomed.info/sct'
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 25;

\echo '--- E8. File sizing: non-pharmacy claims per payer per year, 2017+ (H14) ---'
SELECT h.payer_name, h.claim_year, count(*) AS claims
FROM silver.claim_header h
WHERE h.source_system = 'SYNTHEA_FHIR' AND h.claim_type <> 'RX' AND h.claim_year >= 2017
GROUP BY 1, 2 ORDER BY 1, 2;
