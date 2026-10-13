# DE-SynPUF Legacy Source Profile

Generated 2026-10-13 18:23 by `ingestion/legacy/profile_desynpuf.py`.
All columns were read as text to preserve leading zeros in IDs and codes.

## DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv

- **Rows:** 116,352
- **Columns:** 32
- **Fully duplicated rows:** 0
- **Candidate key checks:**
  - `DESYNPUF_ID`: UNIQUE (0 duplicates, 0 rows with null key)

| Column | Type | Null % | Distinct | Min | Max | Top values | Notes |
|---|---|---|---|---|---|---|---|
| DESYNPUF_ID | text/code | 0.0 | 116,352 |  |  | 00013D2EFD8E45D1 (1), 00016F745862898F (1), 0001FDD721E223DC (1) |  |
| BENE_BIRTH_DT | date | 0.0 | 900 | 1909-01-01 | 1983-12-01 | 19421001 (528), 19390401 (510), 19400301 (504) |  |
| BENE_DEATH_DT | date | 98.44 | 12 | 2008-01-01 | 2008-12-01 | 20080901 (166), 20080101 (164), 20080501 (158) |  |
| BENE_SEX_IDENT_CD | numeric | 0.0 | 2 | 1 | 2 | 2 (64,347), 1 (52,005) |  |
| BENE_RACE_CD | numeric | 0.0 | 4 | 1 | 5 | 1 (96,349), 2 (12,343), 3 (4,931) |  |
| BENE_ESRD_IND | text/code | 0.0 | 2 |  |  | 0 (108,091), Y (8,261) |  |
| SP_STATE_CODE | numeric | 0.0 | 52 | 1 | 54 | 05 (10,224), 10 (7,745), 45 (6,703) |  |
| BENE_COUNTY_CD | numeric | 0.0 | 307 | 0 | 999 | 200 (3,454), 010 (3,223), 020 (3,023) |  |
| BENE_HI_CVRAGE_TOT_MONS | numeric | 0.0 | 13 | 0 | 12 | 12 (104,302), 0 (5,294), 11 (900) |  |
| BENE_SMI_CVRAGE_TOT_MONS | numeric | 0.0 | 13 | 0 | 12 | 12 (97,659), 0 (11,246), 11 (933) |  |
| BENE_HMO_CVRAGE_TOT_MONS | numeric | 0.0 | 13 | 0 | 12 | 0 (89,462), 12 (22,384), 9 (659) |  |
| PLAN_CVRG_MOS_NUM | numeric | 0.0 | 13 | 0 | 12 | 12 (61,870), 00 (47,297), 11 (1,299) |  |
| SP_ALZHDMTA | numeric | 0.0 | 2 | 1 | 2 | 2 (93,942), 1 (22,410) |  |
| SP_CHF | numeric | 0.0 | 2 | 1 | 2 | 2 (83,197), 1 (33,155) |  |
| SP_CHRNKIDN | numeric | 0.0 | 2 | 1 | 2 | 2 (97,666), 1 (18,686) |  |
| SP_CNCR | numeric | 0.0 | 2 | 1 | 2 | 2 (108,937), 1 (7,415) |  |
| SP_COPD | numeric | 0.0 | 2 | 1 | 2 | 2 (100,609), 1 (15,743) |  |
| SP_DEPRESSN | numeric | 0.0 | 2 | 1 | 2 | 2 (91,512), 1 (24,840) |  |
| SP_DIABETES | numeric | 0.0 | 2 | 1 | 2 | 2 (72,292), 1 (44,060) |  |
| SP_ISCHMCHT | numeric | 0.0 | 2 | 1 | 2 | 2 (67,410), 1 (48,942) |  |
| SP_OSTEOPRS | numeric | 0.0 | 2 | 1 | 2 | 2 (96,175), 1 (20,177) |  |
| SP_RA_OA | numeric | 0.0 | 2 | 1 | 2 | 2 (98,436), 1 (17,916) |  |
| SP_STRKETIA | numeric | 0.0 | 2 | 1 | 2 | 2 (111,129), 1 (5,223) |  |
| MEDREIMB_IP | numeric | 0.0 | 2,025 | -3000.0 | 164220.0 | 0.00 (100,918), 4000.00 (959), 5000.00 (884) | 12 negative values |
| BENRES_IP | numeric | 0.0 | 145 | 0.0 | 53096.0 | 0.00 (100,610), 1024.00 (9,087), 2048.00 (3,776) |  |
| PPPYMT_IP | numeric | 0.0 | 69 | 0.0 | 68000.0 | 0.00 (115,703), 5000.00 (50), 6000.00 (45) |  |
| MEDREIMB_OP | numeric | 0.0 | 1,466 | -90.0 | 50020.0 | 0.00 (57,154), 100.00 (1,701), 200.00 (1,330) | 51 negative values |
| BENRES_OP | numeric | 0.0 | 656 | 0.0 | 12450.0 | 0.00 (61,731), 20.00 (3,373), 10.00 (3,041) |  |
| PPPYMT_OP | numeric | 0.0 | 74 | 0.0 | 14400.0 | 0.00 (113,816), 200.00 (251), 2000.00 (206) |  |
| MEDREIMB_CAR | numeric | 0.0 | 1,222 | 0.0 | 21160.0 | 0.00 (31,754), 50.00 (713), 30.00 (665) |  |
| BENRES_CAR | numeric | 0.0 | 399 | 0.0 | 5260.0 | 0.00 (33,645), 20.00 (2,025), 10.00 (1,926) |  |
| PPPYMT_CAR | numeric | 0.0 | 138 | 0.0 | 2110.0 | 0.00 (99,000), 10.00 (1,985), 100.00 (1,666) |  |

