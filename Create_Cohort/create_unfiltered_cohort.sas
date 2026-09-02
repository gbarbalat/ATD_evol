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

   /* FINAL PASS: Remove duplicate couples across all stacked months */
   PROC SQL;
      CREATE TABLE WORK.ALL_ER_PRS_F AS
      SELECT DISTINCT BEN_NIR_PSA, BEN_RNG_GEM
      FROM WORK.ALL_ER_PRS_F;
   QUIT;

   %put NOTE: Nested monthly loops finished successfully.;

%mend loop_exe_and_flx_FC1_1;

/* Execution Example */
%loop_exe_and_flx_FC1_1(start=01JAN2015:00:00:00, stop=31DEC2017:23:59:59);


/* 1. Inner join with IR_BEN_R and select distinct BEN_IDT_ANO */
PROC SQL;
   CREATE TABLE ORAUSER.UNIQUE_BEN_NIR_TOT 
   as select distinct ben_nir_psa, ben_rng_gem
		FROM WORK.ALL_ER_PRS_F ;
/* %m_stats_table(nom_table=UNIQUE_BEN_IDT) ; */
QUIT;

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

/* Call stats macro after SQL block completes */
%m_stats_table(nom_table=ORAUSER.UNIQUE_BEN_IDT);


/* 2. Count the number of unique BEN_IDT_ANO */
PROC SQL;
   SELECT COUNT(*) AS total_unique_ben_idt
   FROM ORAUSER.UNIQUE_BEN_IDT;
QUIT;

/* 3. Cohort of unique BEN_IDT_ANO, with all possible ben_nir_tot per BEN_IDT_ANO */
proc sql;
    create table work.FC1_1 as
    select distinct 
        u.BEN_IDT_ANO,
        ir.BEN_NIR_PSA,
        ir.BEN_RNG_GEM
    from orauser.UNIQUE_BEN_IDT as u
    inner join oravue.IR_BEN_R as ir
        on u.BEN_IDT_ANO = ir.BEN_IDT_ANO;
quit;

proc sql;
    create table oaruser.FC1_1 as
    select *
    from work.FC1_1;
quit;

%m_stats_table(nom_table=FC1_1)




/* ==============================================================================
   STEP 2: SELECT ER_PRS_F VAR IN THESE INDIVIDUALS
   ============================================================================== */
%macro loop_exe_and_flx(start=01JAN2015:00:00:00, stop=31DEC2015:23:59:59);

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
            select 
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
                on pha.PHA_PRS_C13 = ref.PHA_RGE_C13 
                
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

   %put NOTE: Nested monthly loops finished successfully.;

%mend loop_exe_and_flx;

/* Execution Example */
%loop_exe_and_flx(start=01JAN2006:00:00:00, stop=31DEC2020:23:59:59);



/* ==============================================================================
   STEP 3: SELECT RIP VAR IN THESE INDIVIDUALS
   ============================================================================== */
%macro extract_PMSI(start=09, stop=19);

