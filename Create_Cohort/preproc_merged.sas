/* 7. Sort final dataset */
/* Ensure starting datetime cutoff macro variable is defined */
%let start     = 01JAN2015:00:00:00;
%let exe_start = %sysfunc(inputn(&start, datetime20.));

/* 7.1. Filter out pre-2015 rows, coalesce age, and drop unwanted columns */
data work.FC4_filtered;
   set work.FC4_concatenated;
   
   /* Keep rows on or after 01/01/2015 */
   where EXE_SOI_DTD >= &exe_start.;
   
   /* Combine AGE_ANN and BEN_AMA_COD if needed into a single AGE_ANN column */
   AGE_ANN = coalesce(AGE_ANN, BEN_AMA_COD);
   
   /* Drop specified columns */
   drop NIR_ANO_17 PHA_PRS_C13 BEN_AMA_COD;
run;

/* 7.2. Sort final output dataset into sasdata1.merged_ */
proc sort data=work.FC4_filtered out=sasdata1.merged_;
   by BEN_IDT_ANO EXE_SOI_DTD;
run;
