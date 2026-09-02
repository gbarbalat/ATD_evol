/* ==============================================================================
   STEP 0: JUST COUNT the number of women aged 18-39 in 2015-2017 avec BEN_IDT_ANO
   ============================================================================== */
%macro loop_exe_and_flx_FC0(start=01JAN2015:00:00:00, stop=31DEC2015:23:59:59);

   %local exe_start exe_stop_limit 
          exe_cur_b exe_cur_e exe_cur_b_c exe_cur_e_c
          flx_start_limit flx_end_limit flx_cur flx_cur_c;

   /* Convert inputs to numeric SAS datetimes */
   %let exe_start      = %sysfunc(inputn(&start, datetime20.));
   %let exe_stop_limit = %sysfunc(inputn(&stop,  datetime20.));

   /* Initialize outer loop EXE pointer to the 1st of the starting month */
   %let exe_cur_b = %sysfunc(intnx(dtmonth, &exe_start, 0, b));

   /* ==================== OUTER LOOP: EXE_SOI_DTD ==================== */
   %do %while (&exe_cur_b <= &exe_stop_limit and &exe_cur_b ne .);

      /* Calculate end of current EXE month (e.g., 28FEB2015:23:59:59) */
      %let exe_cur_e   = %sysfunc(intnx(dtmonth, &exe_cur_b, 0, e));
      
      /* Format EXE boundaries for SQL literals */
      %let exe_cur_b_c = %sysfunc(putn(&exe_cur_b, datetime20.));
      %let exe_cur_e_c = %sysfunc(putn(&exe_cur_e, datetime20.));

      /* Set FLX boundaries relative to the current EXE month:
         - Starts: 1 month after current EXE month start
         - Ends:   6 months after current EXE month start */
      %let flx_start_limit = %sysfunc(intnx(dtmonth, &exe_cur_b, 1, b));
      %let flx_end_limit   = %sysfunc(intnx(dtmonth, &exe_cur_b, 6, b));

      %let flx_cur = &flx_start_limit;

      /* ==================== INNER LOOP: FLX_DIS_DTD ==================== */
      %do %while (&flx_cur <= &flx_end_limit and &flx_cur ne .);

         /* Format current FLX datetime for SQL literal */
         %let flx_cur_c = %sysfunc(putn(&flx_cur, datetime20.));

         %put NOTE: Processing EXE range [&exe_cur_b_c TO &exe_cur_e_c] with FLX_DIS_DTD = &flx_cur_c;

         proc sql;
            create table WORK.QUERY_FOR_ER_PRS_F as
            select distinct
               prs.BEN_NIR_PSA,
               prs.BEN_RNG_GEM

            from oravue.ER_PRS_F as prs
                
            where prs.EXE_SOI_DTD between "%sysfunc(strip(&exe_cur_b_c))"dt 
                                      and "%sysfunc(strip(&exe_cur_e_c))"dt
              and prs.FLX_DIS_DTD = "%sysfunc(strip(&flx_cur_c))"dt  
              and prs.BEN_SEX_COD = 2
			  and prs.BEN_AMA_COD between 18 and 39;   
         quit;

         proc append base=WORK.ALL_ER_PRS_F data=WORK.QUERY_FOR_ER_PRS_F force;
         run;

         /* Advance FLX by 1 month */
         %let flx_cur = %sysfunc(intnx(dtmonth, &flx_cur, 1, b));

      %end; /* End Inner Loop */

      /* Advance EXE start pointer to the 1st of next month */
      %let exe_cur_b = %sysfunc(intnx(dtmonth, &exe_cur_b, 1, b));

   %end; /* End Outer Loop */

   proc datasets lib=work nolist;
      delete QUERY_FOR_ER_PRS_F;
   quit;

   /* FINAL PASS: Remove duplicate couples across all stacked months */
   PROC SQL;
      CREATE TABLE WORK.ALL_ER_PRS_F AS
      SELECT DISTINCT BEN_NIR_PSA, BEN_RNG_GEM
      FROM WORK.ALL_ER_PRS_F;
   QUIT;

   %put NOTE: Nested monthly loops finished successfully.;

%mend loop_exe_and_flx_FC0;

/* Execution Example */
%loop_exe_and_flx_FC0(start=01JAN2015:00:00:00, stop=31DEC2017:23:59:59);


/* 1. Inner join with IR_BEN_R and select distinct BEN_IDT_ANO */
PROC SQL;
   CREATE TABLE ORAUSER.UNIQUE_BEN_NIR_TOT 
   as select distinct ben_nir_psa, ben_rng_gem
		FROM WORK.ALL_ER_PRS_F ;
/* %m_stats_table(nom_table=UNIQUE_BEN_IDT) ; */
QUIT;

