/* can't do this on R as files are too heavy ...*/ 

/* =========================================================================
   Step 1: Clean dates where MAX_TRT_DTD or BEN_DCD_DTE precede DT_FIRST_AD
   ========================================================================= */
data work.merged_checks_recode;
    set sasdata1.merged_;
    format MAX_TRT_DTD BEN_DCD_DTE DT_FIRST_AD yymmdd10.;
    
    if MAX_TRT_DTD < DT_FIRST_AD then MAX_TRT_DTD = today();
    if BEN_DCD_DTE < DT_FIRST_AD then BEN_DCD_DTE = today();
run;

/* Sort data by patient and start time to prepare for sequential operations */
proc sort data=work.merged_checks_recode;
    by BEN_IDT_ANO start;
run;

/* =========================================================================
   Step 2: Update last row's next_exe_date and stop per patient
   ========================================================================= */
data work.merged_checks_recode2;
    set work.merged_checks_recode;
    by BEN_IDT_ANO;
    
    if last.BEN_IDT_ANO then do;
        /* Correct SAS syntax for finding the minimum across columns */
        next_exe_date = min(BEN_DCD_DTE, MAX_TRT_DTD, DT_FIRST_AD + 365);
        stop = next_exe_date - DT_FIRST_AD;
    end;
run;

/* =========================================================================
   Step 3: Shift event and psy_meds by 1 row and apply terminal conditions
   ========================================================================= */
/* =========================================================================
   Step 3: Emulate lead() in SAS using a row index and self-join, 
           then apply terminal conditions on the last row
   ========================================================================= */

/* 1. Ensure data is sorted and assign a sequential row number per patient */
proc sort data=work.merged_checks_recode2;
    by BEN_IDT_ANO start;
run;

data work.merged_checks_recode2_seq;
    set work.merged_checks_recode2;
    by BEN_IDT_ANO;
    retain row_num;
    if first.BEN_IDT_ANO then row_num = 1;
    else row_num + 1;
run;

/* 2. Self-join to pull the next row's event and psy_meds (emulating lead) */
proc sql;
    create table work.merged_checks_recode3_joined as
    select a.*, 
           b.event as l_event,
           b.psy_meds as l_psy_meds
    from work.merged_checks_recode2_seq a
    left join work.merged_checks_recode2_seq b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO and a.row_num + 1 = b.row_num;
quit;

/* 3. Apply the lead shifts and terminal conditions on the final row */
data work.merged_checks_recode3;
    set work.merged_checks_recode3_joined;
    by BEN_IDT_ANO;
    
    /* Shift values if a next row exists */
    if l_event ne '' then event = l_event;
    if l_psy_meds ne '' then psy_meds = l_psy_meds;
    
    /* Apply terminal conditions on the absolute last row per patient */
    if last.BEN_IDT_ANO then do;
        if stop >= 365 then do;
            event = "Cens";
            psy_meds = "Cens";
        end;
        else if next_exe_date = MAX_TRT_DTD then do;
            event = "Cens";
            psy_meds = "Cens";
        end;
        else if next_exe_date = BEN_DCD_DTE then do;
            event = "Death";
            psy_meds = "Death";
        end;
    end;
    
    drop row_num l_event l_psy_meds;
run;
/* =========================================================================
   Step 4: Generate 45-day intervals, merge, filter overlaps, and aggregate
   ========================================================================= */
/* =========================================================================
   Step 4: Generate 45-day intervals, merge, filter overlaps, and aggregate
   ========================================================================= */

/* 1. Find max stop and terminal event per patient (including max_stop) */
proc sql;
    create table work.patient_max as
    select BEN_IDT_ANO,
           max(stop) as max_stop
    from work.merged_checks_recode3
    group by BEN_IDT_ANO;
    
    create table work.patient_terminal as
    select a.BEN_IDT_ANO, 
           a.event as terminal_event, 
           b.max_stop
    from work.merged_checks_recode3 a
    inner join work.patient_max b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO and a.stop = b.max_stop;
quit;

/* 2. Generate 45-day interval blocks */
data work.intervals;
    set work.patient_max;
    if max_stop <= 0 then max_stop = 0;
    
    do int_start = 0 to max_stop - 1 by 45;
       int_stop = min(int_start + 45, max_stop);
       output;
    end;
run;

/* 3. Merge terminal event and max bounds back to the intervals */
proc sql;
    create table work.intervals_full as
    select a.*, 
           b.terminal_event, 
           b.max_stop as max_patient_stop
    from work.intervals a
    left join work.patient_terminal b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO;
quit;

