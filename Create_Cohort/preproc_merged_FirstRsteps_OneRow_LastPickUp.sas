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
    
    /* Calculate grace_adm for each row based on hospital/admission lengths */
    /* Using max() safely handles cases where multiple length columns are > 0 */
    length_hosp = max(
        coalesce(MCO_Length, 0), 
        coalesce(SSR_Length, 0), 
        coalesce(HAD_Length, 0), 
        coalesce(RIP_0_Length, 0)
    );
    
    if length_hosp > 0 then 
		grace_adm = min(&grace + length_hosp, stop - start);    
	else 
        grace_adm = &grace;

    /* Existing logic for the last row per patient */
    if last.BEN_IDT_ANO then do;
        /* Correct SAS syntax for finding the minimum across columns */
        next_exe_date = min(BEN_DCD_DTE, DT_FIRST_AD + 365);
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
        if (stop - start) > grace_adm then do; /* &grace  */
            calc_stop = start ; 
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

data sasdata1.merged_checks_recode6_LastPickUp;
    merge work.merged_checks_recode4 work.merged_checks_recode5 work.psy_concat;
    by ben_idt_ano;
run;
