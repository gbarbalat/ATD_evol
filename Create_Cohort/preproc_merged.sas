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
%let start     = 01JAN2015:00:00:00;
%let exe_start = %sysfunc(inputn(&start, datetime20.));

data work.FC4_filtered;
   set work.FC4_concatenated;
   
   /* 1. Date Filter: Keep rows on or after 01/01/2015 */
   where EXE_SOI_DTD >= &exe_start.;
   
   /* 2. Coalesce Age Columns */
   AGE_ANN = coalesce(AGE_ANN, BEN_AMA_COD);
   
   /* 3. Transform BEN_RES_DPT */
   /* Standardize to character string (padded with leading zeroes up to 3 chars) */
   length _dpt $3 _com $3 BEN_RES_GEO $5;
   _dpt = put(BEN_RES_DPT, $3.);
   _com = put(BEN_RES_COM, $3.);
   
   /* Ensure BEN_RES_DPT starts with 0 */
   if substr(_dpt, 1, 1) ne '0' then _dpt = '0' || substr(_dpt, 1, 2);
   
   /* If 2nd char is 9, ensure 3rd char is restricted to 0-5 (Overseas DOM rules) */
   if substr(_dpt, 2, 1) = '9' and substr(_dpt, 3, 1) not in ('0', '1', '2', '3', '4', '5') then do;
      /* Adjust or flag as needed according to protocol */
      substr(_dpt, 3, 1) = '0'; 
   end;

   /* 4. Build BEN_RES_GEO */
   /* Standardize BEN_RES_COM (pad left with '0' if only 2 characters long) */
   if length(strip(_com)) = 2 then _com = '0' || strip(_com);
   
   /* Concatenate last 2 chars of BEN_RES_DPT + 3 chars of BEN_RES_COM */
   BEN_RES_GEO = substr(_dpt, 2, 2) || _com;

   /* 5. Drop unwanted variables (including BEN_RES_DPT and BEN_RES_COM) */
   drop NIR_ANO_17 PHA_PRS_C13 BEN_AMA_COD BEN_RES_DPT BEN_RES_COM _dpt _com;
run;

/* Sort final merged output */
proc sort data=work.FC4_filtered out=sasdata1.merged_;
   by BEN_IDT_ANO EXE_SOI_DTD;
run;
