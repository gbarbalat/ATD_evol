/* Step 1: Ensure sasdata1.merged_45 is sorted by BEN_IDT_ANO and start */
proc sort data=work.merged_&grace. out=work._m&grace._sorted;
    by BEN_IDT_ANO start;
run;

/* Step 2: Build lead(event) and lead(psy_meds) = values on row i+1 within each BEN_IDT_ANO */
data work._m&grace._lead;
    merge work._m&grace._sorted
          work._m&grace._sorted (firstobs=2 
                            keep=BEN_IDT_ANO event psy_meds 
                            rename=(BEN_IDT_ANO=_next_id 
                                    event=_next_event 
                                    psy_meds=_next_psy_meds));
    
    /* If the next row belongs to the same BEN_IDT_ANO, take row i+1's values; otherwise missing */
    if BEN_IDT_ANO = _next_id then do;
        _lead_event    = _next_event;
        _lead_psy_meds = _next_psy_meds;
    end;
    else do;
        _lead_event    = .;
        _lead_psy_meds = ''; /* Use . if psy_meds is numeric */
    end;

    drop _next_id _next_event _next_psy_meds;
run;

/* Step 3: Apply all first.BEN_IDT_ANO, i-1 lag, and i+1 lead rules in exact column order */
data sasdata1.merged_&.;
    /* Declare wider length for Pregnant & _lag_Pregnant BEFORE SET to avoid truncating Prev_Pregnant */
    length Pregnant _lag_Pregnant $20;

    /* RETAIN before SET locks the exact output column order in the PDV */
    retain
        BEN_IDT_ANO
        /* 1 */     refill_nb
        /* 1 bis */ season_year region BEN_RES_DPT FDEP20_quint P20_POP Nb_GP Nb_Psych
        /* 2 */     PSY_: TPS_: MAX_TRT_DTD BEN_DCD_DTE BEN_AMA_COD DT_FIRST_AD PHA_ATC_LIB
        /* 3 & 4 */ RIP_0_Length RIP_2_Length MCO_Length HAD_Length SSR_Length
        /* 5 */     Pregnant
        /* 6 */     HasATMPInv HasAAH HasC2S HasALDPsy HasALDNonPsy
        /* 7 */     CumulAnx CumulGP CumulOtherMed CumulNonMed CumulPsych CumulOtherMeds
        /* 8 */     start PSP_SPE_COD stop
        /* 9 */     event psy_meds
    ;

    set work._m45_lead;
    by BEN_IDT_ANO;

    /* Retain helper variable to hold the patient's first PHA_ATC_LIB across all rows */
    retain _first_PHA_ATC_LIB;

    /* Compute i-1 values from the original merged_45 columns BEFORE overwriting */
    /* Rule 1 bis */
    _lag_season_year  = lag(season_year);
    _lag_region       = lag(region);
    _lag_BEN_RES_DPT  = lag(BEN_RES_DPT);
    _lag_FDEP20_quint = lag(FDEP20_quint);
    _lag_P20_POP      = lag(P20_POP);
    _lag_Nb_GP        = lag(Nb_GP);
    _lag_Nb_Psych     = lag(Nb_Psych);

    /* Rules 3 & 4 */
    _lag_RIP_0_Length = lag(RIP_0_Length);
    _lag_RIP_2_Length = lag(RIP_2_Length);
    _lag_MCO_Length   = lag(MCO_Length);
    _lag_HAD_Length   = lag(HAD_Length);
    _lag_SSR_Length   = lag(SSR_Length);

    /* Rule 5 */
    _lag_Pregnant = lag(Pregnant);

    /* Rule 6 */
    _lag_HasATMPInv   = lag(HasATMPInv);
    _lag_HasAAH       = lag(HasAAH);
    _lag_HasC2S       = lag(HasC2S);
    _lag_HasALDPsy    = lag(HasALDPsy);
    _lag_HasALDNonPsy = lag(HasALDNonPsy);

    /* Rule 7 */
    _lag_CumulAnx       = lag(CumulAnx);
    _lag_CumulGP        = lag(CumulGP);
    _lag_CumulOtherMed  = lag(CumulOtherMed);
    _lag_CumulNonMed    = lag(CumulNonMed);
    _lag_CumulPsych     = lag(CumulPsych);
    _lag_CumulOtherMeds = lag(CumulOtherMeds);

    /* Assign row-specific values within each BEN_IDT_ANO */
    if first.BEN_IDT_ANO then do;
        /* Capture first PHA_ATC_LIB for this BEN_IDT_ANO */
        _first_PHA_ATC_LIB = PHA_ATC_LIB;

        /* Rules 3 & 4: Convert 'Yes'/'No' character indicators to numeric (1/0) */
        RIP_0_Length = (Prev_RIP_0 = 'Yes');
        RIP_2_Length = (Prev_RIP_2 = 'Yes');
        MCO_Length   = (Prev_MCO   = 'Yes');
        HAD_Length   = (Prev_HAD   = 'Yes');
        SSR_Length   = (Prev_SSR   = 'Yes');

        /* Rule 5 */
        Pregnant = Prev_Pregnant;

        /* Rule 6 */
        HasATMPInv   = Prev_ATMPInv;
        HasAAH       = Prev_AAH;
        HasC2S       = Prev_C2S;
        HasALDPsy    = Prev_ALDPsy;
        HasALDNonPsy = Prev_ALDNonPsy;

        /* Rule 7 */
        CumulAnx       = CumulPrev_Anx;
        CumulGP        = CumulPrev_SeenGP;
        CumulOtherMed  = CumulPrev_SeenOtherMed;
        CumulNonMed    = CumulPrev_SeenNonMed;
        CumulPsych     = CumulPrev_SeenPsych;
        CumulOtherMeds = CumulPrev_Meds;
    end;
    else do;
        /* Rule 1 bis */
        season_year  = _lag_season_year;
        region       = _lag_region;
        BEN_RES_DPT  = _lag_BEN_RES_DPT;
        FDEP20_quint = _lag_FDEP20_quint;
        P20_POP      = _lag_P20_POP;
        Nb_GP        = _lag_Nb_GP;
        Nb_Psych     = _lag_Nb_Psych;

        /* Rules 3 & 4 */
        RIP_0_Length = _lag_RIP_0_Length;
        RIP_2_Length = _lag_RIP_2_Length;
        MCO_Length   = _lag_MCO_Length;
        HAD_Length   = _lag_HAD_Length;
        SSR_Length   = _lag_SSR_Length;

        /* Rule 5 */
        Pregnant = _lag_Pregnant;

        /* Rule 6 */
        HasATMPInv   = _lag_HasATMPInv;
        HasAAH       = _lag_HasAAH;
        HasC2S       = _lag_HasC2S;
        HasALDPsy    = _lag_HasALDPsy;
        HasALDNonPsy = _lag_HasALDNonPsy;

        /* Rule 7 */
        CumulAnx       = _lag_CumulAnx;
        CumulGP        = _lag_CumulGP;
        CumulOtherMed  = _lag_CumulOtherMed;
        CumulNonMed    = _lag_CumulNonMed;
        CumulPsych     = _lag_CumulPsych;
        CumulOtherMeds = _lag_CumulOtherMeds;
    end;

    /* Carry the first PHA_ATC_LIB onto every row of BEN_IDT_ANO */
    PHA_ATC_LIB = _first_PHA_ATC_LIB;

    /* Rule 9: event and psy_meds in cell i = values from cell i+1 */
    event    = _lead_event;
    psy_meds = _lead_psy_meds;

    /* Keep only the requested columns */
    keep 
        BEN_IDT_ANO
        refill_nb
        season_year region BEN_RES_DPT FDEP20_quint P20_POP Nb_GP Nb_Psych
        PSY_: TPS_: MAX_TRT_DTD BEN_DCD_DTE BEN_AMA_COD DT_FIRST_AD PHA_ATC_LIB
        RIP_0_Length RIP_2_Length MCO_Length HAD_Length SSR_Length
        Pregnant
        HasATMPInv HasAAH HasC2S HasALDPsy HasALDNonPsy
        CumulAnx CumulGP CumulOtherMed CumulNonMed CumulPsych CumulOtherMeds
        start PSP_SPE_COD stop
        event psy_meds
    ;
run;
