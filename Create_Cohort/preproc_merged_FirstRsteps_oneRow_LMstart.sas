/* can't do this on R as files are too heavy ...*/ 
%let grace = 45;
%let LM_start = 0;
%let LM_end = 365;


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
    by BEN_IDT_ANO start;
    
    if last.BEN_IDT_ANO then do;
        /* Correct SAS syntax for finding the minimum across columns */
        next_exe_date = min(BEN_DCD_DTE, MAX_TRT_DTD, DT_FIRST_AD + 365);
        stop = next_exe_date - DT_FIRST_AD;
    end;
run;

/* =========================================================================
   Step 3: Db for Bsl analysis
   ========================================================================= */
/* Sort chronologically to evaluate the sequential stop condition per patient */
proc sort data=work.merged_checks_recode2;
    by ben_idt_ano start;
run;

data work.merged_checks_recode3;
    set work.merged_checks_recode2;
    by ben_idt_ano start;
    
    retain stop_found;
    if first.ben_idt_ano then stop_found = 0;
    
    /* Sequential evaluation for stop */
    if stop_found = 0 then do;
        keep_row = 1;
        if (stop - start) > &grace then do;
            calc_stop = start ; /* + &grace */
            stop_found = 1;
        end;
        else if last.ben_idt_ano then do;
            calc_stop = start;
            stop_found = 1;
        end;
    end;
    else keep_row = 0;
run;

/* Extract patient-level summary (first values for covar, plus calculated stop) */
data work.merged_checks_recode4;
    set work.merged_checks_recode3 (where=(start=&LM_start));
    by ben_idt_ano start;
    
    /* Automatically takes the first. value for all columns due to data step behavior */
    if first.ben_idt_ano;

	/* keep prev variables */ 
	keep ben_idt_ano season_year region BEN_RES_DPT FDEP20_quint P20_POP Nb_GP Nb_Psych 
	DT_FIRST_AD First_Prescriber
	BEN_AMA_COD Prev_Pregnant BEN_DCD_DTE MAX_TRT_DTD
	Prev_C2S Prev_ATMPInv Prev_AAH Prev_Anx Prev_ALDPsy Prev_ALDNonPsy
	AGE_HAD_before AGE_MCO_before AGE_RIP_before AGE_SSR_before Prev_HAD Prev_MCO Prev_RIP_0 Prev_RIP_2 Prev_SSR
	Prev_Psy_Dx_Rx Prev_Psy_Adm
	Prev_SeenPsych Prev_SeenOtherMed Prev_SeenGP Prev_SeenNonMed 
	Prev_Meds Prev_Anx
	CumulPrev_SeenNonMed CumulPrev_SeenOtherMed CumulPrev_SeenGP CumulPrev_SeenPsych CumulPrev_Meds CumulPrev_Anx
	;
    /* drop event psy_meds calc_stop start stop stop_found keep_row; */
run;

/* Extract calculated stop */
data work.merged_checks_recode5;
    set work.merged_checks_recode3 (where=(stop_found=1) keep=ben_idt_ano start stop_found calc_stop);
    by ben_idt_ano start;
    
    if first.ben_idt_ano;
    
    keep ben_idt_ano calc_stop;
run;


/* concatenate meds*/
proc sort data=work.merged_checks_recode3 
          out=work.filtered_unique;
    where keep_row = 1 and not missing(psy_meds);
    by ben_idt_ano start;
run;

data work.psy_concat;
    set work.filtered_unique;
    by ben_idt_ano start;
    
    length unique_psy_meds $32767;
    retain unique_psy_meds;
    
    if first.ben_idt_ano then unique_psy_meds = "";
    
    /* Build the comma-separated list */
    if unique_psy_meds = "" then unique_psy_meds = strip(psy_meds);
    else unique_psy_meds = catx(", ", unique_psy_meds, strip(psy_meds));
    
    /* Keep only the final row for each patient */
    if last.ben_idt_ano;
    keep ben_idt_ano unique_psy_meds;
run;


/* Merge all three dbs */
proc sort data=work.merged_checks_recode4; by ben_idt_ano; run;
proc sort data=work.merged_checks_recode5; by ben_idt_ano; run;
proc sort data=work.psy_concat; by ben_idt_ano; run;

