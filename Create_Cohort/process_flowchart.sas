/* ==============================================================================
   STEP 1: INITIAL COUNT & CREATE COHORT C1
   ============================================================================== */

/* 1a. Count unique individuals in original cohort */
proc sql;
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_initial_cohort
    from sasdata1.filtered_treatment_cohort;
quit;

/* 1b. Create C1: Filter to individuals with >= 1 N06A claim between 2015-01-01 and 2017-12-31 */
proc sql;
    create table work.C1 as
    select *
    from sasdata1.filtered_treatment_cohort
    where PHA_ATC_CLA like 'N06A%' 
          and datepart(EXE_SOI_DTD) between '01Jan2015'd and '31Dec2017'd; 
    ;

    /* Count unique individuals in C1 */
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_unique_C1
    from work.C1;
quit;


/* ==============================================================================
   STEP 2: ANTICOHORT FILTERS (2014 N06A / N06C) & CREATE COHORT C2
   ============================================================================== */

/* In preparation of STEP 2 */
proc sql;
    create table work.C1_first_2015 as
    select 
        BEN_NIR_PSA,
        BEN_RNG_GEM,
		BEN_AMA_COD,
		EXE_SOI_DTD,
        min(datepart(EXE_SOI_DTD)) as min_2015_dtd format=DATE9.
    from work.C1
    where datepart(EXE_SOI_DTD) between '01JAN2015'd and '31DEC2015'd
    group by BEN_NIR_PSA, BEN_RNG_GEM;
quit;


/* ==============================================================================
   STEP 2a & 2b: COUNTS IN ANTICOHORT (2014)
   ============================================================================== */
proc sql;
    /* 2a. Count N06A or N06C in 2014 in anticohort */
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_anti_N06A_N06C_2014
    from sasdata1.final_treatment_anticohort2
    where (PHA_ATC_CLA like 'N06A%' or PHA_ATC_CLA like 'N06C%')
      and datepart(EXE_SOI_DTD) between '01JAN2014'd and '31DEC2014'd;

    /* 2b. Count N06C only in 2014 in anticohort */
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_anti_N06C_2014
    from sasdata1.final_treatment_anticohort2
    where PHA_ATC_CLA like 'N06C%'
      and datepart(EXE_SOI_DTD) between '01JAN2014'd and '31DEC2014'd;
quit;


/* ==============================================================================
   STEP 2d.1: FAST PRE-FILTER OF ANTICOHORT
   ============================================================================== */
proc sql;
    create table work.anti_filtered as
    select distinct BEN_NIR_PSA, BEN_RNG_GEM, EXE_SOI_DTD, BEN_AMA_COD, datepart(EXE_SOI_DTD) as anti_dtd
    from sasdata1.final_treatment_anticohort2
    where (PHA_ATC_CLA like 'N06A%' or PHA_ATC_CLA like 'N06C%');
quit;


/* ==============================================================================
   STEP 2c & 2d.2: COUNT OVERLAP & IDENTIFY EXCLUSIONS (FAST JOIN)
   ============================================================================== */
proc sql;
    /* 2c. Count overlap using the filtered work table */
    select count(distinct catx('_', c1_idx.BEN_NIR_PSA, put(c1_idx.BEN_RNG_GEM, z2.))) as count_overlap_C1_anti
    from work.C1_first_2015 as c1_idx
    inner join work.anti_filtered as anti
        on c1_idx.BEN_NIR_PSA = anti.BEN_NIR_PSA
       and c1_idx.BEN_RNG_GEM = anti.BEN_RNG_GEM
    where anti.anti_dtd + 31 >= (c1_idx.min_2015_dtd - 365)
      and anti.anti_dtd < c1_idx.min_2015_dtd
      /* Condition: Age diff vs Date diff within +/- 1 year */
      and abs(
            (c1_idx.BEN_AMA_COD - anti.BEN_AMA_COD) - 
            (year(datepart(c1_idx.EXE_SOI_DTD)) - year(datepart(anti.EXE_SOI_DTD)))
          ) <= 1; /* NO CHANGE d*/

    /* 2d.2. Build exclusion list */
    create table work.patients_to_exclude as
    select distinct c1_idx.BEN_NIR_PSA, c1_idx.BEN_RNG_GEM
    from work.C1_first_2015 as c1_idx
    inner join work.anti_filtered as anti
        on c1_idx.BEN_NIR_PSA = anti.BEN_NIR_PSA
       and c1_idx.BEN_RNG_GEM = anti.BEN_RNG_GEM
    where anti.anti_dtd + 31 >= (c1_idx.min_2015_dtd - 365)
      and anti.anti_dtd < c1_idx.min_2015_dtd;