/* 4. Join with original dataset and filter for overlapping windows, selecting all columns from b */
proc sql;
    create table work.overlapped as
    select a.*, 
           b.*, 
		   b.start as orig_start, 
           b.stop as orig_stop
    from work.intervals_full a
    inner join work.merged_checks_recode3 b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO
    where b.start < a.int_stop and b.stop > a.int_start;
quit;


/* =========================================================================
   Step 5: Final Aggregation (All variables + True Modes + Patient attributes)
   ========================================================================= */
/* 1. Pre-calculate the mode for season_year, region, and FDEP20_quint */
/* 1. Pre-calculate the mode for season_year, region, and FDEP20_quint with an explicit frequency name */
proc freq data=work.overlapped noprint;
    tables BEN_IDT_ANO * int_start * season_year / out=work.mode_season (rename=(count=freq) drop=percent);
    tables BEN_IDT_ANO * int_start * region / out=work.mode_region (rename=(count=freq) drop=percent);
    tables BEN_IDT_ANO * int_start * FDEP20_quint / out=work.mode_fdep (rename=(count=freq) drop=percent);
run;

/* Keep only the top frequency (mode) per patient-interval */
proc sort data=work.mode_season; by BEN_IDT_ANO int_start descending freq; run;
data work.mode_season_top; set work.mode_season; by BEN_IDT_ANO int_start; if first.int_start; keep BEN_IDT_ANO int_start season_year; run;

proc sort data=work.mode_region; by BEN_IDT_ANO int_start descending freq; run;
data work.mode_region_top; set work.mode_region; by BEN_IDT_ANO int_start; if first.int_start; keep BEN_IDT_ANO int_start region; run;

proc sort data=work.mode_fdep; by BEN_IDT_ANO int_start descending freq; run;
data work.mode_fdep_top; set work.mode_fdep; by BEN_IDT_ANO int_start; if first.int_start; keep BEN_IDT_ANO int_start FDEP20_quint; run;