data sasdata1.merged_checks_recode6;
    merge work.merged_checks_recode4 work.merged_checks_recode5 work.psy_concat;
    by ben_idt_ano;
run;























   
/* =========================================================================
   Step 4: Final Aggregation (All variables + True Modes + Patient attributes)
   ========================================================================= */

/* 1. Pre-calculate the mode for season_year, region, and FDEP20_quint with an explicit frequency name */
proc freq data=work.overlapped noprint;
    tables BEN_IDT_ANO * int_start * season_year / out=work.mode_season (rename=(count=freq) drop=percent);
    tables BEN_IDT_ANO * int_start * region / out=work.mode_region (rename=(count=freq) drop=percent);
    tables BEN_IDT_ANO * int_start * FDEP20_quint / out=work.mode_fdep (rename=(count=freq) drop=percent);	
run;

proc freq data=work.overlapped noprint;
      tables BEN_IDT_ANO * int_start * BEN_RES_DPT / out=work.mode_BEN_RES_DPT (rename=(count=freq) drop=percent);	
run;

/* Keep only the top frequency (mode) per patient-interval */
proc sort data=work.mode_season; by BEN_IDT_ANO int_start descending freq; run;
data work.mode_season_top; set work.mode_season; by BEN_IDT_ANO int_start; if first.int_start; keep BEN_IDT_ANO int_start season_year; run;

proc sort data=work.mode_region; by BEN_IDT_ANO int_start descending freq; run;
data work.mode_region_top; set work.mode_region; by BEN_IDT_ANO int_start; if first.int_start; keep BEN_IDT_ANO int_start region; run;

proc sort data=work.mode_BEN_RES_DPT; by BEN_IDT_ANO int_start descending freq; run;
data work.mode_BEN_RES_DPT_top; set work.mode_BEN_RES_DPT; by BEN_IDT_ANO int_start; if first.int_start; keep BEN_IDT_ANO int_start BEN_RES_DPT; run;

proc sort data=work.mode_fdep; by BEN_IDT_ANO int_start descending freq; run;
data work.mode_fdep_top; set work.mode_fdep; by BEN_IDT_ANO int_start; if first.int_start; keep BEN_IDT_ANO int_start FDEP20_quint; run;

/* mean age instead of varying age */
/* 1. Calculate the mean per patient */
proc sql;
    create table work.patient_means as
    select BEN_IDT_ANO, mean(BEN_AMA_COD) as mean_ama
    from work.overlapped
    group by BEN_IDT_ANO;
quit;

/* 2. Replace BEN_AMA_COD with the calculated mean */
data work.overlapped;
    merge work.overlapped (drop=BEN_AMA_COD) work.patient_means;
    by BEN_IDT_ANO;
    BEN_AMA_COD = mean_ama;
    drop mean_ama;
run;

/* add on last pickup date*/
/* 1. Find the maximum EXE_SOI_DTD per patient */
proc means data=work.overlapped noprint;
    by BEN_IDT_ANO;
    var EXE_SOI_DTD;
    output out=work.max_pickup_dt(drop=_TYPE_ _FREQ_) max=last_pickup_dt;
run;

/* 2. Ensure overlapped is sorted for the merge */
proc sort data=work.overlapped;
    by BEN_IDT_ANO;
run;

/* 3. Merge the last_pickup_dt back into overlapped using a DATA step */
data work.overlapped;
    merge work.overlapped work.max_pickup_dt;
    by BEN_IDT_ANO;
    format last_pickup_dt yymmdd10.;
run;

/* Aggregation query */
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
		a.last_pickup_dt,
        
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
           when a.int_stop = a.max_patient_stop and a.terminal_event in ('Cens', 'Death') then a.terminal_event
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
        a.BEN_IDT_ANO, a.int_start, a.int_stop, a.max_patient_stop, a.terminal_event, a.last_pickup_dt,
        a.DT_FIRST_AD, a.MAX_TRT_DTD, a.First_Prescriber, a.BEN_AMA_COD, a.BEN_DCD_DTE,
        a.Prev_AAH, a.Prev_ALDNonPsy, a.Prev_ALDPsy, a.Prev_Anx, a.Prev_ATMPInv, 
        a.Prev_C2S, a.Prev_HAD, a.Prev_MCO, a.Prev_RIP_0, a.Prev_RIP_2, 
        a.Prev_SSR, a.Prev_Meds, a.Prev_Pregnant, a.Prev_Psy_Adm, a.Prev_Psy_Dx_Rx,
        a.Prev_SeenGP, a.Prev_SeenNonMed, a.Prev_SeenOtherMed, a.Prev_SeenPsych,
        a.AGE_HAD_before, a.AGE_MCO_before, a.AGE_RIP_before, a.AGE_SSR_before
    ;
