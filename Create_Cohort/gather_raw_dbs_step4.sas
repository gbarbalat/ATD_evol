
/* ==============================================================================
   STEP 4: SELECT MCO VAR IN THESE INDIVIDUALS
   ============================================================================== */
%macro extract_MCO(start=06, stop=19);

   /* 1. Reset master output table */
   proc datasets lib=work nolist;
      delete mco_extract_all mco_extract_tmp;
   quit;

   %do year = &start %to &stop;
       %let yr = %sysfunc(putn(&year., z2.));

       /* ------------------------------------------------------------------ */
       /* CHECK 1: Ensure both tables exist in ORAVUE                        */
       /* ------------------------------------------------------------------ */
       proc sql noprint;
          select count(*) into :tbl_count
          from dictionary.tables
          where libname = 'ORAVUE' 
            and memname in ("T_MCO&yr.C", "T_MCO&yr.B");
       quit;

       %if &tbl_count. < 2 %then %do;
          %put WARNING: Tables for MCO year &yr do not exist in ORAVUE. Skipping.;
          %goto next_mco_year;
       %end;

       /* ------------------------------------------------------------------ */
       /* CHECK 2: Strict mandatory key columns                              */
       /* ------------------------------------------------------------------ */
       proc sql noprint;
          select count(distinct name) into :c_col_cnt
          from dictionary.columns
          where libname = 'ORAVUE' 
            and memname = "T_MCO&yr.C"
            and upcase(name) in ('NIR_ANO_17', 'EXE_SOI_DTD', 'EXE_SOI_DTF', 'ETA_NUM', 'RSA_NUM');

          select count(distinct name) into :b_col_cnt
          from dictionary.columns
          where libname = 'ORAVUE' 
            and memname = "T_MCO&yr.B"
            and upcase(name) in ('ETA_NUM', 'RSA_NUM', 'AGE_ANN');
       quit;

       %if &c_col_cnt. < 5 or &b_col_cnt. < 3 %then %do;
          %put WARNING: Mandatory key columns missing in T_MCO&yr for year &yr. Skipping.;
          %goto next_mco_year;
       %end;

       /* ------------------------------------------------------------------ */
       /* CHECK 3: Optional columns and status flags                         */
       /* ------------------------------------------------------------------ */
       proc sql noprint;
          /* Dual-variable handling for DGN_PAL (Select vs Join) */
          select case when count(*) > 0 then "for_dx.DGN_PAL" else "'' as DGN_PAL length=10" end into :f_dgn_pal_select from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.B" and upcase(name)='DGN_PAL';
          select case when count(*) > 0 then "for_dx.DGN_PAL" else "''" end into :f_dgn_pal_join from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.B" and upcase(name)='DGN_PAL';

          /* Where clause boolean flag checks */
          select case when count(*) > 0 then "main.NIR_RET = '0'" else "'0' = '0'" end into :f_nir_ret from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.C" and upcase(name)='NIR_RET';
          select case when count(*) > 0 then "main.NAI_RET = '0'" else "'0' = '0'" end into :f_nai_ret from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.C" and upcase(name)='NAI_RET';
          select case when count(*) > 0 then "main.SEX_RET = '0'" else "'0' = '0'" end into :f_sex_ret from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.C" and upcase(name)='SEX_RET';
          select case when count(*) > 0 then "main.SEJ_RET = '0'" else "'0' = '0'" end into :f_sej_ret from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.C" and upcase(name)='SEJ_RET';
          select case when count(*) > 0 then "main.FHO_RET = '0'" else "'0' = '0'" end into :f_fho_ret from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.C" and upcase(name)='FHO_RET';
          select case when count(*) > 0 then "main.PMS_RET = '0'" else "'0' = '0'" end into :f_pms_ret from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.C" and upcase(name)='PMS_RET';
          select case when count(*) > 0 then "main.DAT_RET = '0'" else "'0' = '0'" end into :f_dat_ret from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.C" and upcase(name)='DAT_RET';
          
          select case when count(*) > 0 then "for_dx.GRG_GHM NOT LIKE '90%'" else "'0' = '0'" end into :f_grg_ghm from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.B" and upcase(name)='GRG_GHM';
          select case when count(*) > 0 then "for_dx.ENT_MOD <> '0'" else "'0' <> '0'" end into :f_ent_mod from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.B" and upcase(name)='ENT_MOD';
          select case when count(*) > 0 then "for_dx.SOR_MOD <> '0'" else "'0' <> '0'" end into :f_sor_mod from dictionary.columns where libname='ORAVUE' and memname="T_MCO&yr.B" and upcase(name)='SOR_MOD';
       quit;

       /* ------------------------------------------------------------------ */
       /* EXECUTION                                                          */
       /* ------------------------------------------------------------------ */
       proc sql;
          create table work.mco_extract_tmp as 
          select 
             fc1_1.BEN_IDT_ANO,
             'MCO' as source_db length=3,
             main.NIR_ANO_17, 
             main.EXE_SOI_DTD, 
             main.EXE_SOI_DTF, 
             &f_dgn_pal_select.,
			 which_cim.CIM_LIL,
             for_dx.AGE_ANN
 
          from oravue.T_MCO&yr.C as main

          inner join orauser.FC1_1 as fc1_1
             on main.NIR_ANO_17 = fc1_1.BEN_NIR_PSA

          inner join oravue.T_MCO&yr.B as for_dx
             on main.ETA_NUM = for_dx.ETA_NUM 
            and main.RSA_NUM = for_dx.RSA_NUM
          left join oraval.MS_CIM_V as which_cim
             on &f_dgn_pal_join. = which_cim.CIM_COD

          where for_dx.ETA_NUM not in (
                   '130780521', '130783236', '130783293', '130784234', '130804297', '600100101', '750041543',
                   '750100018', '750100042', '750100075', '750100083', '750100091', '750100109', '750100125', 
                   '750100166', '750100208', '750100216', '750100232', '750100273', '750100299', '750801441', 
                   '750803447', '750803454', '910100015', '910100023', '920100013', '920100021', '920100039', 
                   '920100047', '920100054', '920100062', '930100011', '930100037', '930100045', '940100027', 
                   '940100035', '940100043', '940100050', '940100068', '950100016', '690783154', '690784137', 
                   '690784152', '690784178', '690787478', '830100558'
                )
            and &f_grg_ghm.
            and &f_ent_mod.
            and &f_sor_mod.
            and main.NIR_ANO_17 not in ('xxxxxxxxxxxxxxxxx', 'BXXXXXXXXXXXXXXXX')
            and &f_nir_ret.
            and &f_nai_ret.
            and &f_sex_ret.
            and &f_sej_ret.
            and &f_fho_ret.
            and &f_pms_ret.
            and &f_dat_ret.;
       quit;

       proc append base=work.mco_extract_all data=work.mco_extract_tmp force;
       run;

       %next_mco_year:

   %end;

   proc datasets lib=work nolist;
      delete mco_extract_tmp;
   quit;

%mend extract_MCO;

/* Execution 
%extract_MCO(start=18, stop=19);*/
%extract_MCO(start=06, stop=19);

/* to sasdata1 */
proc sql;
   create table sasdata1.fc1_4 as
   select *
   from work.mco_extract_all;
quit;
