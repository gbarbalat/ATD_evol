/* can't do this on R as files are too heavy ...*/ 
%let grace = 45;
%let LM_start = 0;
%let LM_end = 365;


/* =========================================================================
   Step 1: Clean dates where MAX_TRT_DTD or BEN_DCD_DTE precede DT_FIRST_AD
   ========================================================================= */
data work.merged_checks_recode;
    set sasdata1.merged_&grace;
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
       /* coalesce(HAD_Length, 0), */
        coalesce(RIP_0_Length, 0)
    );
    
    if length_hosp > 0 then 
		grace_adm = min(&grace + length_hosp, stop - start);    
	else 
        grace_adm = &grace;

    /* Existing logic for the last row per patient */
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

data sasdata1.merged_Mult_LastPU_&grace.;
    
    set work.merged_checks_recode3 (where=(keep_row=1));

    if stop_found ne 0 then call missing(psy_meds);

    retain 
        ben_idt_ano PHA_ATC_LIB 
        PSY_ADD_ALC PSY_ADD_AUT PSY_ADD_CAT PSY_ADD_CNB PSY_ADD_TAB PSY_AUT_IND PSY_CAT_CAT PSY_DME_IND PSY_ENF_IND PSY_PSC_IND PSY_TNH_BIP PSY_TNH_CAT PSY_TNH_DEP PSY_TNH_NEV
        TPS_ADR_EXC TPS_ADR_INC TPS_ANX_EXC TPS_ANX_INC TPS_CAT_EXC TPS_CAT_INC TPS_HYP_EXC TPS_HYP_INC TPS_NLE_EXC TPS_NLE_INC
        Prev_Psy_Adm
        season_year region BEN_RES_DPT FDEP20_quint P20_POP Nb_GP Nb_Psych 
        DT_FIRST_AD 
        BEN_AMA_COD Pregnant BEN_DCD_DTE MAX_TRT_DTD
        RIP_0_Length RIP_2_Length MCO_Length SSR_Length HAD_Length
        HasATMPInv HasAAH HasC2S HasALDPsy HasALDNonPsy
        CumulAnx CumulGP CumulOtherMed CumulNonMed CumulPsych CumulOtherMeds
        start PSP_SPE_COD stop calc_stop event psy_meds;
run;
