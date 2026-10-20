-- F14: every DE-SynPUF claim belongs to a member enrolled in the claim year (thru-date year).
-- FHIR claims are excluded until enrollment arrives from the 834 / payer history (EDI-3).
select h.claim_id, h.member_source_id, h.claim_year
from {{ ref('claim_header') }} h
left join {{ ref('member_year') }} m
  on m.member_source_id = h.member_source_id
 and m.coverage_year    = h.claim_year
where h.source_system = 'DESYNPUF'
  and m.member_source_id is null
