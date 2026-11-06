-- GOLD-3 readmission rate by source, line of business and discharge year (dashboard-ready).
select source_system, line_of_business, extract(year from discharge_date)::int as discharge_year,
       count(*) as index_stays, count(*) filter (where is_readmitted_30d) as readmissions,
       round(100.0 * count(*) filter (where is_readmitted_30d) / count(*), 2) as readmission_rate_pct
from {{ ref('mart_readmission_30d') }}
group by 1, 2, 3
