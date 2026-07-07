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
        
        proc sql;
            create table work.cohort_&suffix as
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
                on pha.PHA_PRS_C13 = ref.PHA_RGE_C13 /* Kept the corrected CIP13 join column */
                
            where prs.EXE_SOI_DTD between '01Jan2013'd and '31Dec2014'd
               and prs.FLX_DIS_DTD = "&sql_date"d    /* Dynamically updates every loop step */
               and prs.BEN_SEX_COD = 2
               and prs.BEN_AMA_COD between 17 and 37
               and (
                  ref.PHA_ATC_CLA like 'N05A%' /* AP + Li */
               or ref.PHA_ATC_CLA like 'N06BA%'  /* Stimulants */
               or ref.PHA_ATC_CLA like 'N06C%'  /* ATD+ */
               or ref.PHA_ATC_CLA like 'N06A%' /* ATD */
               or ref.PHA_ATC_CLA like 'N03A%' /* AntiEpi */
               );               
        quit;
        
        /* Advance the loop tracker forward by exactly 1 month */
        %let current_date = %sysfunc(intnx(month, &current_date, 1, same));
    %end;
%mend extract_monthly_cohorts;

/* Run the macro loop engine */
%extract_monthly_cohorts(01Feb2013, 01Jul2015);


/* ==============================================================================
   2. CONCATENATE ALL GENERATED TABLES INTO A SINGLE MASTER TABLE
   ============================================================================== */
data work.final_treatment_anticohort;
    /* Uses a colon wildcard to automatically set, read, and merge every table 
       in the work library that begins with the prefix 'cohort_' */
    set work.cohort_:;
run;

/* Clean up individual temporary monthly files to save space (Optional) */
proc datasets library=work nolist;
    delete cohort_:;
quit;