quit;


/* ==============================================================================
   STEP 2d.3: CREATE C2 & SUMMARY
   ============================================================================== */
proc sql;
    /* Create C2 dataset */
    create table work.C2 as
    select c1.*
    from work.C1 as c1
    left join work.patients_to_exclude as ex
        on c1.BEN_NIR_PSA = ex.BEN_NIR_PSA
       and c1.BEN_RNG_GEM = ex.BEN_RNG_GEM
    where ex.BEN_NIR_PSA is missing;

    /* Count unique individuals in C2 */
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_unique_C2
    from work.C2;
quit;

/* Clean up temporary work tables */
proc delete data=work.anti_filtered work.patients_to_exclude; run;



/* ==============================================================================
   STEP 3: PRIOR HOSPITALIZATION FILTER & CREATE COHORT C3
   ============================================================================== */

proc sql;
    /* 3a. Count C2 individuals with hospital record prior to 2015-01-01 */
    select count(distinct BEN_NIR_PSA) as count_prior_hosp_in_C2
    from work.C2
    where BEN_NIR_PSA in (
        select distinct NIR_ANO_17
        from sasdata1.master_hospital_extract
        where datepart(EXE_SOI_DTD) < '01JAN2015'd
    );

    /* 3b. Create C3: Remove prior hospitalizations from C2 */
    create table work.C3 as
    select *
    from work.C2
    where BEN_NIR_PSA not in (
        select distinct NIR_ANO_17
        from sasdata1.master_hospital_extract
        where datepart(EXE_SOI_DTD) < '01JAN2015'd
    );

    /* Count unique individuals in C3 */
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_unique_C3
    from work.C3;
quit;

/* ==============================================================================
   STEP 3.1: PRE-FILTER PRIOR HOSPITAL RECORDS (< 01JAN2015)
   ============================================================================== */
proc sql;
    create table work.hosp_prior as
    select distinct 
        NIR_ANO_17, 
        AGE_ANN, 
        datepart(EXE_SOI_DTD) as hosp_dtd
    from sasdata1.master_hospital_extract
    where datepart(EXE_SOI_DTD) < '01JAN2015'd;
quit;


/* ==============================================================================
   STEP 3.2: IDENTIFY C2 PATIENTS TO EXCLUDE (CONSISTENCY RULE APPLIED)
   ============================================================================== */
proc sql;
    create table work.c2_hosp_to_exclude as
    select distinct 
        c2.BEN_NIR_PSA, 
        c2.BEN_RNG_GEM
    from work.C2 as c2
    inner join work.hosp_prior as hosp
        on c2.BEN_NIR_PSA = hosp.NIR_ANO_17
    /* Condition: Age diff vs Date diff within +/- 1 year */
    where abs(
            (c2.BEN_AMA_COD - hosp.AGE_ANN) - 
            (year(datepart(c2.EXE_SOI_DTD)) - year(hosp.hosp_dtd))
          ) <= 1;
quit;


/* ==============================================================================
   STEP 3a & 3b: COUNT OVERLAP & CREATE WORK.C3
   ============================================================================== */
proc sql;
    /* 3a. Count C2 individuals with matching prior hospital record */
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_prior_hosp_in_C2
    from work.c2_hosp_to_exclude;

    /* 3b. Create C3: Exclude those individuals from C2 */
    create table work.C3 as
    select c2.*
    from work.C2 as c2
    left join work.c2_hosp_to_exclude as ex
        on c2.BEN_NIR_PSA = ex.BEN_NIR_PSA
       and c2.BEN_RNG_GEM = ex.BEN_RNG_GEM
    where ex.BEN_NIR_PSA is missing;

    /* Count unique individuals remaining in C3 */
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_unique_C3
    from work.C3;