proc sql;
   create table ORAUSER.UNIQUE_BEN_IDT as
   select distinct 
      ir.BEN_IDT_ANO
   from ORAUSER.UNIQUE_BEN_NIR_TOT keys
   inner join ORAVUE.IR_BEN_R ir
       on  keys.BEN_NIR_PSA = ir.BEN_NIR_PSA
       and keys.BEN_RNG_GEM = ir.BEN_RNG_GEM;
quit;

/* Call stats macro after SQL block completes */
%m_stats_table(nom_table=ORAUSER.UNIQUE_BEN_IDT);


/* 2. Count the number of unique BEN_IDT_ANO */
PROC SQL;
   SELECT COUNT(*) AS total_unique_ben_idt
   FROM ORAUSER.UNIQUE_BEN_IDT;
QUIT;







/* ==============================================================================
   STEP 1: INITIAL COUNT & CREATE COHORT C1
   ============================================================================== */

/* 1a. Count unique individuals in original cohort */
proc sql;
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_initial_cohort
    from sasdata1.filtered_treatment_cohort;
quit;

/* 1b. Create C1: Filter to individuals with >= 1 N06A claim between 2015 and 2017 */
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

/* ==============================================================================
   STEP 3.0: FIND FIRST ANTIDEPRESSANT (N06A) PRESCRIPTION DATE PER PATIENT IN C2
   ============================================================================== */
proc sql;
    create table work.c2_first_atd as
    select 
        BEN_NIR_PSA,
        BEN_RNG_GEM,
        min(datepart(EXE_SOI_DTD)) as min_atd_dtd format=DATE9.
    from work.C2
    where PHA_ATC_LIB like 'N06A%'
    group by BEN_NIR_PSA, BEN_RNG_GEM;
quit;


/* ==============================================================================
   STEP 3.1: PRE-FILTER PRIOR HOSPITAL RECORDS UP TO END OF 2017
   ============================================================================== */
proc sql;
    create table work.hosp_candidates as
    select distinct 
        NIR_ANO_17, 
        AGE_ANN, 
        datepart(EXE_SOI_DTD) as hosp_dtd format=DATE9.
    from sasdata1.master_hospital_extract
    where datepart(EXE_SOI_DTD) <= '31DEC2017'd
      and (
            source_db = 'RIP' 
            or (source_db <> 'RIP' and DGN_PAL like 'F%')
          );
quit;


/* ==============================================================================
   STEP 3.2: IDENTIFY C2 PATIENTS TO EXCLUDE (HOSPITAL ADMISSION BEFORE FIRST ATD)
   ============================================================================== */
