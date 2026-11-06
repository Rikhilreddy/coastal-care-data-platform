-- GOLD-1 claim fact, one row per claim (net of adjustments: a recoupment is a negative row).
select
    md5(c.source_system || '|' || c.claim_id)                            as claim_key,
    md5(c.source_system || '|' || c.member_source_id)                    as member_key,
    to_char(c.claim_from_date, 'YYYYMMDD')::int                          as service_date_key,
    c.source_system, c.claim_id, c.claim_type,
    {{ line_of_business('c.payer_name') }}                               as line_of_business,
    c.payer_name, c.claim_from_date, c.claim_thru_date, c.claim_year,
    c.admission_date, c.discharge_date, c.drg_code, c.utilization_days,
    c.billed_amount, c.paid_amount, c.is_adjustment
from {{ ref('claim_header') }} c
