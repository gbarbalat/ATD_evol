/* append meds to FC4 */
proc sql;
   create table work.FC4_meds as
   select a.*,
          b.dt_first_ad_dt
   from sasdata1.fc1_2_with_totals as a
   inner join sasdata1.FC4 as b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO;
quit;

/* append admission data */
/* 1. Extract unique benchmark IDs from FC4 into a indexed table */
proc sql;
   create table work.fc4_ids as
   select distinct BEN_IDT_ANO
   from sasdata1.FC4;
quit;

/* 2. Process & Deduplicate FC1_3 */
proc sql;
   create table work.fc1_3_clean as
   select distinct 
          BEN_IDT_ANO, source_db, NIR_ANO_17, EXE_SOI_DTD, EXE_SOI_DTF, 
          DGN_PAL, AGE_ANN, CIM_LIL, FOR_ACT, DEL_DAT, PRE_JOU_NBJ, PRE_DEM_JOU_NBJ
   from sasdata1.FC1_3
   where BEN_IDT_ANO in (select BEN_IDT_ANO from work.fc4_ids);
quit;

/* 3. Process & Deduplicate FC1_4 */
proc sql;
   create table work.fc1_4_clean as
   select distinct 
          BEN_IDT_ANO, source_db, NIR_ANO_17, EXE_SOI_DTD, EXE_SOI_DTF, 
          DGN_PAL, AGE_ANN, CIM_LIL
   from sasdata1.FC1_4
   where BEN_IDT_ANO in (select BEN_IDT_ANO from work.fc4_ids);
quit;

/* 4. Process & Deduplicate FC1_5 (Rename ASS_DGN_1 to DGN_PAL) */
proc sql;
   create table work.fc1_5_clean as
   select distinct 
          BEN_IDT_ANO, source_db, NIR_ANO_17, EXE_SOI_DTD, EXE_SOI_DTF, 
          ASS_DGN_1 as DGN_PAL, AGE_ANN, CIM_LIL
   from sasdata1.FC1_5
   where BEN_IDT_ANO in (select BEN_IDT_ANO from work.fc4_ids);
quit;

/* 5. Process & Deduplicate FC1_6 */
proc sql;
   create table work.fc1_6_clean as
   select distinct 
          BEN_IDT_ANO, source_db, NIR_ANO_17, EXE_SOI_DTD, EXE_SOI_DTF, 
          DGN_PAL, AGE_ANN, CIM_LIL
   from sasdata1.FC1_6
   where BEN_IDT_ANO in (select BEN_IDT_ANO from work.fc4_ids);
quit;

/* 6. Concatenate Admission and FC4_meds, preserving all unique columns */
data work.FC4_concatenated;
   set work.fc1_3_clean
       work.fc1_4_clean
       work.fc1_5_clean
       work.fc1_6_clean
       work.FC4_meds;
run;

/* 7. Sort final dataset */
/* Ensure starting datetime cutoff macro variable is defined */
%let start     = 01JAN2015:00:00:00;
%let exe_start = %sysfunc(inputn(&start, datetime20.));

/* 7.1. Filter out pre-2015 rows, coalesce age, and drop unwanted columns */
data sasdata1.merged_big;
   set work.FC4_concatenated;   
   
   /* Combine AGE_ANN and BEN_AMA_COD if needed into a single AGE_ANN column */
   AGE_ANN = coalesce(AGE_ANN, BEN_AMA_COD);
   
   /* Drop specified columns */
   drop NIR_ANO_17 PHA_PRS_C13 BEN_AMA_COD BEN_NIR_PSA BEN_RNG_GEM 
		PRE_PRE_DTD CIM_LIL;
run;

/* 7.2. baseline merged_ */
data sasdata1.merged_;
   set sasdata1.merged_big;
   
   /* Keep rows on or after 01/01/2015 */
   where EXE_SOI_DTD >= first_ad;/*&exe_start.;*/

   /* Drop specified columns */
   drop PRS_GRS_DTD PHA_FRM_LIB PHA_SUB_DOS PHA_UPC_NBR PSP_ACT_NAT
		PSP_SPE_COD PSP_ACT_NAT BEN_RES_DPT BEN_RES_COM MAX_TRT_DTD
		PHA_ACT_QSN total_PHA_ACT_QSN;
run;
