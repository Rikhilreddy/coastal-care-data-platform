-- GOLD-1 calendar dimension, one row per day. The range comes from the data itself (Synthea
-- histories reach back decades), padded to whole years and at least 2007-2030, so every
-- claim date always has a calendar row (tested by a relationships test on fct_claim).
with bounds as (
    select least(date_trunc('year', min(claim_from_date)), '2007-01-01')::date                  as first_day,
           greatest(date_trunc('year', max(claim_from_date)) + interval '1 year - 1 day', '2030-12-31')::date as last_day
    from {{ ref('claim_header') }}
)
select d::date                                   as date_day,
       to_char(d, 'YYYYMMDD')::int               as date_key,
       extract(year from d)::int                 as year,
       extract(quarter from d)::int              as quarter,
       extract(month from d)::int                as month,
       to_char(d, 'YYYY-MM')                     as year_month,
       to_char(d, 'Dy')                          as day_name,
       extract(isodow from d) in (6, 7)          as is_weekend
from bounds, generate_series(bounds.first_day, bounds.last_day, interval '1 day') d
