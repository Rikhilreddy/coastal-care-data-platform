-- EDI-3 claim lifecycle: a remitted claim has exactly one 835 payment (CLP) for the same usage
-- and the same charge, and no 835 pays a claim that was never received. Claims not yet
-- remitted are PENDING (accounts receivable), reported by assert_835_pending_claims (warn).
with sent as (select claim_id, usage_indicator, total_charge from {{ ref('edi_inbound_837p_claim') }}),
remit as (
    select c.claim_id, max(s.elements[15]) as usage_indicator, count(*) as payments, max(c.charge) as charge
    from {{ ref('edi_inbound_835_claim') }} c
    join {{ source('bronze', 'x12_segment') }} s on s._source_file = c._source_file and s.segment_id = 'ISA'
    group by c.claim_id
)
select coalesce(s.claim_id, r.claim_id) as claim_id, s.total_charge, r.charge, r.payments
from sent s
full outer join remit r on r.claim_id = s.claim_id and r.usage_indicator = s.usage_indicator
where s.claim_id is null or (r.claim_id is not null and (r.payments <> 1 or r.charge <> s.total_charge))
