-- Reconciliation, FHIR: bronze Claim count, billed dollars (Claim.total) and paid dollars
-- (EOB.payment) must equal the FHIR rows in silver.claim_header, to the cent.
-- H17: 46% of EOB payments carry floating-point artifacts (e.g. 103.32800000000001).
-- Money is stored in cents, so the control total is defined as the sum of each amount
-- ROUNDED TO CENTS PER CLAIM. Summing raw floats would differ by rounding, not by data.
with bronze as (
    select
        count(*) filter (where resource_type = 'Claim') as claims,
        coalesce(sum(round((resource #>> '{total,value}')::numeric, 2))
                 filter (where resource_type = 'Claim'), 0) as billed,
        coalesce(sum(round((resource #>> '{payment,amount,value}')::numeric, 2))
                 filter (where resource_type = 'ExplanationOfBenefit'), 0) as paid
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type in ('Claim', 'ExplanationOfBenefit')
),
silver as (
    select count(*) as claims,
           coalesce(sum(billed_amount), 0) as billed,
           coalesce(sum(paid_amount), 0)   as paid
    from {{ ref('claim_header') }}
    where source_system = 'SYNTHEA_FHIR'
)
select b.*, s.claims as silver_claims, s.billed as silver_billed, s.paid as silver_paid
from bronze b cross join silver s
where b.claims <> s.claims or b.billed <> s.billed or b.paid <> s.paid
