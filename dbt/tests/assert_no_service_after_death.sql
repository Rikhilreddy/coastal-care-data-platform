-- F16 / H18 payment integrity, all sources: no claim may start after the member's death.
-- One documented exception: death certification (SNOMED 308646001), a physician service
-- that legitimately happens after death (H18). Any other post-death claim fails the build.
with post_death as (
    select h.source_system, h.claim_id, h.member_source_id, h.claim_type,
           h.claim_from_date, m.death_date, h.paid_amount
    from {{ ref('claim_header') }} h
    join {{ ref('member') }} m
      on m.source_system    = h.source_system
     and m.member_source_id = h.member_source_id
    where m.death_date is not null
      and h.claim_from_date > m.death_date
),
death_certification as (
    select resource_id as claim_id
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type = 'Claim'
      and resource #>> '{item,0,productOrService,coding,0,code}' = '308646001'
)
select p.*
from post_death p
left join death_certification d
  on p.source_system = 'SYNTHEA_FHIR'
 and d.claim_id = p.claim_id
where d.claim_id is null
