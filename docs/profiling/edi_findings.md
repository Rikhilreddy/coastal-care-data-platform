# EDI-1 Discovery Findings (H19–H31)

**Queries:** `sql/investigations/05_edi_discovery.sql`, `06_edi_line_discovery.sql` · **Outputs:** `docs/profiling/edi_*.txt`

| # | Finding | Evidence | Rule |
|---|---|---|---|
| H19 | Practitioners carry NPIs; organizations do not | All 1,786 practitioners have `us-npi`; organizations only a Synthea id | Rendering NPI from practitioner; billing NPI synthetic with valid check digit |
| H20 | Claims have no care team; EOBs do | `careTeam` on 151,490 EOBs, 0 claims | Rendering provider from the EOB |
| H21 | Most non-pharmacy claims lack a diagnosis | 29,631 of 79,317 have one (37%) | 837P requires HI: pre-submission edit `NO_DIAGNOSIS` |
| H22 | Service codes are concentrated | 182 SNOMED codes cover 95% of lines; 120 non-dental service codes cover 97.1% | Crosswalk targets the top codes; the rest are `UNMAPPED` |
| H23 | Claim lines include non-services | Supplies, findings, situations, environments on claim lines | Classified by SNOMED semantic tag |
| H24 | Line charges live on the EOB | `line_sbmtd_chrg_amt` on 433,876 EOB lines | 837 lines are built from priced EOB lines |
| H25 | ~70% of claim lines are services by tag | procedure 262,893 + regime/therapy 25,406 lines | Non-service lines bundled |
| H26 | EOB line charges sum to the claim total | 79,317 of 79,317 claims, 0 differences | Reconciliation: Σ 837 lines = billed |
| H27 | Rendering NPI is inside the EOB reference | `Practitioner?identifier=…us-npi\|<NPI>` on all EOBs | Parsed from the reference |
| H28 | Missing diagnoses cluster by visit type | Problem visits 95% without; check-ups 50%; vaccines 99.7%; prenatal 87% | Governed visit-reason rule for visit types with a standard Z code |
| H29 | About 19% of claims are dental | 15,255 claims with dental lines | Out of scope (CDT licensed, 837D) |
| H30 | Self-pay claims have no payer | 15,109 NO_INSURANCE claims | Not sent as 837 |
| H31 | Dollars are almost all services | procedure $260.0M, LOINC/CVX $15.7M, regime $13.9M; supplies $0.1M; total $290,305,886.62 = all non-RX billed | Crosswalk spans SNOMED, LOINC and CVX |
| H32 | Some line charges are far outside normal pricing | e.g. spirometry (CPT 94010) billed at $13,700.33 on a 2025 Medicare claim | Sent as received (the provider's charge); flagged for a gold-layer charge-outlier check (e.g. charge > p99 for the CPT code) |
| H33 | Synthea prices quality-tracking services | Medication reconciliation, falls screening, diabetic eye exam carry real charges | CPT Category II codes (1111F, 1100F, 2022F) are billed at $0 in practice, so these lines are BUNDLED into the visit; claim totals unchanged |
| H34 | EOB payments are floats per line | Line totals differ from the claim payment by fractions of a cent | 835 lines rounded to cents; reconciliation tolerance 1 cent per line (as H17) |
| H35 | Synthea Encounters carry no hospital MRN | Patient identity is the FHIR id only | ADT generator assigns a facility MRN (`M` + SHA-256 of facility and member); the MPI must link it back |
| H36 | Synthea names carry numeric suffixes (`Ana123`) | Never present in a real registration system | Stripped in ADT messages and on the member side of the MPI |
| H37 | Two fixture patients share an SSN (mother and child) | A pure SSN match would auto-link the wrong person | Scoring requires DOB and name agreement too; shared-SSN pairs fall below the auto-link threshold |
| H38 | Synthea gives no subscriber ID for dependents (only the owner's name) | Children and spouses cannot be sent under a subscriber | Every covered person is sent as a subscriber (INS01=Y, INS02=18), with their own payer member ID |
| H39 | Coverage history includes NO_INSURANCE spans | They are gaps, not coverage | Not sent on the 834; claims in those months stay SELF_PAY |
| H40 | Secondary payers in the history | COB loop 2320 not built | Primary coverage only; documented backlog |
| H41 | A claim's payer can differ from the member's enrolled plan that year | Paid lands in one line of business, member months in another | Reported, not forced: `mart_pmpm` keeps paid with no enrollment in a separate column |
