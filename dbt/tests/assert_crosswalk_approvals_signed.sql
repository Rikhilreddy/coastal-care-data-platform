-- CONV-4 governance: an APPROVED mapping must name its reviewer and review date
-- (same rule the loader enforces for icd9_dx_overrides.csv). Git history shows who changed it.
select snomed_code, snomed_description, reviewed_by, review_date
from {{ ref('snomed_icd10_crosswalk') }}
where review_status = 'APPROVED'
  and (reviewed_by is null or btrim(reviewed_by) = '' or review_date is null)
