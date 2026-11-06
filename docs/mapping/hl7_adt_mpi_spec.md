# HL7-1: ADT A01/A03 feed and Master Patient Index (MPI)

## Why
Hospitals notify the plan of admissions (A01) and discharges (A03) over HL7 v2. Those messages identify the patient by the **hospital's own MRN**, never by our member ID, so every message has to be matched to a member: the job of an MPI. A wrong match merges two people's medical histories (a patient-safety and HIPAA incident), so the MPI is built to prefer "send to a human" over "guess".

## Pipeline
| Step | What | Where |
|---|---|---|
| 1 | Inpatient FHIR encounters (class IMP, ACUTE, NONAC) become A01 and A03 messages, v2.5.1 | `hl7/generate_adt.py` |
| 2 | Seeded data-entry noise, about 2% last-name typo, 3% SSN not collected, 1% DOB one day off; the answer key goes to `audit.mpi_test_truth` | `generate_adt.py` |
| 3 | Land messages one row per segment; separators read from MSH; MSH, EVN, PID and PV1 required; message and segment counts reconciled | `hl7/load_bronze_hl7.py` → `bronze.hl7_segment` |
| 4 | Parse to one row per event; PID-3 repetitions split by `~`, MR and SS found by identifier type (CX.5) | `hl7.hl7_adt_event` |
| 5 | Match | `mpi.mpi_source_record` → `mpi_candidate` → `mpi_link` |
| 6 | Measure against the answer key | `mpi.mpi_match_quality` |

## Field map (HL7 → model)
| HL7 | Meaning | Column |
|---|---|---|
| MSH-9.2 | Trigger event (A01, A03) | `event_type` |
| MSH-10 | Message control ID (unique) | `message_control_id` |
| MSH-11 | Processing ID (T test, P production) | `processing_id` |
| EVN-2 | Event time | `event_ts` |
| PID-3 (MR) | Facility MRN | `facility_mrn` |
| PID-3 (SS) | SSN | `ssn` |
| PID-5.1 / 5.2 | Last / first name | `last_name`, `first_name` |
| PID-7 | Birth date | `birth_date` |
| PID-8 | Sex | `sex_code` |
| PID-11.5 | ZIP | `postal_code` |
| PV1-2 | Patient class (I) | `patient_class` |
| PV1-7.1 | Attending NPI | `attending_npi` |
| PV1-19 | Visit number (FHIR encounter id) | `visit_number` |
| PV1-44 / 45 | Admit / discharge time | `admit_ts`, `discharge_ts` |

## Matching
**Blocking**: compare a record only with members that share the SSN, the birth date, or the first three letters of the last name plus ZIP.

**Scoring** (max 16)
| Evidence | Points |
|---|---|
| SSN exact | 6 |
| DOB exact / within 1 day | 3 / 1 |
| Last name exact / trigram similarity ≥ 0.5 (pg_trgm) | 3 / 2 |
| First name exact / similarity ≥ 0.5 | 2 / 1 |
| Sex | 1 |
| ZIP | 1 |

**Decision**
| Decision | Rule |
|---|---|
| AUTO_LINK | best ≥ 10 **and** ahead of the runner-up by ≥ 3 |
| REVIEW | best 6 to 9, or a near tie: a data steward decides |
| NO_MATCH | best < 6 |

## Results on the test fixture (420 patients: 20 twin pairs, 10 senior/junior pairs, a shared SSN)
| Run | Auto-linked | False links | Sent to review | Precision | Recall |
|---|---|---|---|---|---|
| Normal feed | 420 | 0 | 0 | 1.0000 | 1.0000 |
| Stress test: every SSN removed | 406 | 0 | 14 (typos, DOB off) | 1.0000 | 0.9667 |

The stress test is the important one: without SSNs the matcher **slowed down (sent 14 to review) but never linked the wrong person**.

## Tests
| Test | Rule | Severity |
|---|---|---|
| `assert_mpi_no_false_links` | No auto-link joins two different people | error |
| `assert_mpi_recall` | Recall ≥ 97% | warn |
| `assert_adt_covers_inpatient_stays` | Each stay has exactly one A01 and, once ended, one A03; times equal the encounter's | error |
| `unique` on MSH-10 | No duplicate messages | error |

## HIPAA
ADT messages carry direct identifiers (PHI). They live under `data/` (never in Git); the MPI reads `silver.member_identity` (restricted), and only `linked_member_id` flows on to analytics.
