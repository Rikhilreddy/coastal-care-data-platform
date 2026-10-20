-- Reconciliation, FHIR: every bronze Patient becomes exactly one silver.member row and
-- one silver.member_identity row.
select
    (select count(*) from {{ source('bronze', 'fhir_resource') }} where resource_type = 'Patient') as bronze_patients,
    (select count(*) from {{ ref('member') }} where source_system = 'SYNTHEA_FHIR')            as silver_members,
    (select count(*) from {{ ref('member_identity') }} where source_system = 'SYNTHEA_FHIR')   as identity_rows
where (select count(*) from {{ source('bronze', 'fhir_resource') }} where resource_type = 'Patient')
      <> (select count(*) from {{ ref('member') }} where source_system = 'SYNTHEA_FHIR')
   or (select count(*) from {{ source('bronze', 'fhir_resource') }} where resource_type = 'Patient')
      <> (select count(*) from {{ ref('member_identity') }} where source_system = 'SYNTHEA_FHIR')
