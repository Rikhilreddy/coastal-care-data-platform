-- One row per PRICED ExplanationOfBenefit line (H24, H26): the lines the 837 and 835 are built from.
-- Adjudication amounts are picked by category (Blue Button variables), rounded to cents (H17).
-- Claim lines that are diagnoses repeated as items are not priced on the EOB and never appear here (H31).
{%- set bb = 'https://bluebutton.cms.gov/resources/variables/' %}
with eob as (
    select resource as r
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type = 'ExplanationOfBenefit'
)
select
    regexp_replace(eob.r #>> '{claim,reference}', '^(urn:uuid:|Claim/)', '')         as claim_id,
    (i ->> 'sequence')::int                                                           as line_sequence,
    case i #>> '{productOrService,coding,0,system}'
        when 'http://snomed.info/sct'       then 'SNOMEDCT'
        when 'http://loinc.org'             then 'LOINC'
        when 'http://hl7.org/fhir/sid/cvx'  then 'CVX'
        else 'OTHER'
    end                                                                               as code_system,
    i #>> '{productOrService,coding,0,code}'                                          as source_code,
    i #>> '{productOrService,coding,0,display}'                                       as description,
    coalesce(substring(i #>> '{productOrService,coding,0,display}' from '\(([^()]*)\)\s*$'), '(no tag)') as semantic_tag,
    {{ bb_adjudication('i', 'line_sbmtd_chrg_amt') }}                                                  as charge,
    {{ bb_adjudication('i', 'line_alowd_chrg_amt') }}                                                  as allowed,
    {{ bb_adjudication('i', 'line_prvdr_pmt_amt') }}                                                   as paid,
    {{ bb_adjudication('i', 'line_bene_ptb_ddctbl_amt') }}                                             as deductible,
    {{ bb_adjudication('i', 'line_coinsrnc_amt') }}                                                    as coinsurance,
    left(i #>> '{servicedPeriod,start}', 10)::date                                    as service_date,
    i #>> '{locationCodeableConcept,coding,0,code}'                                   as place_of_service,
    regexp_replace(eob.r #>> '{careTeam,0,provider,reference}', '^.*\|', '')          as rendering_npi  -- H27
from eob
cross join lateral jsonb_array_elements(eob.r -> 'item') as i
where jsonb_path_exists(i, '$.adjudication[*] ? (@.category.coding[0].code == "{{ bb }}line_sbmtd_chrg_amt")')
