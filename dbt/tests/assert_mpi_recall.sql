{{ config(severity='warn') }}
-- MPI effectiveness: at least 97% of identities with a true member are auto-linked.
select * from {{ ref('mpi_match_quality') }} where recall < 0.97
