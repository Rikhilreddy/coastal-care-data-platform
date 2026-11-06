-- EDI-2 round trip, claim level: every claim received in an 837P must match, field by field,
-- the READY claim it was generated from (total, payer, member, rendering NPI, diagnoses).
-- Any difference means the file was altered or mis-parsed between sender and receiver.
select i._source_file, i.claim_id,
       case
         when r.claim_id is null                             then 'NOT_A_READY_SOURCE_CLAIM'
         when r.reject_reason is not null                    then 'SOURCE_CLAIM_WAS_REJECTED'
         when i.total_charge <> r.billed_amount              then 'TOTAL_CHARGE'
         when upper(i.payer_name) <> upper(r.payer_name)     then 'PAYER'
         when i.member_source_id <> lower(r.member_source_id) then 'MEMBER'
         when coalesce(i.rendering_npi, '') <> coalesce(r.rendering_npi, '') then 'RENDERING_NPI'
         when i.icd10_codes <> r.icd10_codes                 then 'DIAGNOSES'
       end as mismatch
from {{ ref('edi_inbound_837p_claim') }} i
left join {{ ref('edi_claim_readiness') }} r on r.claim_id = i.claim_id
where r.claim_id is null
   or r.reject_reason is not null
   or i.total_charge <> r.billed_amount
   or upper(i.payer_name) <> upper(r.payer_name)
   or i.member_source_id <> lower(r.member_source_id)
   or coalesce(i.rendering_npi, '') <> coalesce(r.rendering_npi, '')
   or i.icd10_codes <> r.icd10_codes
