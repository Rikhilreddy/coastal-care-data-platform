-- GOLD-4 charge outliers (H32): a billed line is an outlier when it is above the 99th
-- percentile for its procedure code AND more than 3x the median, with at least 20 lines of
-- history for that code. Sent as billed; flagged for payment-integrity review.
with lines as (
    select claim_id, line_sequence, procedure_code, line_charge, service_date
    from {{ ref('edi_claim_line') }}
    where line_role = 'SERVICE' and procedure_code is not null and line_charge > 0
),
stats as (
    select procedure_code, count(*) as n,
           percentile_cont(0.5) within group (order by line_charge)  as median_charge,
           percentile_cont(0.99) within group (order by line_charge) as p99_charge
    from lines group by procedure_code having count(*) >= 20
)
select l.*, s.n as code_line_count, round(s.median_charge::numeric, 2) as median_charge,
       round(s.p99_charge::numeric, 2) as p99_charge,
       round(l.line_charge / nullif(s.median_charge::numeric, 0), 1) as times_median
from lines l join stats s using (procedure_code)
where l.line_charge > s.p99_charge and l.line_charge > 3 * s.median_charge
