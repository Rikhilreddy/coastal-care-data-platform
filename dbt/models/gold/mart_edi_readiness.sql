-- GOLD-4 claim submission readiness by payer and month: how many claims (and dollars) can be
-- sent as 837P, and why the rest are held (pre-submission edit). No member identifiers.
select {{ line_of_business('payer_name') }}                           as line_of_business,
       payer_name, to_char(claim_from_date, 'YYYY-MM')                as service_month,
       coalesce(nullif(reject_reason, ''), 'READY')                   as status,
       count(*)                                                       as claims,
       sum(billed_amount)                                             as billed_amount
from {{ ref('edi_claim_readiness') }}
group by 1, 2, 3, 4
