-- CONV-4 governance: a FHIR diagnosis may carry an ICD-10-CM code ONLY if it came from an
-- APPROVED crosswalk row (conversion_method = CROSSWALK), and every CROSSWALK row has one.
select claim_id, dx_position, source_code, icd10_code, conversion_method
from {{ ref('claim_diagnosis') }}
where source_system = 'SYNTHEA_FHIR'
  and ((icd10_code is not null and conversion_method <> 'CROSSWALK')
    or (icd10_code is null and conversion_method = 'CROSSWALK'))
