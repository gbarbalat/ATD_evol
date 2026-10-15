/* 1. Remove duplicate rows based on patient, date, and drug label */
proc sort data=sasdata1.merged_include_other nodupkey out=work.merged_include_other_rd;
   by BEN_IDT_ANO EXE_SOI_DTD PHA_ATC_LIB;
run;

/* 2. Aggregate PHA_ATC_LIB into comma-separated psy_meds and transform dates */
/* also add an event column where for each BEN_IDT_ANO and EXE_SOI_DTD,
the value takes SSRI if the values of PHA_ATC_CLA all start with N06AB; 
ATD_OTH if the values start by N06A but do not include N06AB; 
SWI_CLA if any of the values of PHA_ATC_CLA does not start by N06A; 
DEATH  if  next_exe_date = datepart(BEN_DCD_DTE); 
CENS if next_exe_date=datepart(MAX_TRT_DTE) */
data work.merged_tmp;
   length psy_meds $ 500 event $ 15;
   
   /* First pass: Concatenate PHA_ATC_LIB and evaluate ATC classification flags per group */
   do while(1);
      set work.merged_include_other_rd;
      by BEN_IDT_ANO EXE_SOI_DTD;
      
      if first.EXE_SOI_DTD then do;
         psy_meds = PHA_ATC_LIB;
         all_n06ab = 1;
         all_n06a = 1;
         has_n06ab = 0;
      end;
      else do;
         psy_meds = catx(', ', psy_meds, PHA_ATC_LIB);
      end;
      
      /* Check prefix criteria for each row in the group */
      if substr(strip(PHA_ATC_CLA), 1, 5) = 'N06AB' then do;
         has_n06ab = 1;
      end;
      else if substr(strip(PHA_ATC_CLA), 1, 4) = 'N06A' then do;
         all_n06ab = 0;
      end;
      else do;
         all_n06ab = 0;
         all_n06a = 0;
      end;
      
      if last.EXE_SOI_DTD then leave;
   end;
   
   /* Second pass: Output rows, compute relative times, and assign the event type */
   do while(1);
      set work.merged_include_other_rd;
      by BEN_IDT_ANO EXE_SOI_DTD;
      
      /* Transform dates into relative time (in days) from dt_first_ad */
      start = intck('day', dt_first_ad, EXE_SOI_DTD);
      stop  = intck('day', dt_first_ad, next_exe_date);
      
      /* Event classification logic 
      if next_exe_date = datepart(BEN_DCD_DTE) then event = 'DEATH';
      else if next_exe_date = datepart(MAX_TRT_DTE) then event = 'CENS';*/
      if all_n06ab = 1 then event = 'SSRI';
      else if all_n06a = 1 and all_n06ab = 0 then event = 'ATD_OTH';
      else event = 'SWI_CLA';
      
      output;
      if last.EXE_SOI_DTD then leave;
   end;
run;

proc sort data=work.merged_tmp nodupkey out=work.merged_tmp2;
   by BEN_IDT_ANO EXE_SOI_DTD psy_meds;
run;

/* now create work.merged_tmp3 from work.merged_tmp2 where for each BEN_IDT_ANO, 
each time it encounters event = "SWI_CLA", it removes all rows past that line. */
/* 1. Ensure data is ordered chronologically per patient */
proc sort data=work.merged_tmp2;
   by BEN_IDT_ANO start;
run;

/* 2. Truncate follow-up after the SWI_CLA event */
data work.merged_tmp3;
   set work.merged_tmp2;
   by BEN_IDT_ANO;
   
   retain stop_patient;
   
   /* Reset the stop flag for each new patient */
   if first.BEN_IDT_ANO then stop_patient = 0;
   
   /* If a previous row triggered SWI_CLA, drop this and all subsequent rows */
   if stop_patient then delete;
   
   output;
   
   /* If the current row is SWI_CLA, flag to stop processing further rows for this patient */
   if event = 'SWI_CLA' then stop_patient = 1;
run;

