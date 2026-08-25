/* ==============================================================================
   1. DEFINE THE MACRO TO GENERATE AND RUN THE MONTHLY QUERIES
   ============================================================================== */
%macro extract_monthly_cohorts(start_date, end_date);
    
    /* Convert input text dates to internal SAS date numeric values */
    %let current_date = %sysfunc(inputn(&start_date, date9.));
    %let final_date   = %sysfunc(inputn(&end_date, date9.));
    
    /* Loop month by month until we pass the end date */
    %do %while (&current_date <= &final_date);
        
        /* Format the macro dates for the table names and SQL literals */
        %let suffix   = %sysfunc(putn(&current_date, yymmddn6.)); /* e.g., 20150201 -> 150201 */
        %let sql_date = %sysfunc(putn(&current_date, date9.));    /* e.g., 01FEB2015 */
        
        /* STEP A: Fast Database Extraction (No Local Joins) */
        proc sql;
            create table work.raw_&suffix as
            select 
                /* Variables from ER_PRS_F */
                prs.EXE_SOI_DTD,
                prs.FLX_DIS_DTD,
                prs.BEN_SEX_COD,
                prs.BEN_AMA_COD,
                prs.BEN_DCD_DTE,
                prs.BEN_NIR_PSA,
                prs.BEN_RNG_GEM,
                prs.BEN_RES_DPT,
                prs.BEN_RES_COM,
                prs.PRE_PRE_DTD,
                prs.PRS_GRS_DTD,
                
                /* Variables from ER_PHA_F */
                pha.PHA_PRS_C13,
                pha.PHA_ACT_QSN,
                
                /* Variables from IR_PHA_R */
                ref.PHA_FRM_LIB,
                ref.PHA_ATC_L03,
                ref.PHA_ATC_LIB, 
                ref.PHA_SUB_DOS,
                ref.PHA_UPC_NBR
                
            from oravue.ER_PRS_F as prs

            inner join oravue.ER_PHA_F as pha
                on  prs.FLX_DIS_DTD = pha.FLX_DIS_DTD
                and prs.FLX_TRT_DTD = pha.FLX_TRT_DTD
                and prs.FLX_EMT_TYP = pha.FLX_EMT_TYP
                and prs.FLX_EMT_NUM = pha.FLX_EMT_NUM
                and prs.FLX_EMT_ORD = pha.FLX_EMT_ORD
                and prs.ORG_CLE_NUM = pha.ORG_CLE_NUM
                and prs.DCT_ORD_NUM = pha.DCT_ORD_NUM
                and prs.PRS_ORD_NUM = pha.PRS_ORD_NUM
                and prs.REM_TYP_AFF = pha.REM_TYP_AFF
                
            inner join oravue.IR_PHA_R as ref
                on pha.PHA_PRS_C13 = ref.PHA_RGE_C13
                
            where prs.EXE_SOI_DTD between '01Jan1975'd and '31Dec2014'd
               and prs.FLX_DIS_DTD = "&sql_date"d
               and prs.BEN_SEX_COD = 2
               and (
                  ref.PHA_ATC_CLA like 'N05A%'
               or ref.PHA_ATC_CLA like 'N06BA%'
               or ref.PHA_ATC_CLA like 'N06C%'
               or ref.PHA_ATC_CLA like 'N06A%'
               or ref.PHA_ATC_CLA like 'N03A%'
               );               
        quit;
        
        /* STEP B: Fast In-Memory Hash Filter */
        data work.cohort_&suffix;
            if _n_ = 1 then do;
                declare hash h(dataset:'work.filtered_treatment_cohort');
                h.defineKey('BEN_NIR_PSA', 'BEN_RNG_GEM');
                h.defineDone();
            end;
            
            set work.raw_&suffix;
            
            /* Keep ONLY rows that match the keys in work.filtered_treatment_cohort */
            if h.find() = 0; 
        run;

        /* Clean up raw intermediate tables to save space */
        proc datasets library=work nolist;
            delete raw_&suffix;
        quit;

        /* Advance the loop tracker forward by exactly 1 month */
        %let current_date = %sysfunc(intnx(month, &current_date, 1, s));
    %end;
%mend extract_monthly_cohorts;

/* Run the macro loop engine */
%extract_monthly_cohorts(01Feb1975, 01Jul2015);


/* ==============================================================================
   2. CONCATENATE ALL GENERATED TABLES INTO A SINGLE MASTER TABLE
   ============================================================================== */
data work.final_treatment_anticohort;
    set work.cohort_:;
run;

/* Clean up individual temporary monthly files to save space */
proc datasets library=work nolist;
    delete cohort_:;
quit;


/* 1. Extract distinct ATC Code to Name mappings */
proc sql;
    create table work.atc_lookup as
    select distinct 
        PHA_ATC_CLA, 
        PHA_ATC_LIB
    from work.filtered_treatment_cohort
    where PHA_ATC_CLA is not missing 
      and PHA_ATC_LIB is not missing;
quit;

/* 2. Join the lookup table onto the anti-cohort */
proc sql;
    create table work.final_treatment_anticohort2 as
    select 
        anti.*,
        map.PHA_ATC_CLA
    from work.final_treatment_anticohort as anti
    left join work.atc_lookup as map
        on anti.PHA_ATC_LIB = map.PHA_ATC_LIB;
quit;
