-- EDI-1 reconciliation: for every READY claim, the 837 service lines (after bundling)
-- add up exactly to the claim's billed amount, so CLM02 = sum of SV102 (X12 rule).
select claim_id, billed_amount, service_line_total
from {{ ref('edi_claim_readiness') }}
where reject_reason is null
  and service_line_total <> billed_amount