/* 1. Clear/initialize the cumulative output table */
   proc sql;
      create table work.rip_extract_all like work.rip_extract_tmp; /* or empty shell */
   quit;

   	%do year = &start %to &stop;

        %let yr = %sysfunc(putn(&year., z2.));

		proc sql;
        
        create table work.rip_extract_tmp as 
        select 
            'RIP' as source_db,
            main.NIR_ANO_17, 
            main.EXE_SOI_DTD, 
            main.EXE_SOI_DTF, 
            for_dx.DGN_PAL,
            for_dx.AGE_ANN,

            /* --- FOR_ACT (Appears in 2012 / year >= 12) --- */
            %if %eval(&year < 12) %then %do;
                '' length=10 as FOR_ACT,
            %end;
            %else %do;
                for_dx.FOR_ACT,
            %end;

            /* --- COH_NAI_RET, COH_SEX_RET (Appear in 2014 / year >= 14) --- */
            %if %eval(&year < 14) %then %do;
                '0' as COH_NAI_RET,
                '0' as COH_SEX_RET,
            %end;
            %else %do;
                main.COH_NAI_RET,
                main.COH_SEX_RET,
            %end;

            /* --- TYP_GEN_RSA (Appears in 2015 / year >= 15) --- */
            %if %eval(&year < 15) %then %do;
                '0' as TYP_GEN_RSA,
            %end;
            %else %do;
                for_dx.TYP_GEN_RSA,
            %end;

            /* --- SEQ_IND (Appears in 2020 / year >= 20) --- */
            %if %eval(&year < 20) %then %do;
                '' as SEQ_IND,
            %end;
            %else %do;
                main.SEQ_IND,
            %end;

            for_dx.DEL_DAT,
            for_dx.PRE_JOU_NBJ,
            for_dx.PRE_DEM_JOU_NBJ,
            which_cim.CIM_LIL
        from 
            oravue.T_RIP&yr.C as main

		inner join orauser.FC1_1 as fc1_1
		on 
			main.NIR_ANO_17 = fc1_1.BEN_NIR_PSA

        inner join 
            oravue.T_RIP&yr.RSA as for_dx
        on 
            main.ETA_NUM_EPMSI = for_dx.ETA_NUM_EPMSI AND main.RIP_NUM = for_dx.RIP_NUM
        left join 
            oraval.MS_CIM_V as which_cim
        on 
            for_dx.DGN_PAL = which_cim.CIM_COD
        where 
            for_dx.ETA_NUM_EPMSI not in (
                '130780521', '130783236', '130783293', '130784234', '130804297', '600100101', '750041543',
                '750100018', '750100042', '750100075', '750100083', '750100091', '750100109', '750100125', 
                '750100166', '750100208', '750100216', '750100232', '750100273', '750100299', '750801441', 
                '750803447', '750803454', '910100015', '910100023', '920100013', '920100021', '920100039', 
                '920100047', '920100054', '920100062', '930100011', '930100037', '930100045', '940100027', 
                '940100035', '940100043', '940100050', '940100068', '950100016', '690783154', '690784137', 
                '690784152', '690784178', '690787478', '830100558'
            )

            /* Dynamic filters applied based on column existence */
            %if %eval(&year >= 14) %then %do;
                and main.COH_NAI_RET = '0'
                and main.COH_SEX_RET = '0'
            %end;

            %if %eval(&year >= 15) %then %do;
                and for_dx.TYP_GEN_RSA = '0'
            %end;

            %if %eval(&year >= 20) %then %do;
                and main.SEQ_IND <> 'E'
            %end;

            and for_dx.ENT_MOD <> '0' 
            and for_dx.SOR_MOD <> '0' 
            and main.NIR_ANO_17 not in ('xxxxxxxxxxxxxxxxx', 'BXXXXXXXXXXXXXXXX') 
            and main.NIR_RET = '0' 
            and main.NAI_RET = '0' 
            and main.SEX_RET = '0' 
            and main.SEJ_RET = '0' 
            and main.FHO_RET = '0'  
            and main.PMS_RET = '0' 
            and main.DAT_RET = '0';

			quit;

	   /* 3. Append current year to the master dataset */
       proc append base=work.rip_extract_all data=work.rip_extract_tmp force;
       run;

    %end;

%mend extract_PMSI;
%extract_PMSI(start=09, stop=19);


/* ==============================================================================
   STEP 4: SELECT MCO VAR IN THESE INDIVIDUALS
   ============================================================================== */
%macro extract_PMSI(start=06, stop=19);

