/* Remove duplicate rows based on patient, date, and drug label */
proc sort data=work.prs_ald_orc_hosp_crto_before nodupkey out=work.cv_before;
   by BEN_IDT_ANO EXE_SOI_DTD PHA_ATC_LIB;
run;

data work.cv_before;
   set work.cv_before;
   BEN_DCD_DTE=datepart(BEN_DCD_DTE);
   MAX_TRT_DTD=datepart(MAX_TRT_DTD);
   format BEN_DCD_DTE MAX_TRT_DTD date9.;
run;


proc sort data=work.prs_ald_orc_hosp_geo_presc_after nodupkey out=work.cv_after;
   by BEN_IDT_ANO EXE_SOI_DTD PHA_ATC_LIB;
run;

/* give BEN_DCD_DTE and MAX_TRT_DTD to cv_after by BEN_IDT_ANO */
/* Create a unique patient-level reference table */
proc sql;
   create table work.unique_patient_dates as
   select distinct 
      BEN_IDT_ANO, 
      BEN_DCD_DTE, 
      MAX_TRT_DTD
   from work.cv_before
   group by BEN_IDT_ANO;
quit;

/* Safely left join without duplicating rows */
proc sql;
   create table work.cv_after as
   select 
      a.*,
      b.BEN_DCD_DTE,
      b.MAX_TRT_DTD
   from work.cv_after as a
   left join work.unique_patient_dates as b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO;
quit;
data work.cv_after;
   set work.cv_after;
   format BEN_DCD_DTE MAX_TRT_DTD date9.;
run;

/* Aggregate PHA_ATC_LIB into comma-separated psy_meds and transform dates */
/* also add an event column where for each BEN_IDT_ANO and EXE_SOI_DTD,
the value takes SSRI if the values of PHA_ATC_CLA all start with N06AB; 
ATD_OTH if the values start by N06A but do not include N06AB; 
SWI_CLA if any of the values of PHA_ATC_CLA does not start by N06A; 
DEATH  if  next_exe_date = BEN_DCD_DTE; 
CENS if next_exe_date=MAX_TRT_DTD*/
data work.cv_events_after;
   length psy_meds $ 500 event $ 15;
   
   /* First pass: Concatenate PHA_ATC_LIB and evaluate ATC classification flags per group */
   do while(1);
      set work.cv_after;
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
      set work.cv_after;
      by BEN_IDT_ANO EXE_SOI_DTD;
      
      /* Transform dates into relative time (in days) from dt_first_ad */
      start = intck('day', dt_first_ad, EXE_SOI_DTD);
      stop  = intck('day', dt_first_ad, next_exe_date);
      
      /* Event classification logic */
      if next_exe_date = BEN_DCD_DTE then event = 'DEATH';
      else if next_exe_date = MAX_TRT_DTD then event = 'CENS';
      if all_n06ab = 1 then event = 'SSRI';
      else if all_n06a = 1 and all_n06ab = 0 then event = 'ATD_OTH';
      else event = 'SWI_CLA';
      
      output;
      if last.EXE_SOI_DTD then leave;
   end;
run;

proc sort data=work.cv_events_after nodupkey out=work.cv_events_after;
   by BEN_IDT_ANO EXE_SOI_DTD psy_meds;
run;

/* now create from work.cv_events_after where for each BEN_IDT_ANO, 
each time it encounters event = "SWI_CLA", it removes all rows past that line. */
/* 1. Ensure data is ordered chronologically per patient */
proc sort data=work.cv_events_after;
   by BEN_IDT_ANO start;
run;

/* 2. Truncate follow-up after the SWI_CLA event */
data work.cv_events_rd_after;
   set work.cv_events_after;
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


/* now merge cv_after and cv_events_rd_after */
/* 1. Dynamically find columns in cv_before that are NOT in cv_events_rd_after */
proc sql noprint;
   select distinct upcase(a.name) into :cols_to_pull separated by ', b.'
   from dictionary.columns as a
   where a.libname = 'WORK' and a.memname = 'CV_BEFORE'
     and upcase(a.name) not in (
        select upcase(b.name) 
        from dictionary.columns as b 
        where b.libname = 'WORK' and b.memname = 'CV_EVENTS_RD_AFTER'
     )
     and upcase(a.name) ne 'BEN_IDT_ANO'; /* Exclude the join key itself */
quit;

/* Verify what columns will be added */
%put Columns to bring over: &cols_to_pull.;

/* 2. Deduplicate cv_before to 1 unique row per patient */
proc sort data=work.cv_before nodupkey out=work.cv_before_unique;
   by BEN_IDT_ANO;
run;

/* 3. Left join cv_events_rd_after with only the missing columns */
proc sql;
   create table work.merged_ as
   select 
      a.*
      /* Conditionally append only the non-overlapping columns if any exist */
      %if &cols_to_pull ne %str() %then %do;
         , b.&cols_to_pull.
      %end;
   from work.cv_events_rd_after as a
   left join work.cv_before_unique as b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO;
quit;
