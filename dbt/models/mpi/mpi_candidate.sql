-- MPI step 2: BLOCKING then SCORING.
-- Blocking keeps the comparison small: a member is a candidate only if they share the SSN,
-- or the birth date, or the first 3 letters of the last name + ZIP.
-- Scoring (points): SSN exact 6 | DOB exact 3, within 1 day 1 | last name exact 3, trigram
-- similarity >= 0.5 2 | first name exact 2, similarity >= 0.5 1 | sex 1 | ZIP 1.  Max 16.
-- Member names drop Synthea's numeric suffixes, as registration systems never have them.
with member as (
    select i.member_source_id,
           upper(regexp_replace(i.last_name, '\d+', '', 'g'))  as last_name,
           upper(regexp_replace(i.first_name, '\d+', '', 'g')) as first_name,
           m.birth_date, m.sex_code,
           nullif(regexp_replace(i.ssn, '\D', '', 'g'), '')     as ssn,
           left(i.postal_code, 5)                                as postal_code
    from {{ ref('member_identity') }} i
    join {{ ref('member') }} m using (source_system, member_source_id)
    where i.source_system = 'SYNTHEA_FHIR'
),
pairs as (
    select distinct s.source_system, s.source_record_id, m.member_source_id
    from {{ ref('mpi_source_record') }} s
    join member m
      on (s.ssn is not null and s.ssn = m.ssn)
      or s.birth_date = m.birth_date
      or (left(s.last_name, 3) = left(m.last_name, 3) and s.postal_code = m.postal_code)
)
select
    p.source_system, p.source_record_id, p.member_source_id,
    (case when s.ssn is not null and s.ssn = m.ssn then 6 else 0 end
     + case when s.birth_date = m.birth_date then 3
            when abs(s.birth_date - m.birth_date) <= 1 then 1 else 0 end
     + case when s.last_name = m.last_name then 3
            when similarity(s.last_name, m.last_name) >= 0.5 then 2 else 0 end
     + case when s.first_name = m.first_name then 2
            when similarity(s.first_name, m.first_name) >= 0.5 then 1 else 0 end
     + case when s.sex_code = m.sex_code then 1 else 0 end
     + case when s.postal_code = m.postal_code then 1 else 0 end)       as match_score,
    (s.ssn is not null and s.ssn = m.ssn)                                as ssn_match,
    (s.birth_date = m.birth_date)                                        as dob_match,
    round(similarity(s.last_name, m.last_name)::numeric, 2)              as last_name_similarity
from pairs p
join {{ ref('mpi_source_record') }} s using (source_system, source_record_id)
join member m using (member_source_id)
