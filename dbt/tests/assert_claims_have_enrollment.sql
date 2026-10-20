-- F14: every claim belongs to a member enrolled in the claim year (thru-date year).
-- Was 0 failures in profiling; this keeps it at 0 on every run.
select h.claim_id, h.member_source_id, h.claim_year
from {{ ref('claim_header') }} h
left join {{ ref('member_year') }} m
  on m.member_source_id = h.member_source_id
 and m.coverage_year    = h.claim_year
where m.member_source_id is null
