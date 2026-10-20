-- Reconciliation (rows and dollars), per claim type:
--   bronze segments = segments rolled into silver.claim_header + quarantined segments
-- Proves the roll-up neither dropped nor double-counted a segment or a cent.
with bronze as (
    select 'IP' as claim_type, count(*) as row_count,
           coalesce(sum(nullif(btrim(clm_pmt_amt), '')::numeric), 0) as dollars
    from {{ source('bronze', 'desynpuf_inpatient') }}
    union all
    select 'OP', count(*),
           coalesce(sum(nullif(btrim(clm_pmt_amt), '')::numeric), 0)
    from {{ source('bronze', 'desynpuf_outpatient') }}
),
silver as (
    select claim_type, sum(segment_count) as row_count, sum(paid_amount) as dollars
    from {{ ref('claim_header') }} where source_system = 'DESYNPUF' group by claim_type
),
quarantine as (
    select claim_type, count(*) as row_count, coalesce(sum(paid_amount), 0) as dollars
    from {{ ref('claim_exception') }} where source_system = 'DESYNPUF' group by claim_type
)
select
    b.claim_type,
    b.row_count                                              as bronze_rows,
    coalesce(s.row_count, 0) + coalesce(q.row_count, 0)      as silver_plus_quarantine_rows,
    b.dollars                                                as bronze_dollars,
    coalesce(s.dollars, 0) + coalesce(q.dollars, 0)          as silver_plus_quarantine_dollars
from bronze b
left join silver s     on s.claim_type = b.claim_type
left join quarantine q on q.claim_type = b.claim_type
where b.row_count <> coalesce(s.row_count, 0) + coalesce(q.row_count, 0)
   or b.dollars   <> coalesce(s.dollars, 0)   + coalesce(q.dollars, 0)
