-- EDI-3 X12 balancing on RECEIVED 835s: line charge = paid + adjustments; claim CLP03/CLP04 =
-- sum of its lines; payment BPR02 = sum of its CLP04. A receiver rejects an unbalanced 835.
with line_check as (
    select _source_file, claim_id, line_number, 'LINE' as level
    from {{ ref('edi_inbound_835_line') }} where charge <> paid + total_adjustment
),
claim_check as (
    select c._source_file, c.claim_id, null::bigint as line_number, 'CLAIM' as level
    from {{ ref('edi_inbound_835_claim') }} c
    join (select _source_file, claim_id, sum(charge) as charge, sum(paid) as paid
          from {{ ref('edi_inbound_835_line') }} group by 1, 2) l using (_source_file, claim_id)
    where c.charge <> l.charge or c.paid <> l.paid
),
payment_check as (
    select _source_file, min(claim_id) as claim_id, null::bigint, 'PAYMENT'
    from {{ ref('edi_inbound_835_claim') }}
    group by _source_file, payment_seq, payment_amount
    having payment_amount <> sum(paid)
)
select * from line_check union all select * from claim_check union all select * from payment_check