## DE1_0_2008_to_2010_Inpatient_Claims_Sample_1.csv

- **Rows:** 66,773
- **Columns:** 81
- **Fully duplicated rows:** 0
- **Candidate key checks:**
  - `DESYNPUF_ID`: not unique (28,993 duplicates, 0 rows with null key)
  - `CLM_ID`: not unique (68 duplicates, 0 rows with null key)
  - `CLM_ID + SEGMENT`: UNIQUE (0 duplicates, 0 rows with null key)
  - `DESYNPUF_ID + CLM_ID + SEGMENT`: UNIQUE (0 duplicates, 0 rows with null key)

| Column | Type | Null % | Distinct | Min | Max | Top values | Notes |
|---|---|---|---|---|---|---|---|
| DESYNPUF_ID | text/code | 0.0 | 37,780 |  |  | CD57573A5B77AAFE (14), FC02104A9F15D57C (13), 3A9D94388C426924 (12) |  |
| CLM_ID | numeric | 0.0 | 66,705 | 196011176958156 | 196991177026504 | 196901176966106 (2), 196531176970382 (2), 196821176998887 (2) |  |
| SEGMENT | numeric | 0.0 | 2 | 1 | 2 | 1 (66,705), 2 (68) |  |
| CLM_FROM_DT | date | 0.1 | 1,120 | 2007-11-27 | 2010-12-30 | 20080522 (115), 20081015 (111), 20080616 (104) |  |
| CLM_THRU_DT | date | 0.1 | 1,096 | 2008-01-01 | 2010-12-31 | 20080529 (108), 20080602 (108), 20080905 (106) |  |
| PRVDR_NUM | text/code | 0.0 | 2,675 |  |  | 23006G (772), 1000AH (634), 3600NG (537) |  |
| CLM_PMT_AMT | numeric | 0.0 | 92 | -8000.0 | 57000.0 | 4000.00 (7,601), 5000.00 (7,027), 3000.00 (6,399) | 55 negative values |
| NCH_PRMRY_PYR_CLM_PD_AMT | numeric | 0.0 | 72 | 0.0 | 68000.0 | 0.00 (65,246), 5000.00 (119), 6000.00 (100) |  |
| AT_PHYSN_NPI | numeric | 1.01 | 16,670 | 1168381.0 | 9999956301.0 | 9011551271 (533), 2482526289 (390), 3709260297 (387) |  |
| OP_PHYSN_NPI | numeric | 41.51 | 12,076 | 1159725.0 | 9999602306.0 | 9612910514 (324), 3663285618 (220), 2482526289 (217) |  |
| OT_PHYSN_NPI | numeric | 88.49 | 4,386 | 836309.0 | 9999956301.0 | 8523328573 (91), 2017370966 (56), 1817151262 (43) |  |
| CLM_ADMSN_DT | date | 0.0 | 1,120 | 2007-11-27 | 2010-12-30 | 20080522 (115), 20081015 (111), 20080616 (104) |  |
| ADMTNG_ICD9_DGNS_CD | numeric | 0.9 | 2,285 | 30.0 | 99939.0 | 78605 (2,739), 78650 (2,697), 486 (2,363) | ICD-9 dx format valid: 100.0% |
| CLM_PASS_THRU_PER_DIEM_AMT | numeric | 0.0 | 15 | 0.0 | 500.0 | 0.00 (47,800), 10.00 (2,886), 200.00 (2,277) |  |
| NCH_BENE_IP_DDCTBL_AMT | numeric | 3.26 | 3 | 1024.0 | 1100.0 | 1024.00 (26,058), 1068.00 (24,793), 1100.00 (13,744) |  |
| NCH_BENE_PTA_COINSRNC_LBLTY_AM | numeric | 0.0 | 36 | 0.0 | 34000.0 | 0.00 (65,348), 2000.00 (253), 1000.00 (216) |  |
| NCH_BENE_BLOOD_DDCTBL_LBLTY_AM | numeric | 0.0 | 18 | 0.0 | 2000.0 | 0.00 (66,597), 300.00 (28), 1000.00 (26) |  |
| CLM_UTLZTN_DAY_CNT | numeric | 0.1 | 99 | 0.0 | 136.0 | 3 (10,896), 2 (9,542), 1 (8,130) |  |
| NCH_BENE_DSCHRG_DT | date | 0.0 | 1,096 | 2008-01-01 | 2010-12-31 | 20080529 (108), 20080602 (108), 20080905 (106) |  |
| CLM_DRG_CD | numeric | 0.0 | 739 | 0.0 | 999.0 | 882 (282), 177 (281), 886 (275) |  |
| ICD9_DGNS_CD_1 | numeric | 0.14 | 2,740 | 30.0 | 99989.0 | 486 (2,453), V5789 (1,807), 41401 (1,675) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_2 | text/code | 0.79 | 2,961 |  |  | 4019 (4,170), 2724 (1,852), 25000 (1,739) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_3 | text/code | 1.92 | 2,909 |  |  | 4019 (3,830), 25000 (1,766), 2724 (1,730) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_4 | text/code | 4.15 | 2,907 |  |  | 4019 (3,469), 2724 (1,728), 25000 (1,665) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_5 | text/code | 7.69 | 2,915 |  |  | 4019 (3,126), 25000 (1,600), 2724 (1,580) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_6 | text/code | 12.59 | 2,843 |  |  | 4019 (2,687), 25000 (1,442), 2724 (1,413) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_7 | text/code | 18.52 | 2,823 |  |  | 4019 (2,329), 25000 (1,335), 2724 (1,294) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_8 | text/code | 25.2 | 2,696 |  |  | 4019 (1,943), 25000 (1,236), 2724 (1,157) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_9 | text/code | 32.56 | 2,571 |  |  | 4019 (1,649), 25000 (1,058), 2724 (1,034) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_10 | text/code | 91.83 | 1,134 |  |  | 4019 (170), 25000 (130), 2724 (110) | ICD-9 dx format valid: 100.0% |
| ICD9_PRCDR_CD_1 | numeric | 42.74 | 1,294 | 11.0 | 9999.0 | 9904 (1,861), 8154 (1,646), 3893 (1,424) | ICD-9 px format valid: 100.0% |
| ICD9_PRCDR_CD_2 | text/code | 65.95 | 1,992 |  |  | 4019 (1,463), 2724 (671), 25000 (660) | ICD-9 px format valid: 48.0% (e.g. bad: E8889, 29410, 70715) |
| ICD9_PRCDR_CD_3 | text/code | 78.34 | 1,680 |  |  | 4019 (810), 2724 (406), 25000 (399) | ICD-9 px format valid: 46.84% (e.g. bad: V5866, 40390, 53081) |
| ICD9_PRCDR_CD_4 | text/code | 85.96 | 1,370 |  |  | 4019 (467), 2724 (261), 25000 (237) | ICD-9 px format valid: 47.14% (e.g. bad: V4976, V454, 41519) |
| ICD9_PRCDR_CD_5 | text/code | 90.35 | 1,125 |  |  | 4019 (308), 2724 (185), 41401 (170) | ICD-9 px format valid: 46.77% (e.g. bad: 53081, 43491, 41402) |
| ICD9_PRCDR_CD_6 | text/code | 93.08 | 927 |  |  | 4019 (215), 2724 (136), 25000 (119) | ICD-9 px format valid: 46.58% (e.g. bad: 70724, 29633, 51881) |
| HCPCS_CD_1 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_2 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_3 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_4 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_5 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_6 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_7 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_8 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_9 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_10 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_11 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_12 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_13 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_14 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_15 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_16 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_17 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_18 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_19 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_20 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_21 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_22 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_23 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_24 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_25 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_26 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_27 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_28 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_29 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_30 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_31 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_32 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_33 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_34 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_35 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_36 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_37 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_38 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_39 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_40 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_41 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_42 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_43 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_44 | empty | 100.0 | 0 |  |  |  |  |
| HCPCS_CD_45 | empty | 100.0 | 0 |  |  |  |  |