quit;


/* Merge back the modes and psy_meds */
proc sql;
    create table work.merged_checks_recode5 as
    select a.*, 
           b.season_year, 
           c.region, 
           d.FDEP20_quint,
		   e.BEN_RES_DPT
    from work.merged_checks_recode4 a
    left join work.mode_season_top b on a.BEN_IDT_ANO = b.BEN_IDT_ANO and a.start = b.int_start
    left join work.mode_region_top c on a.BEN_IDT_ANO = c.BEN_IDT_ANO and a.start = c.int_start
    left join work.mode_fdep_top d on a.BEN_IDT_ANO = d.BEN_IDT_ANO and a.start = d.int_start
	left join work.mode_BEN_RES_DPT_top e on a.BEN_IDT_ANO = e.BEN_IDT_ANO and a.start = e.int_start 
	;
quit;


/* -------------------------------------------------------------------------
   Step 6: Attach comma-separated unique sorted psy_meds safely
   ------------------------------------------------------------------------- */
/* Sort unique medication components per patient-interval */
proc sort data=work.overlapped(keep=BEN_IDT_ANO int_start int_stop psy_meds) 
          out=work.all_meds ;/*nodupkey*/
    by BEN_IDT_ANO int_start int_stop psy_meds;
    where psy_meds ne '';
run;
proc sort data=work.all_meds
          out=work.unique_meds nodupkey;/**/
    by BEN_IDT_ANO int_start int_stop psy_meds;
    where psy_meds ne '';
run;

/* Concatenate sorted unique values using data step first/last logic */
/* Step 1: Flatten rows and split any comma-separated values into individual rows */
data work.meds_long;
    set work.all_meds;
    do i = 1 to countw(psy_meds, ',');
        med_item = upcase(strip(scan(psy_meds, i, ',')));
        if med_item ne '' then output;
    end;
    keep BEN_IDT_ANO int_start int_stop med_item;
run;

/* Step 2: Sort, remove redundancies, and ensure alphabetical order */
proc sort data=work.meds_long nodupkey;
    by BEN_IDT_ANO int_start int_stop med_item;
run;

/* Step 3: Collapse back into a single string per group */
data work.psy_meds_agg;
    set work.meds_long;
    by BEN_IDT_ANO int_start int_stop med_item;
    
    length psy_meds $1000;
    retain psy_meds;
    
    if first.int_stop or first.int_start or first.BEN_IDT_ANO then psy_meds = '';
    
    if psy_meds = '' then psy_meds = med_item;
    else psy_meds = catx(', ', psy_meds, med_item);
    
    if last.int_stop or last.int_start or last.BEN_IDT_ANO then output;
    
    keep BEN_IDT_ANO int_start int_stop psy_meds;
run;


/* Merge back into final dataset */
proc sql;
    create table sasdata1.merged_checks_recode6 as
    select a.*, b.psy_meds
    from work.merged_checks_recode5 a
    left join work.psy_meds_agg b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO 
     and a.start = b.int_start 
     and a.stop = b.int_stop;
quit;

/* -------------------------------------------------------------------------
   Step 7: Checks
   ------------------------------------------------------------------------- */
proc sql;
    create table work.patients_under_9 as
    select BEN_IDT_ANO, 
           DT_FIRST_AD, 
           MAX_TRT_DTD, 
           BEN_DCD_DTE, start, stop
    from sasdata1.merged_checks_recode6
    where (MAX_TRT_DTD > intnx('year', DT_FIRST_AD, 1, 'same') 
           and BEN_DCD_DTE > intnx('year', DT_FIRST_AD, 1, 'same'))
    group by BEN_IDT_ANO
    having count(*) <> 9;
quit;

/* rmv 2 participants entered mistakenly - DPN_QLF issue... */
data sasdata1.merged_checks_recode6;
    set sasdata1.merged_checks_recode6;
    if BEN_IDT_ANO not in ('A', 'B');
run;