/* 1. Clear/initialize the cumulative output table */
   proc sql;
      create table work.mco_extract_all like work.mco_extract_tmp; /* or empty shell */
   quit;

   	%do year = &start %to &stop;

        %let yr = %sysfunc(putn(&year., z2.));

		proc sql;
        
        create table work.mco_extract_tmp as 
        select 
            'MCO' as source_db,
            main.NIR_ANO_17, 
            main.EXE_SOI_DTD, 
            main.EXE_SOI_DTF, 
            for_dx.DGN_PAL,
            for_dx.AGE_ANN,
			 which_cim.CIM_LIL
        from 
            oravue.T_MCO&yr.C as main

		inner join orauser.FC1_1 as fc1_1
		on 
			main.NIR_ANO_17 = fc1_1.BEN_NIR_PSA

        inner join 
            oravue.T_MCO&yr.B as for_dx
        
		on 
            main.ETA_NUM = for_dx.ETA_NUM AND main.RSA_NUM = for_dx.RSA_NUM

		left join 
            oraval.MS_CIM_V as which_cim
        on 
            for_dx.DGN_PAL = which_cim.CIM_COD

        where 
            for_dx.ETA_NUM not in ('130780521', '130783236', '130783293', '130784234', '130804297','600100101', '750041543',
'750100018', '750100042', '750100075', '750100083', '750100091', '750100109', '750100125', '750100166', '750100208', 
'750100216', '750100232', '750100273', '750100299' , '750801441', '750803447', '750803454', '910100015', '910100023', 
'920100013', '920100021', '920100039', '920100047', '920100054', '920100062', '930100011', '930100037', '930100045', 
'940100027', '940100035', '940100043', '940100050', '940100068', '950100016', '690783154', '690784137', '690784152', 
'690784178', '690787478', '830100558')
            and for_dx.GRG_GHM NOT LIKE '90%' 
            and for_dx.ENT_MOD <> '0' 
            and for_dx.SOR_MOD <> '0'
            and main.NIR_ANO_17 not in ('xxxxxxxxxxxxxxxxx', 'BXXXXXXXXXXXXXXXX') 
            and main.NIR_RET = '0' 
            and main.NAI_RET = '0' 
            and main.SEX_RET = '0' 
            and main.SEJ_RET = '0' 
            and main.FHO_RET = '0'  
            and main.PMS_RET = '0' 
            and main.DAT_RET = '0';


			quit;

	   /* 3. Append current year to the master dataset */
       proc append base=work.mco_extract_all data=work.mco_extract_tmp force;
       run;

    %end;

%mend extract_PMSI;
%extract_PMSI(start=06, stop=19);


/* ==============================================================================
   STEP 5: SELECT SSR VAR IN THESE INDIVIDUALS
   ============================================================================== */
%macro extract_PMSI(start=06, stop=19);

/* 1. Clear/initialize the cumulative output table */
   proc sql;
      create table work.ssr_extract_all like work.ssr_extract_tmp; /* or empty shell */
   quit;

   	%do year = &start %to &stop;

        %let yr = %sysfunc(putn(&year., z2.));

		proc sql;
        
        create table work.ssr_extract_tmp as 
        select 
            'SSR' as source_db,
            main.NIR_ANO_17, 
            main.EXE_SOI_DTD, 
            main.EXE_SOI_DTF, 
            for_dx.DGN_PAL,
            for_dx.AGE_ANN,
			 which_cim.CIM_LIL
        from 
            oravue.T_SSR&yr.C as main

		inner join orauser.FC1_1 as fc1_1
		on 
			main.NIR_ANO_17 = fc1_1.BEN_NIR_PSA

        inner join 
            oravue.T_SSR&yr.B as for_dx
        
		on 
            main.ETA_NUM = for_dx.ETA_NUM AND main.RHA_NUM = for_dx.RHA_NUM

		left join 
            oraval.MS_CIM_V as which_cim
        on 
            for_dx.DGN_PAL = which_cim.CIM_COD

        where 
			for_dx.ETA_NUM not in ('130780521', '130783236', '130783293', '130784234', '130804297','600100101', '750041543',
'750100018', '750100042', '750100075', '750100083', '750100091', '750100109', '750100125', '750100166', '750100208', 
'750100216', '750100232', '750100273', '750100299' , '750801441', '750803447', '750803454', '910100015', '910100023', 
'920100013', '920100021', '920100039', '920100047', '920100054', '920100062', '930100011', '930100037', '930100045', 
'940100027', '940100035', '940100043', '940100050', '940100068', '950100016', '690783154', '690784137', '690784152', 
'690784178', '690787478', '830100558')
            and for_dx.ENT_MOD <> '0' 
            and for_dx.SOR_MOD <> '0'
            and main.NIR_ANO_17 not in ('xxxxxxxxxxxxxxxxx', 'BXXXXXXXXXXXXXXXX') 
            and main.NIR_RET = '0' 
            and main.NAI_RET = '0' 
            and main.SEX_RET = '0' 
            and main.SEJ_RET = '0' 
            and main.FHO_RET = '0'  
            and main.PMS_RET = '0' 
            and main.DAT_RET = '0';


			quit;

	   /* 3. Append current year to the master dataset */
       proc append base=work.ssr_extract_all data=work.ssr_extract_tmp force;
       run;

    %end;