## DE1_0_2008_to_2010_Outpatient_Claims_Sample_1.csv

- **Rows:** 790,790
- **Columns:** 76
- **Fully duplicated rows:** 0
- **Candidate key checks:**
  - `DESYNPUF_ID`: not unique (705,518 duplicates, 0 rows with null key)
  - `CLM_ID`: not unique (10,975 duplicates, 0 rows with null key)
  - `CLM_ID + SEGMENT`: UNIQUE (0 duplicates, 0 rows with null key)
  - `DESYNPUF_ID + CLM_ID + SEGMENT`: UNIQUE (0 duplicates, 0 rows with null key)

| Column | Type | Null % | Distinct | Min | Max | Top values | Notes |
|---|---|---|---|---|---|---|---|
| DESYNPUF_ID | text/code | 0.0 | 85,272 |  |  | AD5D4E087BF57C05 (78), 14D1519892CEDDD0 (73), 6688888FAE4A668D (73) |  |
| CLM_ID | numeric | 0.0 | 779,815 | 542012280836456 | 542992281646108 | 542052281361022 (2), 542012281447530 (2), 542672281020916 (2) |  |
| SEGMENT | numeric | 0.0 | 2 | 1 | 2 | 1 (779,537), 2 (11,253) |  |
| CLM_FROM_DT | date | 1.42 | 1,116 | 2007-12-12 | 2010-12-31 | 20090321 (1,008), 20090303 (990), 20090425 (989) |  |
| CLM_THRU_DT | date | 1.42 | 1,096 | 2008-01-01 | 2010-12-31 | 20090321 (1,015), 20090425 (987), 20090623 (985) |  |
| PRVDR_NUM | text/code | 0.0 | 6,294 |  |  | 0502NA (9,906), 2201DT (6,084), 0505TK (5,755) |  |
| CLM_PMT_AMT | numeric | 0.0 | 53 | -100.0 | 3300.0 | 100.00 (78,250), 10.00 (65,944), 200.00 (63,762) | 2,566 negative values |
| NCH_PRMRY_PYR_CLM_PD_AMT | numeric | 0.0 | 33 | 0.0 | 14000.0 | 0.00 (783,826), 200.00 (730), 2000.00 (578) |  |
| AT_PHYSN_NPI | numeric | 2.25 | 98,695 | 102408.0 | 9999885698.0 | 1586461282 (3,049), 3177196045 (2,073), 8208965993 (1,677) |  |
| OP_PHYSN_NPI | numeric | 83.0 | 39,439 | 325865.0 | 9999615484.0 | 1586461282 (544), 9244350711 (388), 8208965993 (312) |  |
| OT_PHYSN_NPI | numeric | 67.42 | 56,560 | 102408.0 | 9999469755.0 | 8208965993 (1,386), 2690462085 (1,239), 2484358033 (1,157) |  |
| NCH_BENE_BLOOD_DDCTBL_LBLTY_AM | numeric | 0.0 | 8 | 0.0 | 800.0 | 0.00 (790,757), 200.00 (10), 400.00 (8) |  |
| ICD9_DGNS_CD_1 | text/code | 0.71 | 11,133 |  |  | 4019 (19,079), 4011 (18,816), OTHER (5,675) | ICD-9 dx format valid: 99.28% (e.g. bad: OTHER) |
| ICD9_DGNS_CD_2 | text/code | 37.73 | 5,619 |  |  | 4019 (30,464), 25000 (16,465), 2724 (15,395) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_3 | text/code | 60.68 | 5,014 |  |  | 4019 (18,622), 25000 (10,519), 2724 (9,783) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_4 | text/code | 75.77 | 4,460 |  |  | 4019 (10,745), 25000 (6,512), 2724 (5,667) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_5 | text/code | 85.82 | 3,927 |  |  | 4019 (6,162), 25000 (3,708), 2724 (2,908) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_6 | text/code | 90.78 | 3,402 |  |  | 4019 (3,800), 25000 (2,405), 2724 (1,773) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_7 | text/code | 93.79 | 3,036 |  |  | 4019 (2,491), 25000 (1,558), V5869 (1,109) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_8 | text/code | 95.68 | 2,669 |  |  | 4019 (1,526), 25000 (1,070), 2724 (757) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_9 | text/code | 97.01 | 2,332 |  |  | 4019 (973), 25000 (707), V5869 (475) | ICD-9 dx format valid: 100.0% |
| ICD9_DGNS_CD_10 | text/code | 99.79 | 641 |  |  | 4019 (70), 25000 (39), V5869 (32) | ICD-9 dx format valid: 100.0% |
| ICD9_PRCDR_CD_1 | numeric | 99.97 | 99 | 61.0 | 9961.0 | 3995 (14), 0066 (13), 3722 (12) | ICD-9 px format valid: 100.0% |
| ICD9_PRCDR_CD_2 | text/code | 99.98 | 89 |  |  | 4019 (8), 25000 (7), 2724 (6) | ICD-9 px format valid: 41.46% (e.g. bad: V5861, V1043, 78720) |
| ICD9_PRCDR_CD_3 | text/code | 99.99 | 56 |  |  | 2724 (5), 25000 (4), 4019 (4) | ICD-9 px format valid: 47.95% (e.g. bad: 43882, 51881, 78959) |
| ICD9_PRCDR_CD_4 | text/code | 99.99 | 40 |  |  | 4019 (4), 2724 (3), 5856 (2) | ICD-9 px format valid: 37.5% (e.g. bad: 78650, V4577, 78552) |
| ICD9_PRCDR_CD_5 | text/code | 100.0 | 34 |  |  | 7802 (2), 71595 (1), 33520 (1) | ICD-9 px format valid: 45.71% (e.g. bad: 71595, 33520, 95901) |
| ICD9_PRCDR_CD_6 | text/code | 100.0 | 29 |  |  | 7840 (1), 2511 (1), 7802 (1) | ICD-9 px format valid: 58.62% (e.g. bad: V5861, 25000, V0481) |
| NCH_BENE_PTB_DDCTBL_AMT | numeric | 0.0 | 12 | 0.0 | 200.0 | 0.00 (757,981), 100.00 (7,226), 70.00 (3,697) |  |
| NCH_BENE_PTB_COINSRNC_AMT | numeric | 0.0 | 21 | 0.0 | 1100.0 | 0.00 (265,950), 10.00 (106,756), 20.00 (100,773) |  |
| ADMTNG_ICD9_DGNS_CD | text/code | 75.41 | 4,428 |  |  | V7612 (8,209), 42731 (5,523), 4019 (4,877) | ICD-9 dx format valid: 100.0% |
| HCPCS_CD_1 | text/code | 18.28 | 2,533 |  |  | 36415 (161,373), 99213 (31,792), 99212 (23,658) | HCPCS format valid: 99.99% (e.g. bad: 520, 01, 0521) |
| HCPCS_CD_2 | text/code | 42.92 | 3,405 |  |  | 85025 (23,068), 85610 (15,805), 80053 (14,234) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0851, TOTAL) |
| HCPCS_CD_3 | text/code | 58.08 | 3,305 |  |  | 85025 (18,142), 85610 (11,684), 80053 (10,746) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0851, 0841) |
| HCPCS_CD_4 | text/code | 65.45 | 3,192 |  |  | 85025 (15,057), 97110 (9,485), 85610 (9,034) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_5 | text/code | 71.39 | 3,044 |  |  | 85025 (12,182), 97110 (8,565), 80053 (7,315) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0851, 0306) |
| HCPCS_CD_6 | text/code | 75.96 | 2,888 |  |  | 85025 (9,543), 97110 (7,865), 80053 (5,815) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0841) |
| HCPCS_CD_7 | text/code | 79.74 | 2,799 |  |  | 85025 (7,838), 97110 (7,119), 80053 (4,464) | HCPCS format valid: 99.97% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_8 | text/code | 82.6 | 2,613 |  |  | 97110 (6,408), 85025 (5,888), 80053 (3,677) | HCPCS format valid: 99.97% (e.g. bad: 201E5, 0851, 108) |
| HCPCS_CD_9 | text/code | 84.85 | 2,551 |  |  | 97110 (5,876), 85025 (4,922), Q4081 (3,651) | HCPCS format valid: 99.97% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_10 | text/code | 86.66 | 2,449 |  |  | 97110 (5,475), 85025 (4,119), Q4081 (3,616) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0851, 0841) |
| HCPCS_CD_11 | text/code | 88.16 | 2,347 |  |  | 97110 (5,014), Q4081 (3,628), 90999 (3,496) | HCPCS format valid: 99.97% (e.g. bad: 201E5, 0851, 112) |
| HCPCS_CD_12 | text/code | 89.39 | 2,260 |  |  | 97110 (4,747), Q4081 (3,523), 90999 (3,368) | HCPCS format valid: 99.97% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_13 | text/code | 90.51 | 2,145 |  |  | 97110 (4,316), Q4081 (3,463), 90999 (3,452) | HCPCS format valid: 99.98% (e.g. bad: 201E5) |
| HCPCS_CD_14 | text/code | 91.42 | 2,054 |  |  | 97110 (4,031), Q4081 (3,507), 90999 (3,222) | HCPCS format valid: 99.97% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_15 | text/code | 92.19 | 1,986 |  |  | 97110 (3,658), Q4081 (3,538), 90999 (3,202) | HCPCS format valid: 99.97% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_16 | text/code | 92.88 | 1,871 |  |  | Q4081 (3,502), 97110 (3,465), 90999 (3,224) | HCPCS format valid: 99.97% (e.g. bad: 201E5) |
| HCPCS_CD_17 | text/code | 93.49 | 1,789 |  |  | Q4081 (3,341), 90999 (3,294), 97110 (3,221) | HCPCS format valid: 99.97% (e.g. bad: 201E5, 0851, 4A217) |
| HCPCS_CD_18 | text/code | 94.02 | 1,734 |  |  | Q4081 (3,393), 90999 (3,127), 97110 (3,055) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0841, 0851) |
| HCPCS_CD_19 | text/code | 94.48 | 1,656 |  |  | Q4081 (3,365), 90999 (3,201), A4657 (2,851) | HCPCS format valid: 99.95% (e.g. bad: 201E5, 0851, 108) |
| HCPCS_CD_20 | text/code | 94.9 | 1,565 |  |  | Q4081 (3,224), 90999 (3,078), A4657 (2,969) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_21 | text/code | 95.26 | 1,464 |  |  | Q4081 (3,283), 90999 (3,010), A4657 (2,891) | HCPCS format valid: 99.97% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_22 | text/code | 95.57 | 1,431 |  |  | Q4081 (3,269), 90999 (3,024), A4657 (2,852) | HCPCS format valid: 99.99% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_23 | text/code | 95.83 | 1,374 |  |  | Q4081 (3,134), 90999 (3,005), A4657 (2,880) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_24 | text/code | 96.06 | 1,361 |  |  | Q4081 (3,184), A4657 (2,844), 90999 (2,843) | HCPCS format valid: 99.96% (e.g. bad: 201E5, 0851, 0841) |
| HCPCS_CD_25 | text/code | 96.3 | 1,214 |  |  | Q4081 (3,165), 90999 (2,853), A4657 (2,740) | HCPCS format valid: 99.98% (e.g. bad: 0841, 201E5, 0851) |
| HCPCS_CD_26 | text/code | 96.48 | 1,195 |  |  | Q4081 (3,088), 90999 (2,795), A4657 (2,743) | HCPCS format valid: 99.97% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_27 | text/code | 96.64 | 1,156 |  |  | Q4081 (3,000), 90999 (2,784), A4657 (2,715) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0841) |
| HCPCS_CD_28 | text/code | 96.82 | 1,111 |  |  | Q4081 (2,963), 90999 (2,717), A4657 (2,568) | HCPCS format valid: 99.98% (e.g. bad: 201E5) |
| HCPCS_CD_29 | text/code | 96.97 | 1,072 |  |  | Q4081 (2,983), 90999 (2,645), A4657 (2,604) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_30 | text/code | 97.12 | 1,020 |  |  | Q4081 (2,818), 90999 (2,659), A4657 (2,548) | HCPCS format valid: 99.96% (e.g. bad: 201E5, 0841, 0851) |
| HCPCS_CD_31 | text/code | 97.28 | 981 |  |  | Q4081 (2,800), 90999 (2,636), A4657 (2,447) | HCPCS format valid: 99.99% (e.g. bad: 0851) |
| HCPCS_CD_32 | text/code | 97.42 | 941 |  |  | Q4081 (2,671), 90999 (2,538), A4657 (2,395) | HCPCS format valid: 99.98% (e.g. bad: 201E5, 0851) |
| HCPCS_CD_33 | text/code | 97.55 | 888 |  |  | Q4081 (2,707), A4657 (2,359), 90999 (2,243) | HCPCS format valid: 99.97% (e.g. bad: 0851, 201E5, DIALY) |
| HCPCS_CD_34 | text/code | 97.68 | 841 |  |  | Q4081 (2,515), 90999 (2,294), A4657 (2,293) | HCPCS format valid: 99.99% (e.g. bad: 201E5) |
| HCPCS_CD_35 | text/code | 97.78 | 823 |  |  | Q4081 (2,499), 90999 (2,237), A4657 (2,179) | HCPCS format valid: 99.97% (e.g. bad: 0851, 201E5) |
| HCPCS_CD_36 | text/code | 97.88 | 817 |  |  | Q4081 (2,431), 90999 (2,183), A4657 (2,125) | HCPCS format valid: 99.97% (e.g. bad: 0851, 201E5, 0841) |
| HCPCS_CD_37 | text/code | 97.98 | 757 |  |  | Q4081 (2,322), A4657 (2,070), 90999 (2,059) | HCPCS format valid: 99.98% (e.g. bad: 0851, 201E5) |
| HCPCS_CD_38 | text/code | 98.09 | 757 |  |  | Q4081 (2,300), 90999 (1,953), A4657 (1,936) | HCPCS format valid: 99.97% (e.g. bad: 0851, 201E5) |
| HCPCS_CD_39 | text/code | 98.18 | 733 |  |  | Q4081 (2,087), 90999 (1,969), A4657 (1,946) | HCPCS format valid: 99.99% (e.g. bad: 0851) |
| HCPCS_CD_40 | text/code | 98.29 | 675 |  |  | Q4081 (2,018), A4657 (1,784), 90999 (1,775) | HCPCS format valid: 99.96% (e.g. bad: 0841, 0851, 201E5) |
| HCPCS_CD_41 | text/code | 98.4 | 658 |  |  | Q4081 (1,898), A4657 (1,738), 90999 (1,663) | HCPCS format valid: 99.97% (e.g. bad: 0851, 201E5) |
| HCPCS_CD_42 | text/code | 98.5 | 666 |  |  | Q4081 (1,780), A4657 (1,614), 90999 (1,568) | HCPCS format valid: 99.98% (e.g. bad: 0851, 0841) |
| HCPCS_CD_43 | text/code | 98.58 | 623 |  |  | Q4081 (1,681), A4657 (1,541), 90999 (1,453) | HCPCS format valid: 99.97% (e.g. bad: 0851, 0841) |
| HCPCS_CD_44 | text/code | 98.67 | 588 |  |  | Q4081 (1,578), 90999 (1,436), A4657 (1,400) | HCPCS format valid: 100.0% |
| HCPCS_CD_45 | empty | 100.0 | 0 |  |  |  |  |

