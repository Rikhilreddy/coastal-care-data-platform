-- EDI-1 governance: every visit-reason ICD-10-CM code is a valid, billable FY2027 code,
-- and APPROVED rules are signed.
with codes as (
    select encounter_code, review_status, reviewed_by, review_date,
           unnest(string_to_array(icd10_code, '|')) as icd10_code
    from {{ ref('encounter_reason_dx') }}
)
select c.*, i.is_billable
from codes c
left join {{ source('ref', 'icd10cm') }} i on i.icd10_code = c.icd10_code
where i.icd10_code is null or not i.is_billable
   or (c.review_status = 'APPROVED' and (c.reviewed_by is null or c.review_date is null))
