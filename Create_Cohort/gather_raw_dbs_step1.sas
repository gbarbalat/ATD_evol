/* ==============================================================================
   STEP 1: COHORT JUST ONE ATD
   ============================================================================== */
%macro loop_exe_and_flx_FC1_1(start=01JAN2015:00:00:00, stop=31DEC2015:23:59:59);

   %local exe_start exe_stop_limit 
          exe_cur_b exe_cur_e exe_cur_b_c exe_cur_e_c
          flx_start_limit flx_end_limit flx_cur flx_cur_c;

   /* Convert inputs to numeric SAS datetimes */
   %let exe_start      = %sysfunc(inputn(&start, datetime20.));
   %let exe_stop_limit = %sysfunc(inputn(&stop,  datetime20.));

   /* Initialize outer loop EXE pointer to the 1st of the starting month */
   %let exe_cur_b = %sysfunc(intnx(dtmonth, &exe_start, 0, b));

   proc datasets lib=work nolist;
   		delete ALL_ER_PRS_F;
   quit;

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
               prs.BEN_RNG_GEM,prs.EXE_SOI_DTD, prs.FLX_DIS_DTD

            from oravue.ER_PRS_F as prs

            inner join oravue.ER_PHA_F as pha
                on  prs.FLX_DIS_DTD = pha.FLX_DIS_DTD
                and prs.FLX_TRT_DTD = pha.FLX_TRT_DTD
                and prs.FLX_EMT_TYP = pha.FLX_EMT_TYP
                and prs.FLX_EMT_NUM = pha.FLX_EMT_NUM
                and prs.FLX_EMT_ORD = pha.FLX_EMT_ORD
                and prs.ORG_CLE_NUM = pha.ORG_CLE_NUM
                and prs.DCT_ORD_NUM = pha.DCT_ORD_NUM
                and prs.PRS_ORD_NUM = pha.PRS_ORD_NUM
                and prs.REM_TYP_AFF = pha.REM_TYP_AFF
                
            inner join oravue.IR_PHA_R as ref
                on pha.PHA_PRS_C13 = ref.PHA_RGE_C13 
                
            where prs.EXE_SOI_DTD between "%sysfunc(strip(&exe_cur_b_c))"dt 
                                      and "%sysfunc(strip(&exe_cur_e_c))"dt
              and prs.FLX_DIS_DTD = "%sysfunc(strip(&flx_cur_c))"dt  
              and prs.BEN_SEX_COD = 2
			  and prs.BEN_AMA_COD between 18 and 39
              and ref.PHA_ATC_CLA like 'N06A%' ;   
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

   /* FINAL PASS: Remove duplicate couples across all stacked months 
   PROC SQL;
      CREATE TABLE WORK.ALL_ER_PRS_F AS
      SELECT DISTINCT BEN_NIR_PSA, BEN_RNG_GEM
      FROM WORK.ALL_ER_PRS_F;
   QUIT;*/

   %put NOTE: Nested monthly loops finished successfully.;

%mend loop_exe_and_flx_FC1_1;

/* Execution Example 
%loop_exe_and_flx_FC1_1(start=01JAN2015:00:00:00, stop=28FEB2015:23:59:59);*/
%loop_exe_and_flx_FC1_1(start=01JAN2015:00:00:00, stop=31DEC2017:23:59:59);


/* 1. Inner join with IR_BEN_R and select distinct BEN_IDT_ANO */
PROC SQL;
   CREATE TABLE ORAUSER.UNIQUE_BEN_NIR_TOT 
   as select distinct ben_nir_psa, ben_rng_gem
		FROM WORK.ALL_ER_PRS_F ;
 %m_stats_table(nom_table=UNIQUE_BEN_IDT) ; 
QUIT;

/* 2. Collect all BEN_NIR_PSA, as well as BEN_DCD_DTE and MAX_TRT_DTD */
proc sql;
   create table ORAUSER.UNIQUE_BEN_IDT as
   select 
      ir.BEN_IDT_ANO,
      
      /* 1. Maximum overall treatment date per beneficiary */
      max(ir.MAX_TRT_DTD) format=datetime20. as MAX_TRT_DTD,
      
      /* 2. Real death date if present; falls back to 01JAN1600 if all rows are default */
      coalesce(
         max(case when ir.BEN_DCD_DTE ne '01JAN1600:00:00:00'dt then ir.BEN_DCD_DTE end),
         max(ir.BEN_DCD_DTE)
      ) format=datetime20. as BEN_DCD_DTE

   from ORAUSER.UNIQUE_BEN_NIR_TOT keys
   inner join ORAVUE.IR_BEN_R ir
       on  keys.BEN_NIR_PSA = ir.BEN_NIR_PSA
       and keys.BEN_RNG_GEM = ir.BEN_RNG_GEM
   group by 
      ir.BEN_IDT_ANO;
quit;
%m_stats_table(nom_table=ORAUSER.UNIQUE_BEN_IDT);

/* 3. Cohort of unique BEN_IDT_ANO, with all possible ben_nir_tot per BEN_IDT_ANO */
proc sql;
    create table orauser.FC1_1 as
    select distinct 
        u.*,
        ir.BEN_NIR_PSA,
        ir.BEN_RNG_GEM
    from orauser.UNIQUE_BEN_IDT as u
    inner join oravue.IR_BEN_R as ir
        on u.BEN_IDT_ANO = ir.BEN_IDT_ANO;
quit;
%m_stats_table(nom_table=FC1_1)