## DE1_0_2009_Beneficiary_Summary_File_Sample_1.csv

- **Rows:** 114,538
- **Columns:** 32
- **Fully duplicated rows:** 0
- **Candidate key checks:**
  - `DESYNPUF_ID`: UNIQUE (0 duplicates, 0 rows with null key)

| Column | Type | Null % | Distinct | Min | Max | Top values | Notes |
|---|---|---|---|---|---|---|---|
| DESYNPUF_ID | text/code | 0.0 | 114,538 |  |  | 00013D2EFD8E45D1 (1), 00016F745862898F (1), 0001FDD721E223DC (1) |  |
| BENE_BIRTH_DT | date | 0.0 | 900 | 1909-01-01 | 1983-12-01 | 19421001 (518), 19390401 (501), 19400301 (497) |  |
| BENE_DEATH_DT | date | 98.44 | 12 | 2009-01-01 | 2009-12-01 | 20090101 (172), 20090201 (159), 20091001 (155) |  |
| BENE_SEX_IDENT_CD | numeric | 0.0 | 2 | 1 | 2 | 2 (63,344), 1 (51,194) |  |
| BENE_RACE_CD | numeric | 0.0 | 4 | 1 | 5 | 1 (94,822), 2 (12,154), 3 (4,867) |  |
| BENE_ESRD_IND | text/code | 0.0 | 2 |  |  | 0 (103,682), Y (10,856) |  |
| SP_STATE_CODE | numeric | 0.0 | 52 | 1 | 54 | 05 (10,074), 10 (7,632), 45 (6,610) |  |
| BENE_COUNTY_CD | numeric | 0.0 | 307 | 0 | 999 | 200 (3,399), 010 (3,168), 020 (2,980) |  |
| BENE_HI_CVRAGE_TOT_MONS | numeric | 0.0 | 13 | 0 | 12 | 12 (106,914), 0 (7,241), 11 (51) |  |
| BENE_SMI_CVRAGE_TOT_MONS | numeric | 0.0 | 13 | 0 | 12 | 12 (105,262), 0 (8,032), 6 (309) |  |
| BENE_HMO_CVRAGE_TOT_MONS | numeric | 0.0 | 13 | 0 | 12 | 0 (81,208), 12 (29,980), 9 (468) |  |
| PLAN_CVRG_MOS_NUM | numeric | 0.0 | 13 | 0 | 12 | 12 (80,486), 00 (22,009), 06 (1,906) |  |
| SP_ALZHDMTA | numeric | 0.0 | 2 | 1 | 2 | 2 (88,134), 1 (26,404) |  |
| SP_CHF | numeric | 0.0 | 2 | 1 | 2 | 2 (75,100), 1 (39,438) |  |
| SP_CHRNKIDN | numeric | 0.0 | 2 | 1 | 2 | 2 (90,820), 1 (23,718) |  |
| SP_CNCR | numeric | 0.0 | 2 | 1 | 2 | 2 (105,202), 1 (9,336) |  |
| SP_COPD | numeric | 0.0 | 2 | 1 | 2 | 2 (96,613), 1 (17,925) |  |
| SP_DEPRESSN | numeric | 0.0 | 2 | 1 | 2 | 2 (86,453), 1 (28,085) |  |
| SP_DIABETES | numeric | 0.0 | 2 | 1 | 2 | 2 (66,829), 1 (47,709) |  |
| SP_ISCHMCHT | numeric | 0.0 | 2 | 1 | 2 | 2 (59,937), 1 (54,601) |  |
| SP_OSTEOPRS | numeric | 0.0 | 2 | 1 | 2 | 2 (92,630), 1 (21,908) |  |
| SP_RA_OA | numeric | 0.0 | 2 | 1 | 2 | 2 (94,544), 1 (19,994) |  |
| SP_STRKETIA | numeric | 0.0 | 2 | 1 | 2 | 2 (108,508), 1 (6,030) |  |
| MEDREIMB_IP | numeric | 0.0 | 2,090 | -2000.0 | 136100.0 | 0.00 (95,983), 4000.00 (1,136), 5000.00 (965) | 9 negative values |
| BENRES_IP | numeric | 0.0 | 106 | 0.0 | 38272.0 | 0.00 (95,712), 1068.00 (14,024), 2136.00 (3,227) |  |
| PPPYMT_IP | numeric | 0.0 | 67 | 0.0 | 91000.0 | 0.00 (113,970), 5000.00 (44), 7000.00 (37) |  |
| MEDREIMB_OP | numeric | 0.0 | 1,527 | -80.0 | 46480.0 | 0.00 (43,057), 100.00 (2,278), 200.00 (1,789) | 61 negative values |
| BENRES_OP | numeric | 0.0 | 646 | 0.0 | 13840.0 | 0.00 (48,660), 20.00 (4,117), 10.00 (3,474) |  |
| PPPYMT_OP | numeric | 0.0 | 87 | 0.0 | 19000.0 | 0.00 (111,826), 200.00 (275), 2000.00 (221) |  |
| MEDREIMB_CAR | numeric | 0.0 | 1,055 | 0.0 | 16540.0 | 0.00 (23,716), 50.00 (811), 30.00 (738) |  |
| BENRES_CAR | numeric | 0.0 | 330 | 0.0 | 4690.0 | 0.00 (25,681), 10.00 (2,155), 20.00 (2,103) |  |
| PPPYMT_CAR | numeric | 0.0 | 139 | 0.0 | 2200.0 | 0.00 (95,561), 10.00 (2,032), 100.00 (1,918) |  |

