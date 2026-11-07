-- SCD-2 integrity: every member has exactly one current version, and versions never overlap
-- (each version starts where the previous one ended).
with v as (
    select member_key, valid_from, valid_to, is_current,
           lead(valid_from) over (partition by member_key order by valid_from) as next_from
    from {{ ref('dim_member_history') }}
)
select member_key, 'NOT_ONE_CURRENT' as issue from v group by member_key having count(*) filter (where is_current) <> 1
union all
select member_key, 'GAP_OR_OVERLAP' from v where next_from is not null and valid_to is distinct from next_from
