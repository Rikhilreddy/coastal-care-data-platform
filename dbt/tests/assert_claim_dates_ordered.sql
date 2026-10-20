{{ config(severity='warn') }}
-- Data quality (warn, not fail): a claim should not end before it starts.
select claim_id, claim_from_date, claim_thru_date
from {{ ref('claim_header') }}
where claim_thru_date < claim_from_date
