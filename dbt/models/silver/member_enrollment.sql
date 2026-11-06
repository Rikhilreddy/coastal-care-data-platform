-- EDI-4 enrollment spans, one row per 834 enrollment record, linked to OUR member through the
-- MPI. Only AUTO_LINK records become enrollment: a record in REVIEW or NO_MATCH must not create
-- member months for a possibly wrong person (it is counted in mpi_link for a data steward).
select e.subscriber_id, l.linked_member_id as member_source_id, 'SYNTHEA_FHIR'::text as source_system,
       e.payer_name, e.line_of_business, e.coverage_begin, e.coverage_end, e.usage_indicator, e._source_file
from {{ ref('edi_inbound_834_member') }} e
join {{ ref('mpi_link') }} l on l.source_system = 'X12_834' and l.source_record_id = e.subscriber_id
where l.decision = 'AUTO_LINK'
