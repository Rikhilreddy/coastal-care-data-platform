-- MPI step 3: DECISION per source record.
--   AUTO_LINK  best score >= 10 and clearly ahead of the runner-up (by >= 3 points)
--   REVIEW     best score 6-9, or a near tie: a data steward decides (never guessed)
--   NO_MATCH   best score < 6
with ranked as (
    select c.*,
           row_number() over (partition by source_system, source_record_id order by match_score desc, member_source_id) as rn,
           lead(match_score) over (partition by source_system, source_record_id order by match_score desc, member_source_id) as runner_up
    from {{ ref('mpi_candidate') }} c
)
select
    s.source_system, s.source_record_id,
    r.member_source_id                                         as best_member_id,
    coalesce(r.match_score, 0)                                 as best_score,
    r.runner_up                                                as runner_up_score,
    case
        when r.match_score >= 10 and r.match_score - coalesce(r.runner_up, 0) >= 3 then 'AUTO_LINK'
        when r.match_score >= 6                                                    then 'REVIEW'
        else 'NO_MATCH'
    end                                                        as decision,
    case when r.match_score >= 10 and r.match_score - coalesce(r.runner_up, 0) >= 3
         then r.member_source_id end                           as linked_member_id
from {{ ref('mpi_source_record') }} s
left join ranked r using (source_system, source_record_id)
where r.rn = 1 or r.rn is null
