/* from FC2, go to ER_PRS_F, and gather a whole bunch of data */

%macro loop_exe_and_flx_PRS_Au(start=01JAN2015:00:00:00, stop=31DEC2015:23:59:59);

   %local exe_start exe_stop_limit 
          exe_cur_b exe_cur_e exe_cur_b_c exe_cur_e_c
          flx_start_limit flx_end_limit flx_cur flx_cur_c;

   /* Convert inputs to numeric SAS datetimes */
   %let exe_start      = %sysfunc(inputn(&start, datetime20.));
   %let exe_stop_limit = %sysfunc(inputn(&stop,  datetime20.));

   /* Initialize outer loop EXE pointer to the 1st of the starting month */
   %let exe_cur_b = %sysfunc(intnx(dtmonth, &exe_start, 0, b));

   proc datasets lib=work nolist;
   		delete ALL_ER_PRS_F_Au;
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
            create table WORK.QUERY_FOR_ER_PRS_F_Au as
            select 
			   FC2.BEN_IDT_ANO,
			   FC2.MAX_TRT_DTD,
			   FC2.BEN_DCD_DTE,
			   FC2.DT_FIRST_AD,

               prs.BEN_NIR_PSA,
               prs.BEN_RNG_GEM,
               prs.BEN_AMA_COD,
               prs.EXE_SOI_DTD,
               prs.PRE_PRE_DTD,
               prs.PSP_SPE_COD,
               prs.PSP_ACT_NAT,
			   prs.PSE_SPE_COD,
               prs.PSE_ACT_NAT,
			   prs.RGO_ASU_NAT, /* 40 AT/MP, 80 Invalidité */
			   prs.RGM_COD, /* code petit regime pour AAH = 180 181 188 189 */
			   prs.RGM_GRG_COD, /* =1 pour AAH */
               prs.BEN_RES_DPT,
               prs.BEN_RES_COM, 
               prs.PRS_GRS_DTD,prs.EXE_SOI_DTD - FC2.dt_first_ad

            from oravue.ER_PRS_F as prs

            /* Cohort key filter */
            inner join ORAUSER.FC2 as FC2
                on  prs.BEN_NIR_PSA = FC2.BEN_NIR_PSA
                and prs.BEN_RNG_GEM = FC2.BEN_RNG_GEM
                
            where prs.EXE_SOI_DTD between "%sysfunc(strip(&exe_cur_b_c))"dt 
                                      and "%sysfunc(strip(&exe_cur_e_c))"dt
              and prs.FLX_DIS_DTD = "%sysfunc(strip(&flx_cur_c))"dt  
			  and (prs.EXE_SOI_DTD - FC2.dt_first_ad)/ 86400 >=  - 366
  			  and (prs.EXE_SOI_DTD - FC2.dt_first_ad)/ 86400 <=  + 366

			  

			  and prs.BEN_CDI_NIR = "00"
			  and prs.DPN_QLF <> 71;
       quit;

         proc append base=WORK.ALL_ER_PRS_F_Au data=WORK.QUERY_FOR_ER_PRS_F_Au force;
         run;

         /* Advance FLX by 1 month */
         %let flx_cur = %sysfunc(intnx(dtmonth, &flx_cur, 1, b));

      %end; /* End Inner Loop */

      /* Advance EXE start pointer to the 1st of next month */
      %let exe_cur_b = %sysfunc(intnx(dtmonth, &exe_cur_b, 1, b));

   %end; /* End Outer Loop */

   proc datasets lib=work nolist;
      delete QUERY_FOR_ER_PRS_F_Au;
   quit;

   proc sort data=WORK.ALL_ER_PRS_F_Au out=WORK.ALL_ER_PRS_F_dedup_Au nodupkey;
   		by ben_idt_ano exe_soi_dtd ben_res_dpt ;
   run;

   %put NOTE: Nested monthly loops finished successfully.;

%mend loop_exe_and_flx_PRS_Au;

/* Execution Example*/
%loop_exe_and_flx_PRS_Au(start=01JAN2021:00:00:00, stop=31DEC2024:23:59:59);

/* to sasdata1 */
proc sql;
   create table sasdata1.PRS_Au as
   select *
   from work.all_er_prs_f_Au;
quit;
