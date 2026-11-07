-- Incremental safety net: whatever the watermark did, the incremental table must hold exactly
-- the messages in bronze: none missed (late or re-sent files), none left over.
with bronze as (select distinct message_control_id from {{ source('bronze', 'hl7_segment') }} where segment_id = 'MSH'),
built  as (select message_control_id from {{ ref('hl7_adt_event') }})
(select 'MISSING_FROM_INCREMENTAL' as issue, message_control_id from bronze except select 'MISSING_FROM_INCREMENTAL', message_control_id from built)
union all
(select 'NOT_IN_BRONZE', message_control_id from built except select 'NOT_IN_BRONZE', message_control_id from bronze)