proc sql;
    create table work.c2_hosp_to_exclude as
    select distinct 
        c2.BEN_NIR_PSA, 
        c2.BEN_RNG_GEM
    from work.C2 as c2
    inner join work.c2_first_atd as atd
        on c2.BEN_NIR_PSA = atd.BEN_NIR_PSA
       and c2.BEN_RNG_GEM = atd.BEN_RNG_GEM
    inner join work.hosp_candidates as hosp
        on c2.BEN_NIR_PSA = hosp.NIR_ANO_17
    /* Admission must occur before the first N06A prescription */
    where hosp.hosp_dtd < atd.min_atd_dtd
    /* Consistency rule: Age diff vs Date diff within +/- 1 year */
      and abs(
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
proc delete data=work.c2_first_atd work.hosp_candidates work.c2_hosp_to_exclude; run;


/* ==============================================================================
   STEP 4: PRIOR MEDICATION EXCLUSIONS (N03A, N05A, N06BA) & CREATE COHORT C4
   ============================================================================== */

/* ==============================================================================
   STEP 4.0: IDENTIFY EARLIEST EXCLUSION DRUG DATES (N03A, N05A, N06BA)
   Across anticohort2, work.C3, and stimulants_2015_2020 with Age-Date Check
   ============================================================================== */

/* 1. Extract candidate exclusion drugs from all 3 sources */
proc sql;
    create table work.all_exclusion_candidates as
    /* Source 1: anticohort2 */
    select distinct 
        anti.BEN_NIR_PSA, 
        anti.BEN_RNG_GEM
    from sasdata1.final_treatment_anticohort2 as anti
    inner join work.C3 as c3
        on anti.BEN_NIR_PSA = c3.BEN_NIR_PSA
       and anti.BEN_RNG_GEM = c3.BEN_RNG_GEM
    where (anti.PHA_ATC_CLA like 'N03A%' or anti.PHA_ATC_CLA like 'N05A%' or anti.PHA_ATC_CLA like 'N06BA%')
      and abs((c3.BEN_AMA_COD - anti.BEN_AMA_COD) - (year(datepart(c3.EXE_SOI_DTD)) - year(datepart(anti.EXE_SOI_DTD)))) <= 1

    union all

    /* Source 2: work.C3 itself */
    select distinct 
        BEN_NIR_PSA, 
        BEN_RNG_GEM, 
        datepart(EXE_SOI_DTD) as ex_dtd format=DATE9.
    from work.C3
    where (PHA_ATC_CLA like 'N03A%' or PHA_ATC_CLA like 'N05A%' or PHA_ATC_CLA like 'N06BA%'
        or PHA_ATC_LIB like 'N03A%' or PHA_ATC_LIB like 'N05A%' or PHA_ATC_LIB like 'N06BA%')

    union all

    /* Source 3: stimulants_2015_2020 */
    select distinct 
        stim.BEN_NIR_PSA, 
        stim.BEN_RNG_GEM, 
        datepart(stim.EXE_SOI_DTD) as ex_dtd format=DATE9.
    from sasdata1.stimulants_2015_2020 as stim
    inner join work.C3 as c3
        on stim.BEN_NIR_PSA = c3.BEN_NIR_PSA
       and stim.BEN_RNG_GEM = c3.BEN_RNG_GEM
    where (stim.PHA_ATC_CLA like 'N03A%' or stim.PHA_ATC_CLA like 'N05A%' or stim.PHA_ATC_CLA like 'N06BA%')
      and abs((c3.BEN_AMA_COD - stim.BEN_AMA_COD) - (year(datepart(c3.EXE_SOI_DTD)) - year(datepart(stim.EXE_SOI_DTD)))) <= 1;
quit;

/* 2. Find earliest exclusion drug date per patient */
proc sql;
    create table work.min_exclusion_dates as
    select 
        BEN_NIR_PSA,
        BEN_RNG_GEM,
        min(ex_dtd) as min_ex_dtd format=DATE9.
    from work.all_exclusion_candidates
    group by BEN_NIR_PSA, BEN_RNG_GEM;
quit;


/* ==============================================================================
   STEP 4.1: BUILD c3_first_atd
   Keep ONLY individuals whose first N06A precedes all exclusion drugs
   ============================================================================== */
proc sql;
    create table work.c3_first_atd as
    select 
        c3.BEN_NIR_PSA,
        c3.BEN_RNG_GEM,
        min(datepart(c3.EXE_SOI_DTD)) as min_atd_dtd format=DATE9.
    from work.C3 as c3
    left join work.min_exclusion_dates as ex
        on c3.BEN_NIR_PSA = ex.BEN_NIR_PSA
       and c3.BEN_RNG_GEM = ex.BEN_RNG_GEM
    where (c3.PHA_ATC_LIB like 'N06A%' or c3.PHA_ATC_CLA like 'N06A%')
    group by c3.BEN_NIR_PSA, c3.BEN_RNG_GEM, ex.min_ex_dtd
    /* N06A date must be strictly earlier than any exclusion drug date */
    having min(datepart(c3.EXE_SOI_DTD)) < coalesce(ex.min_ex_dtd, '31DEC2099'd);
quit;


/* ==============================================================================
   STEP 4.2 & 4b: CREATE C4 AND COUNT EXCLUSIONS
   ============================================================================== */
proc sql;
    /* 4a. Count C3 individuals excluded due to prior N03A/N05A/N06BA */
    select count(distinct catx('_', c3.BEN_NIR_PSA, put(c3.BEN_RNG_GEM, z2.))) as count_other_meds_excluded
    from work.C3 as c3
    where catx('_', c3.BEN_NIR_PSA, put(c3.BEN_RNG_GEM, z2.)) not in (
        select distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))
        from work.c3_first_atd
    );

    /* 4b. Create C4: Retain only valid patients from c3_first_atd */
    create table work.C4 as
    select c3.*
    from work.C3 as c3
    inner join work.c3_first_atd as valid
        on c3.BEN_NIR_PSA = valid.BEN_NIR_PSA
       and c3.BEN_RNG_GEM = valid.BEN_RNG_GEM;

    /* Count unique individuals remaining in C4 */
    select count(distinct catx('_', BEN_NIR_PSA, put(BEN_RNG_GEM, z2.))) as count_unique_C4
    from work.C4;
quit;

/* Clean up temporary tables */
proc delete data=work.all_exclusion_candidates work.min_exclusion_dates work.c3_first_atd; run;



/* ==============================================================================
   STEP 5: LEFT JOIN WITH HOSPITAL DATA, STIMULANT DATA & MAX TREATMENT DATES TO CREATE COHORT C5
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
       and c4.BEN_RNG_GEM = trt.trt_BEN_RNG_GEM
	left join sasdata1.stimulants_2015_2020(rename=(BEN_NIR_PSA = stim_BEN_NIR_PSA 
                                               BEN_RNG_GEM = stim_BEN_RNG_GEM)) as stim
        on c4.BEN_NIR_PSA = stim.stim_BEN_NIR_PSA 
       and c4.BEN_RNG_GEM = stim.stim_BEN_RNG_GEM;
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
