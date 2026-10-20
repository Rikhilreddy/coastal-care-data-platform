-- Coverage months must be 0–12 (STTM rule). Returns offending rows; zero rows = pass.
select member_source_id, coverage_year, part_a_months, part_b_months, hmo_months, part_d_months
from {{ ref('member_year') }}
where part_a_months not between 0 and 12
   or part_b_months not between 0 and 12
   or hmo_months    not between 0 and 12
   or part_d_months not between 0 and 12
