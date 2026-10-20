-- One row per member per source system (stable demographics).
-- Cross-source matching (is DE-SynPUF member X the same person as FHIR patient Y?) is
-- NOT done here: that is the master patient index (MPI) ticket in Sprint 3.
select source_system, member_source_id, birth_date, death_date, sex_code, race_code,
       first_coverage_year, last_coverage_year, birth_date_conflict
from {{ ref('stg_desynpuf__member') }}
union all
select source_system, member_source_id, birth_date, death_date, sex_code, race_code,
       null::int as first_coverage_year, null::int as last_coverage_year, false as birth_date_conflict
from {{ ref('stg_fhir__patient') }}
