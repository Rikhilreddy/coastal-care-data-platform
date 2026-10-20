-- F16 payment integrity: no claim may start after the member's recorded death.
select h.claim_id, h.member_source_id, h.claim_from_date, m.death_date
from {{ ref('claim_header') }} h
join {{ ref('member') }} m on m.member_source_id = h.member_source_id
where m.death_date is not null
  and h.claim_from_date > m.death_date
