-- Admission/discharge dates may appear only on IP claims (all sources).
-- Guards readmission metrics from counting pharmacy or professional claims as admissions.
select source_system, claim_id, claim_type, admission_date
from {{ ref('claim_header') }}
where claim_type <> 'IP'
  and (admission_date is not null or discharge_date is not null)
