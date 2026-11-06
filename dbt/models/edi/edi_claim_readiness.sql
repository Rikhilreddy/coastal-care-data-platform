-- EDI-1 pre-submission edits ("front-end edits"): one row per non-pharmacy FHIR claim.
-- Every claim ends READY or REJECTED with ONE primary reason, so in-scope claims always
-- reconcile: claims = READY + REJECTED, in count and dollars.
-- usage_indicator (X12 ISA15): 'P' = every mapping used is APPROVED (production);
--                              'T' = relies on PROPOSED mappings (test files only).
{%- set dental = "'dental|tooth|teeth|gingiv|periodont|dentur|torus|fluoride|oral (or dental )?impression|lingual|alveol|plaque|frenum|orthodont|mandib|wisdom'" %}
with claim as (
    select h.*, m.birth_date
    from {{ ref('claim_header') }} h
    left join {{ ref('member') }} m
      on m.source_system = h.source_system and m.member_source_id = h.member_source_id
    where h.source_system = 'SYNTHEA_FHIR' and h.claim_type <> 'RX'
),
lines as (
    select claim_id,
           count(*) filter (where line_role = 'SERVICE')                 as service_lines,
           count(*) filter (where line_role = 'UNMAPPED')                as unmapped_lines,
           coalesce(sum(line_charge) filter (where line_role = 'SERVICE'), 0) as service_line_total,
           bool_or(description ~* {{ dental }})                          as has_dental_line,
           bool_and(crosswalk_status is null or crosswalk_status = 'APPROVED') as lines_all_approved,
           max(place_of_service) filter (where is_anchor_line)           as place_of_service,
           max(rendering_npi)                                            as rendering_npi,
           max(source_code) filter (where line_sequence = 1)             as encounter_code
    from {{ ref('edi_claim_line') }}
    group by claim_id
),
dx as (   -- claim diagnoses with their crosswalk target (PROPOSED included, for test files)
    select d.claim_id, d.dx_position, x.icd10_code, x.review_status
    from {{ ref('claim_diagnosis') }} d
    join {{ ref('snomed_icd10_crosswalk') }} x on x.snomed_code = d.source_code
    where d.source_system = 'SYNTHEA_FHIR'
      and x.category <> 'NOT_CODABLE' and x.icd10_code is not null and x.review_status <> 'REJECTED'
),
dx_ranked as (
    select claim_id, icd10_code, review_status,
           row_number() over (partition by claim_id order by min_pos) as rn
    from (select claim_id, icd10_code, min(dx_position) as min_pos,
                 min(review_status) as review_status   -- 'APPROVED' < 'PROPOSED'
          from dx group by claim_id, icd10_code) t
),
dx_claim as (
    select claim_id,
           array_agg(icd10_code order by rn) filter (where rn <= 12) as icd10_codes,   -- 837P HI allows 12
           bool_and(review_status = 'APPROVED')                       as dx_all_approved
    from dx_ranked group by claim_id
),
reason_rule as (
    select encounter_code, icd10_rule, icd10_code, review_status
    from {{ ref('encounter_reason_dx') }} where review_status <> 'REJECTED'
)
select
    c.source_system,
    c.claim_id,
    c.claim_type,
    c.payer_name,
    c.member_source_id,
    c.provider_id,
    l.rendering_npi,
    coalesce(l.place_of_service, '11')                                  as place_of_service,
    c.claim_from_date,
    c.claim_thru_date,
    c.billed_amount,
    coalesce(l.service_lines, 0)                                        as service_lines,
    coalesce(l.service_line_total, 0)                                   as service_line_total,
    coalesce(d.icd10_codes,
             case when r.icd10_rule = 'FIXED' then array[r.icd10_code]
                  when r.icd10_rule = 'BY_AGE' then
                       array[case when date_part('year', age(c.claim_from_date, c.birth_date)) >= 18
                                  then split_part(r.icd10_code, '|', 1) else split_part(r.icd10_code, '|', 2) end]
             end)                                                       as icd10_codes,
    case when d.icd10_codes is not null then 'CLAIM_DIAGNOSIS'
         when r.encounter_code is not null then 'ENCOUNTER_REASON_RULE' end as dx_source,
    case
        when c.payer_name = 'NO_INSURANCE'                 then 'SELF_PAY'                    -- H30
        when c.claim_type in ('IP', 'OP')                  then 'INSTITUTIONAL_837I_BACKLOG'  -- 837I is a later ticket
        when l.has_dental_line                             then 'DENTAL_OUT_OF_SCOPE'         -- H29 (CDT licensed)
        when coalesce(l.unmapped_lines, 0) > 0             then 'UNMAPPED_SERVICE_CODE'
        when coalesce(l.service_lines, 0) = 0              then 'NO_BILLABLE_SERVICE'
        when d.icd10_codes is null and r.encounter_code is null then 'NO_DIAGNOSIS'          -- H21, H28
    end                                                                 as reject_reason,
    case when coalesce(l.lines_all_approved, false)
          and coalesce(d.dx_all_approved, r.review_status = 'APPROVED', false)
         then 'P' else 'T' end                                          as usage_indicator
from claim c
left join lines l        on l.claim_id = c.claim_id
left join dx_claim d     on d.claim_id = c.claim_id
left join reason_rule r  on r.encounter_code = l.encounter_code
