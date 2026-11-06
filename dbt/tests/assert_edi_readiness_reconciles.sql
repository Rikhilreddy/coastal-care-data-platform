-- EDI-1 reconciliation: every non-pharmacy FHIR claim gets exactly one readiness row,
-- and READY + REJECTED equals the claim population in count and billed dollars.
with src as (
    select count(*) as claims, coalesce(sum(billed_amount), 0) as billed
    from {{ ref('claim_header') }} where source_system = 'SYNTHEA_FHIR' and claim_type <> 'RX'
), edi as (
    select count(*) as claims, coalesce(sum(billed_amount), 0) as billed
    from {{ ref('edi_claim_readiness') }}
)
select s.claims as source_claims, e.claims as edi_claims, s.billed as source_billed, e.billed as edi_billed
from src s cross join edi e
where s.claims <> e.claims or s.billed <> e.billed
