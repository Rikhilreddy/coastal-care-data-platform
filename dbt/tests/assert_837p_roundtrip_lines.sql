-- EDI-2 round trip, line level: the received service lines equal the SERVICE lines that were
-- sent (same count, order, procedure code, charge, service date) for every received claim.
with sent as (
    select l.claim_id,
           row_number() over (partition by l.claim_id order by l.line_sequence) as line_number,
           l.procedure_code, l.line_charge, l.service_date
    from {{ ref('edi_claim_line') }} l
    where l.line_role = 'SERVICE'
      and l.claim_id in (select claim_id from {{ ref('edi_inbound_837p_claim') }})
),
received as (
    select claim_id, line_number, procedure_code, line_charge, service_date
    from {{ ref('edi_inbound_837p_line') }}
)
select coalesce(s.claim_id, r.claim_id) as claim_id, coalesce(s.line_number, r.line_number) as line_number,
       s.procedure_code as sent_code, r.procedure_code as received_code,
       s.line_charge as sent_charge, r.line_charge as received_charge
from sent s
full outer join received r on r.claim_id = s.claim_id and r.line_number = s.line_number
where s.claim_id is null or r.claim_id is null
   or s.procedure_code <> r.procedure_code
   or s.line_charge <> r.line_charge
   or s.service_date <> r.service_date
