-- EDI-3 financial reconciliation: what the 835 paid on each claim equals what the payer's
-- EOB paid (silver.claim_header.paid_amount), allowing at most 1 cent per line of rounding
-- (EOB amounts are floats, H17; each 835 line is rounded to cents).
with remit as (
    select c.claim_id, c.paid, count(l.*) as lines
    from {{ ref('edi_inbound_835_claim') }} c
    left join {{ ref('edi_inbound_835_line') }} l on l._source_file = c._source_file and l.claim_id = c.claim_id
    group by c.claim_id, c.paid
)
select r.claim_id, r.paid as remit_paid, h.paid_amount as eob_paid, r.lines
from remit r
join {{ ref('claim_header') }} h on h.source_system = 'SYNTHEA_FHIR' and h.claim_id = r.claim_id
where abs(r.paid - h.paid_amount) > 0.01 * greatest(r.lines, 1)
