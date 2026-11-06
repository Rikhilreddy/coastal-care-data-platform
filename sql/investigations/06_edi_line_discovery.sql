-- EDI-1 discovery, part 2: service lines, line charges, and diagnosis coverage.
-- Answers: which claim lines are billable services vs supplies vs non-billable items,
-- where line charges live, and which encounter types arrive without any diagnosis.
-- Run: psql coastal_care -f sql/investigations/06_edi_line_discovery.sql | tee docs/profiling/edi_line_discovery.txt
\pset footer off
\timing off

\echo '--- E9. Claim lines by SNOMED semantic tag, i.e. the "(procedure)" / "(physical object)" suffix ---'
-- The tag is SNOMED''s top-level hierarchy: it tells us whether a line is a service,
-- a supply, or something that is not billable at all (situation, environment, finding).
WITH lines AS (
    SELECT coalesce(substring(i #>> '{productOrService,coding,0,display}' FROM '\(([^()]*)\)\s*$'), '(no tag)') AS semantic_tag,
           i #>> '{productOrService,coding,0,code}' AS code
    FROM bronze.fhir_resource r, jsonb_array_elements(r.resource -> 'item') AS i
    WHERE r.resource_type = 'Claim' AND r.resource #>> '{type,coding,0,code}' <> 'pharmacy'
      AND i #>> '{productOrService,coding,0,system}' = 'http://snomed.info/sct'
)
SELECT semantic_tag, count(DISTINCT code) AS codes, count(*) AS lines
FROM lines GROUP BY 1 ORDER BY 3 DESC;

\echo '--- E10. Where line charges live: EOB item submitted charge, summed vs Claim.total ---'
WITH eob_lines AS (
    SELECT regexp_replace(r.resource #>> '{claim,reference}', '^(urn:uuid:|Claim/)', '') AS claim_id,
           (a #>> '{amount,value}')::numeric AS submitted
    FROM bronze.fhir_resource r,
         jsonb_array_elements(r.resource -> 'item') AS i,
         jsonb_array_elements(i -> 'adjudication') AS a
    WHERE r.resource_type = 'ExplanationOfBenefit'
      AND jsonb_typeof(i -> 'adjudication') = 'array'
      AND a #>> '{category,coding,0,code}' = 'https://bluebutton.cms.gov/resources/variables/line_sbmtd_chrg_amt'
),
per_claim AS (SELECT claim_id, sum(submitted) AS line_total, count(*) AS priced_lines FROM eob_lines GROUP BY 1)
SELECT count(*)                                                        AS claims_with_priced_lines,
       sum(p.priced_lines)                                             AS priced_lines,
       count(*) FILTER (WHERE round(p.line_total, 2) = h.billed_amount) AS line_total_equals_claim_total,
       count(*) FILTER (WHERE round(p.line_total, 2) <> h.billed_amount) AS line_total_differs
FROM per_claim p
JOIN silver.claim_header h ON h.source_system = 'SYNTHEA_FHIR' AND h.claim_id = p.claim_id;

\echo '--- E11. Non-pharmacy claims WITHOUT any diagnosis, by encounter type (first line) ---'
SELECT r.resource #>> '{item,0,productOrService,coding,0,code}'              AS encounter_code,
       left(r.resource #>> '{item,0,productOrService,coding,0,display}', 50) AS encounter_type,
       count(*)                                                              AS claims,
       count(*) FILTER (WHERE NOT r.resource ? 'diagnosis')                  AS without_diagnosis,
       round(100.0 * count(*) FILTER (WHERE NOT r.resource ? 'diagnosis') / count(*), 1) AS pct_without
FROM bronze.fhir_resource r
WHERE r.resource_type = 'Claim' AND r.resource #>> '{type,coding,0,code}' <> 'pharmacy'
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 20;

\echo '--- E12. EOB careTeam: who the rendering provider is ---'
SELECT ct #>> '{role,coding,0,code}'                                          AS care_team_role,
       regexp_replace(ct #>> '{provider,reference}', '[|?/:][^|?/:]*$', '|<id>') AS provider_reference_pattern,
       count(*)                                                                AS eobs
FROM bronze.fhir_resource r, jsonb_array_elements(r.resource -> 'careTeam') AS ct
WHERE r.resource_type = 'ExplanationOfBenefit'
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 5;

\echo '--- E13. Dental share (dental claims use CDT codes on an 837D; CDT is ADA-licensed) ---'
SELECT count(*) FILTER (WHERE r.resource::text ~* 'dental|tooth|teeth|gingiv|periodont') AS claims_with_dental_lines,
       count(*)                                                                         AS non_pharmacy_claims
FROM bronze.fhir_resource r
WHERE r.resource_type = 'Claim' AND r.resource #>> '{type,coding,0,code}' <> 'pharmacy';

\echo '--- Export: every non-pharmacy line code for the service-line crosswalk (codes only, no PHI) ---'
\copy (SELECT i #>> '{productOrService,coding,0,code}' AS snomed_code, i #>> '{productOrService,coding,0,display}' AS description, coalesce(substring(i #>> '{productOrService,coding,0,display}' FROM '\(([^()]*)\)\s*$'), '(no tag)') AS semantic_tag, count(*) AS lines, count(*) FILTER (WHERE (i ->> 'sequence') = '1') AS as_first_line FROM bronze.fhir_resource r, jsonb_array_elements(r.resource -> 'item') AS i WHERE r.resource_type = 'Claim' AND r.resource #>> '{type,coding,0,code}' <> 'pharmacy' AND i #>> '{productOrService,coding,0,system}' = 'http://snomed.info/sct' GROUP BY 1, 2, 3 ORDER BY 4 DESC) TO 'docs/mapping/snomed_service_line_codes.csv' CSV HEADER
