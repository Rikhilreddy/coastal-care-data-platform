-- CONV-4 governance: every ICD-10-CM target must be a valid, BILLABLE FY2027 code
-- (it will go on an 837), and NOT_CODABLE rows must have no target. Checked for every row,
-- PROPOSED included, so a reviewer never approves an invalid code.
select x.snomed_code, x.snomed_description, x.category, x.icd10_code,
       case when x.category = 'NOT_CODABLE' and x.icd10_code is not null then 'NOT_CODABLE_HAS_TARGET'
            when x.category <> 'NOT_CODABLE' and x.icd10_code is null    then 'MISSING_TARGET'
            when i.icd10_code is null                                    then 'NOT_IN_FY2027'
            else 'NOT_BILLABLE' end as problem
from {{ ref('snomed_icd10_crosswalk') }} x
left join {{ source('ref', 'icd10cm') }} i on i.icd10_code = x.icd10_code
where (x.category = 'NOT_CODABLE' and x.icd10_code is not null)
   or (x.category <> 'NOT_CODABLE' and x.icd10_code is null)
   or (x.icd10_code is not null and (i.icd10_code is null or not i.is_billable))
