-- EDI-1 governance: service-line crosswalk rows must be internally consistent and use valid codes.
--   SERVICE rows need a code; BUNDLED rows must not have one; E_M_BY_AGE uses the PREVENTIVE token.
--   Code format: CPT 5 digits, CPT Category II ####F, HCPCS Level II letter + 4 digits.
--   HCPCS Level II codes must exist in the CMS HCPCS file (ref.hcpcs). CPT is AMA-licensed:
--   format-checked only, no descriptions stored.
--   APPROVED rows must name a reviewer and date.
select x.code_system, x.source_code, x.line_category, x.procedure_code, x.procedure_code_type,
       case
         when x.line_category = 'SERVICE' and x.procedure_code is null              then 'SERVICE_WITHOUT_CODE'
         when x.line_category = 'BUNDLED' and x.procedure_code is not null          then 'BUNDLED_WITH_CODE'
         when x.line_category = 'E_M_BY_AGE' and x.procedure_code <> 'PREVENTIVE'  then 'E_M_BY_AGE_TOKEN'
         when x.procedure_code_type = 'CPT'      and x.procedure_code !~ '^\d{5}$'   then 'BAD_CPT_FORMAT'
         when x.procedure_code_type = 'CPT_CAT2' and x.procedure_code !~ '^\d{4}F$'  then 'BAD_CAT2_FORMAT'
         when x.procedure_code_type = 'HCPCS2'   and h.hcpcs_code is null            then 'HCPCS_NOT_IN_CMS_FILE'
         when x.review_status = 'APPROVED' and (x.reviewed_by is null or x.review_date is null) then 'APPROVAL_UNSIGNED'
       end as problem
from {{ ref('service_line_crosswalk') }} x
left join {{ source('ref', 'hcpcs') }} h on h.hcpcs_code = x.procedure_code
where (x.line_category = 'SERVICE' and x.procedure_code is null)
   or (x.line_category = 'BUNDLED' and x.procedure_code is not null)
   or (x.line_category = 'E_M_BY_AGE' and coalesce(x.procedure_code, '') <> 'PREVENTIVE')
   or (x.procedure_code_type = 'CPT' and x.procedure_code !~ '^\d{5}$')
   or (x.procedure_code_type = 'CPT_CAT2' and x.procedure_code !~ '^\d{4}F$')
   or (x.procedure_code_type = 'HCPCS2' and h.hcpcs_code is null)
   or (x.review_status = 'APPROVED' and (x.reviewed_by is null or x.review_date is null))