## DE1_0_2010_Beneficiary_Summary_File_Sample_1.csv

- **Rows:** 112,754
- **Columns:** 32
- **Fully duplicated rows:** 0
- **Candidate key checks:**
  - `DESYNPUF_ID`: UNIQUE (0 duplicates, 0 rows with null key)

| Column | Type | Null % | Distinct | Min | Max | Top values | Notes |
|---|---|---|---|---|---|---|---|
| DESYNPUF_ID | text/code | 0.0 | 112,754 |  |  | 00013D2EFD8E45D1 (1), 00016F745862898F (1), 0001FDD721E223DC (1) |  |
| BENE_BIRTH_DT | date | 0.0 | 900 | 1909-01-01 | 1983-12-01 | 19421001 (510), 19390401 (488), 19400301 (487) |  |
| BENE_DEATH_DT | date | 98.35 | 12 | 2010-01-01 | 2010-12-01 | 20101101 (204), 20100501 (170), 20100801 (161) |  |
| BENE_SEX_IDENT_CD | numeric | 0.0 | 2 | 1 | 2 | 2 (62,368), 1 (50,386) |  |
| BENE_RACE_CD | numeric | 0.0 | 4 | 1 | 5 | 1 (93,343), 2 (11,962), 3 (4,793) |  |
| BENE_ESRD_IND | text/code | 0.0 | 2 |  |  | 0 (104,737), Y (8,017) |  |
| SP_STATE_CODE | numeric | 0.0 | 52 | 1 | 54 | 05 (9,919), 10 (7,511), 45 (6,520) |  |
| BENE_COUNTY_CD | numeric | 0.0 | 307 | 0 | 999 | 200 (3,353), 010 (3,106), 020 (2,932) |  |
| BENE_HI_CVRAGE_TOT_MONS | numeric | 0.0 | 13 | 0 | 12 | 12 (103,210), 0 (6,319), 11 (576) |  |
| BENE_SMI_CVRAGE_TOT_MONS | numeric | 0.0 | 13 | 0 | 12 | 12 (100,475), 0 (8,648), 11 (621) |  |
| BENE_HMO_CVRAGE_TOT_MONS | numeric | 0.0 | 13 | 0 | 12 | 0 (76,223), 12 (30,832), 9 (707) |  |
| PLAN_CVRG_MOS_NUM | numeric | 0.0 | 13 | 0 | 12 | 12 (84,062), 00 (13,256), 06 (1,720) |  |
| SP_ALZHDMTA | numeric | 0.0 | 2 | 1 | 2 | 2 (94,065), 1 (18,689) |  |
| SP_CHF | numeric | 0.0 | 2 | 1 | 2 | 2 (83,595), 1 (29,159) |  |
| SP_CHRNKIDN | numeric | 0.0 | 2 | 1 | 2 | 2 (97,135), 1 (15,619) |  |
| SP_CNCR | numeric | 0.0 | 2 | 1 | 2 | 2 (107,021), 1 (5,733) |  |
| SP_COPD | numeric | 0.0 | 2 | 1 | 2 | 2 (102,649), 1 (10,105) |  |
| SP_DEPRESSN | numeric | 0.0 | 2 | 1 | 2 | 2 (92,712), 1 (20,042) |  |
| SP_DIABETES | numeric | 0.0 | 2 | 1 | 2 | 2 (79,776), 1 (32,978) |  |
| SP_ISCHMCHT | numeric | 0.0 | 2 | 1 | 2 | 2 (70,589), 1 (42,165) |  |
| SP_OSTEOPRS | numeric | 0.0 | 2 | 1 | 2 | 2 (98,063), 1 (14,691) |  |
| SP_RA_OA | numeric | 0.0 | 2 | 1 | 2 | 2 (101,842), 1 (10,912) |  |
| SP_STRKETIA | numeric | 0.0 | 2 | 1 | 2 | 2 (109,803), 1 (2,951) |  |
| MEDREIMB_IP | numeric | 0.0 | 1,458 | -3000.0 | 105000.0 | 0.00 (101,023), 4000.00 (725), 3000.00 (698) | 7 negative values |
| BENRES_IP | numeric | 0.0 | 67 | 0.0 | 36200.0 | 0.00 (100,788), 1100.00 (10,260), 2200.00 (1,226) |  |
| PPPYMT_IP | numeric | 0.0 | 48 | 0.0 | 68000.0 | 0.00 (112,463), 4000.00 (22), 5000.00 (21) |  |
| MEDREIMB_OP | numeric | 0.0 | 1,131 | -100.0 | 36800.0 | 0.00 (58,598), 100.00 (2,477), 200.00 (1,975) | 85 negative values |
| BENRES_OP | numeric | 0.0 | 485 | 0.0 | 9500.0 | 0.00 (64,941), 20.00 (4,151), 10.00 (3,541) |  |
| PPPYMT_OP | numeric | 0.0 | 48 | 0.0 | 15000.0 | 0.00 (111,251), 200.00 (169), 1000.00 (129) |  |
| MEDREIMB_CAR | numeric | 0.0 | 719 | 0.0 | 10210.0 | 0.00 (27,765), 50.00 (941), 30.00 (871) |  |
| BENRES_CAR | numeric | 0.0 | 225 | 0.0 | 2760.0 | 0.00 (30,037), 10.00 (2,691), 20.00 (2,624) |  |
| PPPYMT_CAR | numeric | 0.0 | 115 | 0.0 | 1830.0 | 0.00 (100,508), 10.00 (1,490), 100.00 (1,226) |  |
