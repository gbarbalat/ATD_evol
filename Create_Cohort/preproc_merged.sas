/* 1. Macro Variable Setup */
%let start     = 01JAN2015:00:00:00;
%let exe_start = %sysfunc(inputn(&start, datetime20.));

/* 2. Link Meds to FC4 Cohort */
proc sql;
   create table work.FC4_meds as
   select a.*,
          b.dt_first_ad_dt
   from sasdata1.fc1_2_with_totals as a
   inner join sasdata1.FC4 as b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO;

/* 3. Unique Patient Key Table */
   create table work.fc4_ids as
   select distinct BEN_IDT_ANO
   from sasdata1.FC4;

/* 4. Extract and Clean Diagnostic Sources */
   create table work.fc1_3_clean as
   select distinct BEN_IDT_ANO, source_db, NIR_ANO_17, EXE_SOI_DTD, EXE_SOI_DTF, 
                   DGN_PAL, AGE_ANN, CIM_LIL, FOR_ACT, DEL_DAT, PRE_JOU_NBJ, PRE_DEM_JOU_NBJ
   from sasdata1.FC1_3
   where BEN_IDT_ANO in (select BEN_IDT_ANO from work.fc4_ids);

   create table work.fc1_4_clean as
   select distinct BEN_IDT_ANO, source_db, NIR_ANO_17, EXE_SOI_DTD, EXE_SOI_DTF, 
                   DGN_PAL, AGE_ANN, CIM_LIL
   from sasdata1.FC1_4
   where BEN_IDT_ANO in (select BEN_IDT_ANO from work.fc4_ids);

   create table work.fc1_5_clean as
   select distinct BEN_IDT_ANO, source_db, NIR_ANO_17, EXE_SOI_DTD, EXE_SOI_DTF, 
                   ASS_DGN_1 as DGN_PAL, AGE_ANN, CIM_LIL
   from sasdata1.FC1_5
   where BEN_IDT_ANO in (select BEN_IDT_ANO from work.fc4_ids);

   create table work.fc1_6_clean as
   select distinct BEN_IDT_ANO, source_db, NIR_ANO_17, EXE_SOI_DTD, EXE_SOI_DTF, 
                   DGN_PAL, AGE_ANN, CIM_LIL
   from sasdata1.FC1_6
   where BEN_IDT_ANO in (select BEN_IDT_ANO from work.fc4_ids);
quit;

/* 5. Concatenate All Input Sources */
data work.FC4_concatenated;
   set work.fc1_3_clean
       work.fc1_4_clean
       work.fc1_5_clean
       work.fc1_6_clean
       work.FC4_meds;
run;

/* 6. Base Prep: Column Cleanup & Coalesce Age */
data sasdata1.merged_big;
   set work.FC4_concatenated;
   AGE_ANN = coalesce(AGE_ANN, BEN_AMA_COD);
   drop NIR_ANO_17 PHA_PRS_C13 BEN_AMA_COD BEN_NIR_PSA BEN_RNG_GEM PRE_PRE_DTD CIM_LIL;
run;

/* 7. Baseline Index Date Filter */
proc sql;
   create table work.merged_index_filtered(drop=PRS_GRS_DTD PHA_FRM_LIB PHA_SUB_DOS 
                                                 PHA_UPC_NBR PSP_ACT_NAT PSP_SPE_COD 
                                                 BEN_RES_DPT BEN_RES_COM 
                                                 PHA_ACT_QSN ) as
   select *
   from sasdata1.merged_big
   group by BEN_IDT_ANO
   having EXE_SOI_DTD >= min(dt_first_ad_dt);
quit;

/* 8. Single Combined DATA Step: Calculate LOS, Fix Datetimes, Apply Filters */
data sasdata1.merged_;
   set work.merged_index_filtered;

   /* 8.1. Filter non-01 FOR_ACT in RIP */
   if upcase(source_db) = 'RIP' and FOR_ACT ne '01' then delete;

   /* 8.2. Length of Stay (LOS) Logic */
   if source_db in ('MCO', 'SSR', 'HAD') then do;
      LOS = datepart(EXE_SOI_DTF) - datepart(EXE_SOI_DTD);
   end;
   else if source_db = 'RIP' then do;
      LOS = PRE_JOU_NBJ;
      /* Fixed Missing Semicolon Here */
      EXE_SOI_DTD = EXE_SOI_DTD + (DEL_DAT * 86400);
      EXE_SOI_DTF = EXE_SOI_DTD + (LOS * 86400);
      format EXE_SOI_DTD DATETIME20. EXE_SOI_DTF DATETIME20.;
   end;

   /* 8.3. Filter Stays Less Than 30 Days (Preserves Outpatient Records) */
   if not missing(LOS) and LOS < 30 then delete;

   drop DEL_DAT PRE_JOU_NBJ PRE_DEM_JOU_NBJ;
run;

/* 9. Final Deduplication and Sorting */
proc sort data=sasdata1.merged_ out=sasdata1.merged_ noduprecs;
   by BEN_IDT_ANO EXE_SOI_DTD;
run;
