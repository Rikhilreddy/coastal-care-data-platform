-- MPI safety rule: an automatic link must NEVER join two different people
-- (a false link merges medical histories, a patient-safety and HIPAA incident).
-- Missed matches are acceptable; they go to review.
select * from {{ ref('mpi_match_quality') }} where false_links > 0
