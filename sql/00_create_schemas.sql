-- Coastal Care Data Platform: medallion layer schemas
CREATE SCHEMA IF NOT EXISTS bronze;
-- raw data, parsed but unchanged
CREATE SCHEMA IF NOT EXISTS silver;
-- cleaned, converted, canonical model
CREATE SCHEMA IF NOT EXISTS gold;
-- star schema and marts
CREATE SCHEMA IF NOT EXISTS ref;
-- ICD-10, HCPCS, GEMs, NPI reference
CREATE SCHEMA IF NOT EXISTS audit;
-- load manifest, reconciliation results
CREATE SCHEMA IF NOT EXISTS quarantine;
-- rejected records with reason codes