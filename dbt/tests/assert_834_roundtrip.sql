-- EDI-4 round trip: for every 834 file loaded, the coverage spans received equal the spans in
-- the enrollment history it was generated from (bronze), for the same payer and window:
-- nothing lost, nothing invented, same dates. The window is the one the generator recorded
-- in audit.edi_file_manifest for that file.
with files as (
    select distinct on (m.payer_name) m.payer_name, m.service_month as window_start,
           regexp_replace(m.file_path, '^.*/', '') as file_name
    from {{ source('audit', 'edi_file_manifest') }} m
    where m.transaction_set = '834'
      and regexp_replace(m.file_path, '^.*/', '') in (select distinct _source_file from {{ ref('edi_inbound_834_member') }})
    order by m.payer_name, m.created_at desc
),
expected as (
    select upper(t.memberid) as subscriber_id, upper(p.name) as payer_name,
           left(t.start_date, 10)::date as coverage_begin, nullif(left(t.end_date, 10), '')::date as coverage_end
    from {{ source('bronze', 'synthea_payer_transitions') }} t
    join {{ source('bronze', 'synthea_payers') }} p on p.id = t.payer
    join files f on f.payer_name = p.name
    join {{ ref('member_identity') }} i on i.source_system = 'SYNTHEA_FHIR' and i.member_source_id = t.patient
    where coalesce(nullif(left(t.end_date, 10), '')::date, '9999-12-31') >= (f.window_start || '-01')::date
),
received as (
    select e.subscriber_id, e.payer_name, e.coverage_begin, e.coverage_end
    from {{ ref('edi_inbound_834_member') }} e
    join files f on f.file_name = e._source_file
)
(select 'MISSING_IN_834' as issue, * from expected except select 'MISSING_IN_834', * from received)
union all
(select 'NOT_IN_HISTORY', * from received except select 'NOT_IN_HISTORY', * from expected)
