-- GOLD-4 data-quality scorecard for the dashboard: aggregate counts only (no identifiers),
-- so analysts can see pipeline health without access to PHI-bearing schemas.
select 'MPI auto-link precision' as metric, source_system as scope, precision as value from {{ ref('mpi_match_quality') }}
union all select 'MPI recall', source_system, recall from {{ ref('mpi_match_quality') }}
union all select 'MPI records sent to review', source_system, sent_to_review from {{ ref('mpi_match_quality') }}
union all select 'Claims quarantined', 'ALL', count(*) from {{ ref('claim_exception') }}
union all select 'Code values quarantined', 'ALL', count(*) from {{ ref('code_exception') }}
union all select 'Charge outlier lines', 'ALL', count(*) from {{ ref('mart_charge_outlier') }}
union all select 'Claims ready for 837P', 'ALL', count(*) filter (where coalesce(reject_reason, '') = '') from {{ ref('edi_claim_readiness') }}
union all select 'Claims held by pre-submission edits', 'ALL', count(*) filter (where coalesce(reject_reason, '') <> '') from {{ ref('edi_claim_readiness') }}
union all
select 'Provider NPIs checked against NPPES: ' || lookup_status, 'ALL', count(*) from {{ ref('provider_registry') }} group by lookup_status
