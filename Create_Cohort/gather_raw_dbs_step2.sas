/* ==============================================================================
   STEP 2: SELECT ER_PRS_F VAR IN THESE INDIVIDUALS
   ============================================================================== */
%macro loop_exe_and_flx_FC1_2(start=01JAN2015:00:00:00, stop=31DEC2015:23:59:59);

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
      %let flx_start_limit = %sysfunc(intnx(dtmonth, &exe_cur_b, 0, b));
      %let flx_end_limit   = %sysfunc(intnx(dtmonth, &exe_cur_b, 7, b));

      %let flx_cur = &flx_start_limit;

      /* ==================== INNER LOOP: FLX_DIS_DTD ==================== */
      %do %while (&flx_cur <= &flx_end_limit and &flx_cur ne .);

         /* Format current FLX datetime for SQL literal */
         %let flx_cur_c = %sysfunc(putn(&flx_cur, datetime20.));

         %put NOTE: Processing EXE range [&exe_cur_b_c TO &exe_cur_e_c] with FLX_DIS_DTD = &flx_cur_c;

         proc sql;
            create table WORK.QUERY_FOR_ER_PRS_F as
            select 

			   fc.BEN_IDT_ANO,
			   fc.MAX_TRT_DTD,
			   fc.BEN_DCD_DTE,

               prs.BEN_NIR_PSA,
               prs.BEN_RNG_GEM,
               prs.BEN_AMA_COD,
               prs.EXE_SOI_DTD,
               prs.PRE_PRE_DTD,
               prs.PSP_SPE_COD,
               prs.PSP_ACT_NAT,
               prs.BEN_RES_DPT,
               prs.BEN_RES_COM, 
               prs.PRS_GRS_DTD,

               pha.PHA_ACT_QSN,
			   pha.PHA_PRS_C13,
               
               ref.PHA_FRM_LIB,
               ref.PHA_ATC_LIB,
               ref.PHA_SUB_DOS,
               ref.PHA_UPC_NBR,
               ref.PHA_ATC_CLA

            from oravue.ER_PRS_F as prs

            /* Cohort key filter */
            inner join ORAUSER.FC1_1 as fc
                on  prs.BEN_NIR_PSA = fc.BEN_NIR_PSA
                and prs.BEN_RNG_GEM = fc.BEN_RNG_GEM

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
                on pha.PHA_PRS_C13 = ref.PHA_CIP_C13 
                
            where prs.EXE_SOI_DTD between "%sysfunc(strip(&exe_cur_b_c))"dt 
                                      and "%sysfunc(strip(&exe_cur_e_c))"dt
              and prs.FLX_DIS_DTD = "%sysfunc(strip(&flx_cur_c))"dt  
              and prs.BEN_SEX_COD = 2
              and (
                    ref.PHA_ATC_CLA like 'N05A%' 
                 or ref.PHA_ATC_CLA like 'N05B%' 
                 or ref.PHA_ATC_CLA like 'N06BA%'
                 or ref.PHA_ATC_CLA like 'N05C%' 
                 or ref.PHA_ATC_CLA like 'N06A%' 
                 or ref.PHA_ATC_CLA like 'N03A%' 
              );
		
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

   proc sort data=WORK.ALL_ER_PRS_F out=WORK.ALL_ER_PRS_F_dedup nodupkey;
   		by ben_idt_ano exe_soi_dtd ben_res_dpt pha_act_qsn pha_prs_c13;
   run;

   %put NOTE: Nested monthly loops finished successfully.;

%mend loop_exe_and_flx_FC1_2;

/* Execution Example 
%loop_exe_and_flx_FC1_2(start=01JAN2015:00:00:00, stop=31JAN2015:23:59:59);*/
%loop_exe_and_flx_FC1_2(start=01JAN2006:00:00:00, stop=31DEC2019:23:59:59);

/* to sasdata1 */
proc sql;
   create table sasdata1.fc1_2 as
   select *
   from work.all_er_prs_f;
quit;
