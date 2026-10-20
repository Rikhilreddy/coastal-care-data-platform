-- Referential integrity, all sources: every claim's member exists in silver.member
-- for the SAME source system (member IDs from different systems must never cross-match).
select h.source_system, h.claim_id, h.member_source_id
from {{ ref('claim_header') }} h
left join {{ ref('member') }} m
  on m.source_system    = h.source_system
 and m.member_source_id = h.member_source_id
where m.member_source_id is null
