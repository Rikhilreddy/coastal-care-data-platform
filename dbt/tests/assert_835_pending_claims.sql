{{ config(severity='warn') }}
-- EDI-3 accounts receivable: claims received on an 837P with no 835 remittance yet.
-- Expected between loading 837s and generating 835s; after the 835 run this must be 0.
select s.claim_id, s.payer_name, s._source_file
from {{ ref('edi_inbound_837p_claim') }} s
left join {{ ref('edi_inbound_835_claim') }} r on r.claim_id = s.claim_id
where r.claim_id is null
