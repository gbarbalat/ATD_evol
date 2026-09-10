%macro extract_RIP(start=06, stop=19);

   /* 1. Reset master output table */
   proc datasets lib=work nolist;
      delete rip_extract_all rip_extract_tmp;
   quit;

   %do year = &start %to &stop;
       %let yr = %sysfunc(putn(&year., z2.));

       /* ------------------------------------------------------------------ */
       /* CHECK 1: Ensure both tables exist in ORAVUE                        */
       /* ------------------------------------------------------------------ */
       proc sql noprint;
          select count(*) into :tbl_count trimmed
          from dictionary.tables
          where libname = 'ORAVUE' 
            and memname in ("T_RIP&yr.C", "T_RIP&yr.RSA");
       quit;

       %if &tbl_count. < 2 %then %do;
          %put WARNING: Tables for RIP year &yr do not exist in ORAVUE. Skipping.;
          %goto next_rip_year;
       %end;

       /* ------------------------------------------------------------------ */
       /* CHECK 2: Strict mandatory key columns                              */
       /* ------------------------------------------------------------------ */
       proc sql noprint;
          select count(distinct name) into :c_col_cnt trimmed
          from dictionary.columns
          where libname = 'ORAVUE' 
            and memname = "T_RIP&yr.C"
            and upcase(name) in ('NIR_ANO_17', 'EXE_SOI_DTD', 'EXE_SOI_DTF', 'ETA_NUM_EPMSI', 'RIP_NUM');

          select count(distinct name) into :b_col_cnt trimmed
          from dictionary.columns
          where libname = 'ORAVUE' 
            and memname = "T_RIP&yr.RSA"
            and upcase(name) in ('ETA_NUM_EPMSI', 'RIP_NUM', 'AGE_ANN');
       quit;

       %if &c_col_cnt. < 5 or &b_col_cnt. < 3 %then %do;
          %put WARNING: Mandatory key columns missing in T_RIP&yr for year &yr. Skipping.;
          %goto next_rip_year;
       %end;

       /* ------------------------------------------------------------------ */
       /* CHECK 3: Optional columns and status flags                         */
       /* ------------------------------------------------------------------ */
       proc sql noprint;
          /* SELECT clause dynamic mapping */
          select case when count(*) > 0 then "for_dx.DGN_PAL" else "'' as DGN_PAL length=10" end into :f_dgn_pal_select trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.RSA" and upcase(name)='DGN_PAL';
          select case when count(*) > 0 then "for_dx.DGN_PAL" else "''" end into :f_dgn_pal_join trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.RSA" and upcase(name)='DGN_PAL';
          
          select case when count(*) > 0 then "for_dx.FOR_ACT" else "'' as FOR_ACT length=10" end into :f_for_act trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.RSA" and upcase(name)='FOR_ACT';
          select case when count(*) > 0 then "main.COH_NAI_RET" else "'0' as COH_NAI_RET length=1" end into :f_coh_nai_ret_sel trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='COH_NAI_RET';
          select case when count(*) > 0 then "main.COH_SEX_RET" else "'0' as COH_SEX_RET length=1" end into :f_coh_sex_ret_sel trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='COH_SEX_RET';
          select case when count(*) > 0 then "for_dx.TYP_GEN_RSA" else "'0' as TYP_GEN_RSA length=1" end into :f_typ_gen_rsa_sel trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.RSA" and upcase(name)='TYP_GEN_RSA';
          select case when count(*) > 0 then "main.SEQ_IND" else "'' as SEQ_IND length=10" end into :f_seq_ind_sel trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='SEQ_IND';
          
          select case when count(*) > 0 then "for_dx.DEL_DAT" else ". as DEL_DAT" end into :f_del_dat trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.RSA" and upcase(name)='DEL_DAT';
          select case when count(*) > 0 then "for_dx.PRE_JOU_NBJ" else ". as PRE_JOU_NBJ" end into :f_pre_jou_nbj trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.RSA" and upcase(name)='PRE_JOU_NBJ';
          select case when count(*) > 0 then "for_dx.PRE_DEM_JOU_NBJ" else ". as PRE_DEM_JOU_NBJ" end into :f_pre_dem_jou_nbj trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.RSA" and upcase(name)='PRE_DEM_JOU_NBJ';

          /* WHERE clause boolean flag checks */
          select case when count(*) > 0 then "main.COH_NAI_RET = '0'" else "1=1" end into :f_coh_nai_ret_flg trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='COH_NAI_RET';
          select case when count(*) > 0 then "main.COH_SEX_RET = '0'" else "1=1" end into :f_coh_sex_ret_flg trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='COH_SEX_RET';
          select case when count(*) > 0 then "for_dx.TYP_GEN_RSA = '0'" else "1=1" end into :f_typ_gen_rsa_flg trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.RSA" and upcase(name)='TYP_GEN_RSA';
          select case when count(*) > 0 then "main.SEQ_IND <> 'E'" else "1=1" end into :f_seq_ind_flg trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='SEQ_IND';

          select case when count(*) > 0 then "main.NIR_RET = '0'" else "1=1" end into :f_nir_ret trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='NIR_RET';
          select case when count(*) > 0 then "main.NAI_RET = '0'" else "1=1" end into :f_nai_ret trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='NAI_RET';
          select case when count(*) > 0 then "main.SEX_RET = '0'" else "1=1" end into :f_sex_ret trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='SEX_RET';
          select case when count(*) > 0 then "main.SEJ_RET = '0'" else "1=1" end into :f_sej_ret trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='SEJ_RET';
          select case when count(*) > 0 then "main.FHO_RET = '0'" else "1=1" end into :f_fho_ret trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='FHO_RET';
          select case when count(*) > 0 then "main.PMS_RET = '0'" else "1=1" end into :f_pms_ret trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='PMS_RET';
          select case when count(*) > 0 then "main.DAT_RET = '0'" else "1=1" end into :f_dat_ret trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.C" and upcase(name)='DAT_RET';

          select case when count(*) > 0 then "for_dx.ENT_MOD <> '0'" else "1=1" end into :f_ent_mod trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.RSA" and upcase(name)='ENT_MOD';
          select case when count(*) > 0 then "for_dx.SOR_MOD <> '0'" else "1=1" end into :f_sor_mod trimmed from dictionary.columns where libname='ORAVUE' and memname="T_RIP&yr.RSA" and upcase(name)='SOR_MOD';
       quit;

       /* ------------------------------------------------------------------ */
       /* EXECUTION                                                          */
       /* ------------------------------------------------------------------ */
       proc sql;
          create table work.rip_extract_tmp as 
          select 
             fc1_1.BEN_IDT_ANO,
             'RIP' as source_db length=3,
             main.NIR_ANO_17, 
             main.EXE_SOI_DTD, 
             main.EXE_SOI_DTF, 
             &f_dgn_pal_select.,
             for_dx.AGE_ANN,
			 which_cim.CIM_LIL,
             &f_for_act.,
             /*&f_coh_nai_ret_sel.,*/
             /*&f_coh_sex_ret_sel.,*/
             /*&f_typ_gen_rsa_sel.,*/
             /*&f_seq_ind_sel.,*/
             &f_del_dat.,
             &f_pre_jou_nbj.,
             &f_pre_dem_jou_nbj.
             
          from oravue.T_RIP&yr.C as main

          inner join orauser.FC1_1 as fc1_1
             on main.NIR_ANO_17 = fc1_1.BEN_NIR_PSA

          inner join oravue.T_RIP&yr.RSA as for_dx
             on main.ETA_NUM_EPMSI = for_dx.ETA_NUM_EPMSI 
            and main.RIP_NUM       = for_dx.RIP_NUM

          left join oraval.MS_CIM_V as which_cim
             on &f_dgn_pal_join. = which_cim.CIM_COD

          where for_dx.ETA_NUM_EPMSI not in (
                   '130780521', '130783236', '130783293', '130784234', '130804297', '600100101', '750041543',
                   '750100018', '750100042', '750100075', '750100083', '750100091', '750100109', '750100125', 
                   '750100166', '750100208', '750100216', '750100232', '750100273', '750100299', '750801441', 
                   '750803447', '750803454', '910100015', '910100023', '920100013', '920100021', '920100039', 
                   '920100047', '920100054', '920100062', '930100011', '930100037', '930100045', '940100027', 
                   '940100035', '940100043', '940100050', '940100068', '950100016', '690783154', '690784137', 
                   '690784152', '690784178', '690787478', '830100558'
                )
            and &f_coh_nai_ret_flg.
            and &f_coh_sex_ret_flg.
            and &f_typ_gen_rsa_flg.
            and &f_seq_ind_flg.
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

       proc append base=work.rip_extract_all data=work.rip_extract_tmp force;
       run;

       %next_rip_year:

   %end;

   proc datasets lib=work nolist;
      delete rip_extract_tmp;
   quit;

%mend extract_RIP;
/* Execution 
%extract_RIP(start=09, stop=10);*/
%extract_RIP(start=06, stop=19);


/* to sasdata1 */
proc sql;
   create table sasdata1.fc1_3 as
   select *
   from work.rip_extract_all;
quit;
