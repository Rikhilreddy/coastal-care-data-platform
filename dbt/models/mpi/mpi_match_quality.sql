-- MPI step 4: measure matching against the answer key (audit.mpi_test_truth), which the
-- matcher never sees. precision = correct auto-links / all auto-links;
-- recall = correct auto-links / records that have a true member.
with judged as (
    select l.*, t.true_member_id, t.noise,
           case
               when l.decision = 'AUTO_LINK' and l.linked_member_id = t.true_member_id then 'TRUE_LINK'
               when l.decision = 'AUTO_LINK'                                          then 'FALSE_LINK'
               when l.decision = 'REVIEW'                                             then 'SENT_TO_REVIEW'
               else 'MISSED'
           end as outcome
    from {{ ref('mpi_link') }} l
    left join {{ source('audit', 'mpi_test_truth') }} t
      on t.source_system = l.source_system and t.source_record_id = l.source_record_id
)
select source_system,
       count(*)                                                        as records,
       count(*) filter (where outcome = 'TRUE_LINK')                   as true_links,
       count(*) filter (where outcome = 'FALSE_LINK')                  as false_links,
       count(*) filter (where outcome = 'SENT_TO_REVIEW')              as sent_to_review,
       count(*) filter (where outcome = 'MISSED')                      as missed,
       count(*) filter (where noise is not null)                       as records_with_noise,
       round(count(*) filter (where outcome = 'TRUE_LINK')::numeric
             / nullif(count(*) filter (where decision = 'AUTO_LINK'), 0), 4) as precision,
       round(count(*) filter (where outcome = 'TRUE_LINK')::numeric
             / nullif(count(*) filter (where true_member_id is not null), 0), 4) as recall
from judged group by source_system
