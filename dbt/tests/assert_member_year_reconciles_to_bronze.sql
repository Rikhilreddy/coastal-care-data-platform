-- Reconciliation: every bronze beneficiary row becomes exactly one member_year row,
-- and reported Medicare reimbursement dollars match to the cent.
-- A data test passes when this query returns ZERO rows.
with bronze as (
    select count(*) as row_count,
           sum(coalesce(nullif(btrim(medreimb_ip), ''), '0')::numeric
             + coalesce(nullif(btrim(medreimb_op), ''), '0')::numeric
             + coalesce(nullif(btrim(medreimb_car), ''), '0')::numeric) as dollars
    from {{ source('bronze', 'desynpuf_beneficiary') }}
), silver as (
    select count(*) as row_count,
           sum(reported_ip_medicare_paid + reported_op_medicare_paid + reported_car_medicare_paid) as dollars
    from {{ ref('member_year') }}
)
select b.row_count as bronze_rows, s.row_count as silver_rows,
       b.dollars as bronze_dollars, s.dollars as silver_dollars
from bronze b cross join silver s
where b.row_count <> s.row_count or b.dollars <> s.dollars
