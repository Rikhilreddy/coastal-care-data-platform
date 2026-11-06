-- EDI-1: every priced line of every non-pharmacy FHIR claim, classified for the 837.
--   SERVICE         -> its own 837 line (CPT/HCPCS from the service-line crosswalk)
--   BUNDLED         -> no line of its own; its charge is added to the claim's first SERVICE line
--   UNMAPPED        -> a service with no crosswalk row: the claim fails UNMAPPED_SERVICE_CODE
-- Lines whose SNOMED semantic tag is not a service (physical object, finding, ...) are BUNDLED by rule.
-- Preventive visits get CPT 99391-99397 from the patient's age on the date of service.
{%- set service_tags = "('procedure', 'regime/therapy', 'environment', '(no tag)')" %}
with line as (
    select l.*, h.member_source_id, m.birth_date
    from {{ ref('stg_fhir__eob_line') }} l
    join {{ ref('claim_header') }} h
      on h.source_system = 'SYNTHEA_FHIR' and h.claim_id = l.claim_id and h.claim_type <> 'RX'
    left join {{ ref('member') }} m
      on m.source_system = 'SYNTHEA_FHIR' and m.member_source_id = h.member_source_id
),
classified as (
    select
        l.*,
        x.line_category                                          as crosswalk_category,
        x.review_status                                          as crosswalk_status,
        case
            when x.source_code is not null then x.line_category
            when l.code_system in ('LOINC', 'CVX') then 'UNMAPPED'
            when l.code_system = 'SNOMEDCT' and l.semantic_tag in {{ service_tags }} then 'UNMAPPED'
            else 'BUNDLED'                                        -- non-service semantic tag: by rule
        end                                                      as line_category,
        case
            when x.procedure_code = 'PREVENTIVE' then
                case
                    when date_part('year', age(l.service_date, l.birth_date)) < 1  then '99391'
                    when date_part('year', age(l.service_date, l.birth_date)) < 5  then '99392'
                    when date_part('year', age(l.service_date, l.birth_date)) < 12 then '99393'
                    when date_part('year', age(l.service_date, l.birth_date)) < 18 then '99394'
                    when date_part('year', age(l.service_date, l.birth_date)) < 40 then '99395'
                    when date_part('year', age(l.service_date, l.birth_date)) < 65 then '99396'
                    else '99397'
                end
            else x.procedure_code
        end                                                      as procedure_code,
        (x.source_code is null)                                  as bundled_by_rule
    from line l
    left join {{ ref('service_line_crosswalk') }} x
      on x.code_system = l.code_system and x.source_code = l.source_code
),
normalized as (
    select c.*,
           case when c.line_category = 'E_M_BY_AGE' then 'SERVICE' else c.line_category end as line_role
    from classified c
),
anchor as (   -- the first SERVICE line receives the charges of BUNDLED lines
    select claim_id, min(line_sequence) as anchor_sequence
    from normalized where line_role = 'SERVICE' group by claim_id
),
bundled as (   -- bundled lines move ALL their amounts (charge and adjudication) to the anchor line
    select claim_id, sum(charge) as bundled_charge, sum(allowed) as bundled_allowed, sum(paid) as bundled_paid,
           sum(deductible) as bundled_deductible, sum(coinsurance) as bundled_coinsurance,
           count(*) as bundled_lines
    from normalized where line_role = 'BUNDLED' group by claim_id
)
select
    n.claim_id,
    n.line_sequence,
    n.code_system,
    n.source_code,
    n.description,
    n.semantic_tag,
    n.line_role,
    n.procedure_code,
    n.crosswalk_status,
    n.bundled_by_rule,
    n.charge                                                     as source_charge,
    case
        when n.line_role <> 'SERVICE' then 0
        when n.line_sequence = a.anchor_sequence then n.charge + coalesce(b.bundled_charge, 0)
        else n.charge
    end                                                          as line_charge,    -- what the 837 line bills
    {%- for f in ['allowed', 'paid', 'deductible', 'coinsurance'] %}
    case
        when n.line_role <> 'SERVICE' then 0
        when n.line_sequence = a.anchor_sequence then n.{{ f }} + coalesce(b.bundled_{{ f }}, 0)
        else n.{{ f }}
    end                                                          as line_{{ f }},   -- for the 835
    {%- endfor %}
    (n.line_sequence = a.anchor_sequence)                        as is_anchor_line,
    n.service_date,
    n.place_of_service,
    n.rendering_npi
from normalized n
left join anchor a  on a.claim_id = n.claim_id
left join bundled b on b.claim_id = n.claim_id
