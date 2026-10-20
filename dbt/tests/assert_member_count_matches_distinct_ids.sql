-- Every distinct member in bronze appears exactly once in silver.member (none lost, none invented).
select (select count(distinct btrim(desynpuf_id)) from {{ source('bronze', 'desynpuf_beneficiary') }}) as bronze_members,
       (select count(*) from {{ ref('member') }}) as silver_members
where (select count(distinct btrim(desynpuf_id)) from {{ source('bronze', 'desynpuf_beneficiary') }})
   <> (select count(*) from {{ ref('member') }})