/* 2. Main Aggregation Query (Without inline subquery errors) */
proc sql;
    create table work.merged_checks_recode4 as
    select 
        a.BEN_IDT_ANO,
        a.int_start as start format=best.,
        a.int_stop as stop format=best.,
        
        /* Patient-Level / Baseline Variables */
        a.DT_FIRST_AD format=yymmdd10.,
        a.MAX_TRT_DTD format=yymmdd10.,
        a.First_Prescriber,
        a.BEN_AMA_COD,
        a.BEN_DCD_DTE format=yymmdd10.,
        
        /* Patient-level Prev_ and history flags */
        a.Prev_AAH, a.Prev_ALDNonPsy, a.Prev_ALDPsy, a.Prev_Anx, a.Prev_ATMPInv, 
        a.Prev_C2S, a.Prev_HAD, a.Prev_MCO, a.Prev_RIP_0, a.Prev_RIP_2, 
        a.Prev_SSR, a.Prev_Meds, a.Prev_Pregnant, a.Prev_Psy_Adm, a.Prev_Psy_Dx_Rx,
        a.Prev_SeenGP, a.Prev_SeenNonMed, a.Prev_SeenOtherMed, a.Prev_SeenPsych,
        a.AGE_HAD_before, a.AGE_MCO_before, a.AGE_RIP_before, a.AGE_SSR_before,

        /* Boolean Flags (Using robust IS NOT NULL / conditional sum) */
        (case when sum(case when a.Pregnant = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as Pregnant,
        (case when sum(case when a.HasAnx = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as HasAnx,
        (case when sum(case when a.HasOtherMeds = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as HasOtherMeds,
        (case when sum(case when a.HasATMPInv = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as HasATMPInv,
        (case when sum(case when a.HasAAH = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as HasAAH,
        (case when sum(case when a.HasALDPsy = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as HasALDPsy,
        (case when sum(case when a.HasALDNonPsy = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as HasALDNonPsy,
        (case when sum(case when a.HasC2S = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as HasC2S,
        (case when sum(case when a.SeenGP = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as SeenGP,
        (case when sum(case when a.SeenPsych = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as SeenPsych,
        (case when sum(case when a.SeenOtherMed = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as SeenOtherMed,
        (case when sum(case when a.SeenNonMed = 'Yes' then 1 else 0 end) > 0 then 'Yes' else 'No' end) as SeenNonMed,
        (case when sum(case when a.Adm_Psy_Cur > 0 then 1 else 0 end) > 0 then 'Yes' else 'No' end) as Adm_Psy_Cur,
        (case when sum(case when a.Adm_Oth_Cur > 0 then 1 else 0 end) > 0 then 'Yes' else 'No' end) as Adm_Oth_Cur,

        /* Refill Counts and Cumulative Metrics */
        max(a.refill_Nb) as refill_Nb,
        max(a.CumulAnx) as CumulAnx,
        max(a.CumulOtherMeds) as CumulOtherMeds,
        max(a.CumulPsych) as CumulPsych,

        /* Numeric Means */
        mean(a.P20_POP) as P20_POP,
        mean(a.Nb_GP) as Nb_GP,
        mean(a.Nb_Psych) as Nb_Psych,

        /* Event Hierarchy Logic (Using IS NOT NULL to prevent type comparison errors) */
        (case 
           when a.int_stop = a.max_patient_stop and a.terminal_event is not null then a.terminal_event
           when max(case when a.event = 'SWI_CLA' then 1 else 0 end) > 0 then 'SWI_CLA'
           when max(case when a.event = 'ATD_OTH' then 1 else 0 end) > 0 and 
                max(case when a.event = 'SWI_CLA' then 1 else 0 end) = 0 then 'ATD_OTH'
           when max(case when a.event = 'SSRI' then 1 else 0 end) > 0 and 
                max(case when a.event = 'ATD_OTH' then 1 else 0 end) = 0 and 
                max(case when a.event = 'SWI_CLA' then 1 else 0 end) = 0 then 'SSRI'
           else ' '
         end) as event 

    from work.overlapped a
    group by 
        a.BEN_IDT_ANO, a.int_start, a.int_stop, a.max_patient_stop, a.terminal_event,
        a.DT_FIRST_AD, a.MAX_TRT_DTD, a.First_Prescriber, a.BEN_AMA_COD, a.BEN_DCD_DTE,
        a.Prev_AAH, a.Prev_ALDNonPsy, a.Prev_ALDPsy, a.Prev_Anx, a.Prev_ATMPInv, 
        a.Prev_C2S, a.Prev_HAD, a.Prev_MCO, a.Prev_RIP_0, a.Prev_RIP_2, 
        a.Prev_SSR, a.Prev_Meds, a.Prev_Pregnant, a.Prev_Psy_Adm, a.Prev_Psy_Dx_Rx,
        a.Prev_SeenGP, a.Prev_SeenNonMed, a.Prev_SeenOtherMed, a.Prev_SeenPsych,
        a.AGE_HAD_before, a.AGE_MCO_before, a.AGE_RIP_before, a.AGE_SSR_before
    ;
quit;

/* 3. Merge back the modes and psy_meds */
proc sql;
    create table work.merged_checks_recode5 as
    select a.*, 
           b.season_year, 
           c.region, 
           d.FDEP20_quint,
           e.psy_mds
    from sasdata1.merged_checks_recode4 a
    left join work.mode_season_top b on a.BEN_IDT_ANO = b.BEN_IDT_ANO and a.start = b.int_start
    left join work.mode_region_top c on a.BEN_IDT_ANO = c.BEN_IDT_ANO and a.start = c.int_start
    left join work.mode_fdep_top d on a.BEN_IDT_ANO = d.BEN_IDT_ANO and a.start = d.int_start
    left join work.psy_meds_agg e on a.BEN_IDT_ANO = e.BEN_IDT_ANO and a.start = e.int_start;
quit;


/* -------------------------------------------------------------------------
   Step 6: Attach comma-separated unique sorted psy_meds safely
   ------------------------------------------------------------------------- */
/* Sort unique medication components per patient-interval */
proc sort data=work.overlapped(keep=BEN_IDT_ANO int_start int_stop PHA_ATC_LIB) 
          out=work.unique_meds nodupkey;
    by BEN_IDT_ANO int_start int_stop PHA_ATC_LIB;
    where PHA_ATC_LIB ne '';
run;

/* Concatenate sorted unique values using data step first/last logic */
data work.psy_meds_agg;
    set work.unique_meds;
    by BEN_IDT_ANO int_start int_stop;
    length psy_mds $500;
    retain psy_mds;
    
    if first.int_stop then psy_mds = trim(PHA_ATC_LIB);
    else psy_mds = trim(psy_mds) || ', ' || trim(PHA_ATC_LIB);
    
    if last.int_stop then output;
    keep BEN_IDT_ANO int_start int_stop psy_mds;
run;

/* Merge back into final dataset */
proc sql;
    create table work.merged_checks_recode6 as
    select a.*, b.psy_mds
    from sasdata1.merged_checks_recode5 a
    left join work.psy_meds_agg b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO 
     and a.start = b.int_start 
     and a.stop = b.int_stop;
quit;