quit;

/* Clean up temporary tables */
proc delete data=work.hosp_prior work.c2_hosp_to_exclude; run;






/* ==============================================================================
   STEP 4: CO-MEDICATION EXCLUSIONS (N03A, N05A, N06BA) & CREATE COHORT C4
   ============================================================================== */

proc sql;
    /* 4a. Count C3 individuals present in anticohort with N03A, N05A, or N06BA */
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_other_meds_in_C3
    from work.C3
    where catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.)) in (
        select distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))
        from sasdata1.final_treatment_anticohort2
        where PHA_ATC_CLA in ('N03A', 'N05A', 'N06BA')
           or PHA_ATC_CLA like 'N03A%'
           or PHA_ATC_CLA like 'N05A%'
           or PHA_ATC_CLA like 'N06BA%'
    );

    /* 4b. Create C4: Remove those individuals from C3 */
    create table work.C4 as
    select *
    from work.C3
    where catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.)) not in (
        select distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))
        from sasdata1.final_treatment_anticohort2
        where PHA_ATC_CLA in ('N03A', 'N05A', 'N06BA')
           or PHA_ATC_CLA like 'N03A%'
           or PHA_ATC_CLA like 'N05A%'
           or PHA_ATC_CLA like 'N06BA%'
    );

    /* Count unique individuals in C4 */
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_unique_C4
    from work.C4;
quit;


/* ==============================================================================
   STEP 5: LEFT JOIN WITH HOSPITAL DATA & MAX TREATMENT DATES TO CREATE COHORT C5
   ============================================================================== */

proc sql;
    create table sasdata1.C5 as
    select 
        c4.*,
        hosp.*,
        trt.*
    from work.C4 as c4
    left join sasdata1.master_hospital_extract(rename=(EXE_SOI_DTD = hosp_exe_soi_dtd)) as hosp
        on c4.BEN_NIR_PSA = hosp.NIR_ANO_17 
    left join sasdata1.ben_max_trt_dtd(rename=(BEN_NIR_PSA = trt_BEN_NIR_PSA 
                                               BEN_RNG_GEM = trt_BEN_RNG_GEM)) as trt
        on c4.BEN_NIR_PSA = trt.trt_BEN_NIR_PSA 
       and c4.BEN_RNG_GEM = trt.trt_BEN_RNG_GEM;
quit;

/* ==============================================================================
STEP 6: more select join and filter
 ============================================================================== */


libname rfcommun "/sasdata/prd/commun/data/rfcommun";
libname sasdata1 "/sasdata/prd/users/44a001478710899";

proc sql;
    /* 1. Aggregate GPs (spe=1) by commune */
    create table work.n_PS as
    select 
        commune, 
        sum(nombre) as nb_GP
    from rfcommun.denb_ps_commune_01jan2015
    where spe = '1'
    group by commune;

    /* 2. Process sasdata1.c5 */
    create table work.c5_filter as
    select 
        c5.*,
        cats(substr(c5.BEN_RES_DPT, 2), c5.BEN_RES_COM) as CODGEO,
        cats(c5.BEN_NIR_PSA, '_', c5.BEN_RNG_GEM) as id,
        edi.*,
        coalesce(ps.nb_GP, 0) as nb_GP
    from sasdata1.c5(drop=FLX_DIS_DTD BEN_SEX_COD COH_NAI_RET 
                          COH_SEX_RET TYP_GEN_RSA SEQ_IND 
                          trt_BEN_NIR_PSA trt_BEN_RNG_GEM) as c5
    left join rfcommun.defa_uu2015 as edi
        on cats(substr(c5.BEN_RES_DPT, 2), c5.BEN_RES_COM) = edi.CODGEO
    left join work.n_PS as ps
        on cats(substr(c5.BEN_RES_DPT, 2), c5.BEN_RES_COM) = ps.commune
    where c5.BEN_RES_DPT not in (
        '971','972','973','974','975','976','977','978','999','209','990',
        '991','992','993','994','099','098','097','995'
    );

    /* Drop BEN_RES_DPT and BEN_RES_COM now that SQL evaluation is complete */
    alter table work.c5_filter
    drop BEN_RES_DPT, BEN_RES_COM;
quit;
