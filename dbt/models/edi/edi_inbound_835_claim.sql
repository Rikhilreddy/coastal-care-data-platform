-- EDI-3: one row per claim payment (CLP) received in an 835, with its payment (BPR) context.
with seg as (select * from {{ ref('stg_x12__835_segment') }}),
bpr as (select _source_file, payment_seq, elements[2]::numeric(14,2) as payment_amount, elements[4] as payment_method
        from seg where segment_id = 'BPR'),
trn as (select _source_file, payment_seq, elements[2] as trace_number from seg where segment_id = 'TRN'),
payee as (select _source_file, payment_seq, elements[2] as payee_name, elements[4] as payee_npi
          from seg where segment_id = 'N1' and elements[1] = 'PE'),
payer as (select _source_file, payment_seq, elements[2] as payer_name
          from seg where segment_id = 'N1' and elements[1] = 'PR'),
clp as (select _source_file, payment_seq, claim_seq,
               elements[1] as claim_id, elements[2] as claim_status,
               elements[3]::numeric(14,2) as charge, elements[4]::numeric(14,2) as paid,
               nullif(elements[5], '')::numeric(14,2) as patient_responsibility,
               elements[6] as claim_filing_indicator, elements[7] as payer_claim_control
        from seg where segment_id = 'CLP')
select c._source_file, c.payment_seq, c.claim_seq, c.claim_id, c.claim_status, c.charge, c.paid,
       coalesce(c.patient_responsibility, 0) as patient_responsibility, c.claim_filing_indicator,
       c.payer_claim_control, p.payer_name, e.payee_name, e.payee_npi, t.trace_number,
       b.payment_amount, b.payment_method
from clp c
left join bpr b   on b._source_file = c._source_file and b.payment_seq = c.payment_seq
left join trn t   on t._source_file = c._source_file and t.payment_seq = c.payment_seq
left join payee e on e._source_file = c._source_file and e.payment_seq = c.payment_seq
left join payer p on p._source_file = c._source_file and p.payment_seq = c.payment_seq