%mend extract_PMSI;
%extract_PMSI(start=06, stop=19);

* ==============================================================================
   STEP 6: SELECT HAD VAR IN THESE INDIVIDUALS
   ============================================================================== */

%macro extract_PMSI(start=06, stop=19);

/* 1. Clear/initialize the cumulative output table */
   proc sql;
      create table work.had_extract_all like work.had_extract_tmp; /* or empty shell */
   quit;

   	%do year = &start %to &stop;

        %let yr = %sysfunc(putn(&year., z2.));

		proc sql;
        
        create table work.had_extract_tmp as 
        select 
            'HAD' as source_db,
            main.NIR_ANO_17, 
            main.EXE_SOI_DTD, 
            main.EXE_SOI_DTF, 
            for_dx.DGN_PAL,
            for_dx.AGE_ANN,
			 which_cim.CIM_LIL
        from 
            oravue.T_SSR&yr.C as main

		inner join orauser.FC1_1 as fc1_1
		on 
			main.NIR_ANO_17 = fc1_1.BEN_NIR_PSA

        inner join 
            oravue.T_HAD&yr.B as for_dx
        
		on 
            main.ETA_NUM_EPMSI = for_dx.ETA_NUM_EPMSI AND main.RHAD_NUM = for_dx.RHAD_NUM
		left join 
            oraval.MS_CIM_V as which_cim
        on 
            for_dx.DGN_PAL = which_cim.CIM_COD

        where 
			for_dx.ETA_NUM not in ('130780521', '130783236', '130783293', '130784234', '130804297','600100101', '750041543',
'750100018', '750100042', '750100075', '750100083', '750100091', '750100109', '750100125', '750100166', '750100208', 
'750100216', '750100232', '750100273', '750100299' , '750801441', '750803447', '750803454', '910100015', '910100023', 
'920100013', '920100021', '920100039', '920100047', '920100054', '920100062', '930100011', '930100037', '930100045', 
'940100027', '940100035', '940100043', '940100050', '940100068', '950100016', '690783154', '690784137', '690784152', 
'690784178', '690787478', '830100558')
            and for_dx.ENT_MOD <> '0' 
            and for_dx.SOR_MOD <> '0'
            and main.NIR_ANO_17 not in ('xxxxxxxxxxxxxxxxx', 'BXXXXXXXXXXXXXXXX') 
            and main.NIR_RET = '0' 
            and main.NAI_RET = '0' 
            and main.SEX_RET = '0' 
            and main.SEJ_RET = '0' 
            and main.FHO_RET = '0'  
            and main.PMS_RET = '0' 
            and main.DAT_RET = '0';


			quit;

	   /* 3. Append current year to the master dataset */
       proc append base=work.had_extract_all data=work.had_extract_tmp force;
       run;

    %end;

%mend extract_PMSI;
%extract_PMSI(start=06, stop=19);
