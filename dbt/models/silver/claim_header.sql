-- One row per claim from every source system, in one canonical shape.
-- Source-specific logic lives in staging/int_<source>__claim_header.sql;
-- this model only unions them, selecting columns by name (macros/claim_header_columns.sql).
-- Adding a source (EDI 837 next) = one new int model + one line here.
select {{ claim_header_columns() }} from {{ ref('int_desynpuf__claim_header') }}
union all
select {{ claim_header_columns() }} from {{ ref('int_fhir__claim_header') }}
