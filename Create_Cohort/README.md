# Section 1 - Gather db

## Collect based on first steps of flowchart  
Collect Meds simply collects meds of interest from 2015 to 2019 -> filtered_treatment_cohort.sas7bdat      
Collect Meds be4 collects meds for the same individuals before the observation period (e.g. to exclude those on Stimulants, APsych, AEpi, and on ATD for less than a year) -> final_treatment_anticohort.sas7bdat    
Collect Supp Admission collects "all time" PSY admissions, and MCO SSR HAD Admissions during the observation period -> master_hospital_extract.sas7bdat    
Collect Z MAX_TRT_DTD collects last point of care consumption to perform sensitivity analysis (varying censoring date) -> ben_max_trt_dtd.sas7bdat  

## Pre-process dbs based on flowchart: obvious filter (excl criteria from flowchart) and obvious select on Out, Exp, Cv 
on SAS, run OLD_NIR_preproc_flowchart.sas  
 Filter to individuals with >= 1 N06A claim between 2015-01-01 and 2017-12-31  
 For individuals initiated before 31Dec2015, remove individuals who were on ATD 1 year before or later  
 Filter out individuals admitted in psychiatry before 2015  
 Filter out individuals prescribed with AEpi, Apsychotics and stimulants before 2015  
 Left join with hospital data 2015-2019 AND with MAX_TRT_DTD  
 
# Section 2 - Process data  
On R,  

## merged_add: merge db of interest, add other vars  
From Meds_preproc,  
left join with Supp_admission_preproc (from 2015 to 2019),  
left join with max_trt_dtd,  
left join with EDI and denom_ps_commune (from rf_commun)  

## merged_explore:  
explore #cols, col names, unique values, tables, NA/distributions; NA in ID and col  

## merged_find_gp:  
Group/arrange levels based on 30-2% & not too many levels (<7) rules & plot_var_outcome:biV steps; recode (e.g. G027B=Citizen, S022= Year + Month) inc. na_if, make categ;



plot var-outcome & biV; redo merged_gp if necessary
merged_gp:  after last round of merged_gp i.e. final set of var and last mdif (inc. char, numeric) - check NA, levels and distrib
merged_ignore: CHECK corr, naniar and drymice; RMV var/cases you can ignore: obvious rmv (no value in observation) and more strategic rmv (influx-outflux); save merged_ignore
merged_imputed and compare_inc_imp.R: imp model, beware IA/non-linear, aux var, squeeze, post and passive imputation (trsf var e.g. BMI). sensitivity anal (MNAR). Data leak (ignore). save merged_imputed
imputation dx (inc. Table1Imputed/NonImputed, density, strip) - warnings - logged events - FMI/LAMBDA ...
merged_listwise complete cases - compare included-full sample using zombie_process_for_full.R and compare_inc_full.R; calculate attrition weights if necessary
pre-anal C/S multivar, easy lgtd (survival instead of cmprsk)/easy ML (glmnet)
reiterate steps 1&2 based on pre-anal (e.g. fmi -> different grouping, remove)
merged_sensit for future sensitivity analyses; save merged_sensit
Section 3 - Revise and Lock Protocol
Section 4 - Write up Participants' characteristics in Results, Fig/Tbles
Section 5 - Analyse data based on analysis plan - Outline of Results section from protocol; Write up section/Tables/Figures on diagnoses +++
Scripts: $PROJECT$_PreProcess_data.R; $PROJECT$_Process_data.R;  $PROJECT$_Anal.R; $PROJECT$_Characteristics
