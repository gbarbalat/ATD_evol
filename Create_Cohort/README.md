# Section 1 - Gather db

## Collect based on first steps of flowchart  
Steps 1 to 6 = create cohort id with >= 1 N06A claim (ATD) between 2015-01-01 and 2017-12-31; gather Meds; gather RIP; MCO; SSR; HAD  (Step 0 = number of women 18-39 with claims during 2015-2017)  

## Pre-process dbs based on flowchart: obvious filter (excl criteria from flowchart) and obvious select on Out, Exp, Cv 
on SAS, run preproc_flowchart.sas  
 - Remove individuals who had been on ATD before their ATD initiation 2015-2017
 - Remove individuals with a psych admission before their ATD initiation 2015-2017
 - Remove individuals prescribed with AEpi, Apsychotics and stimulants before their ATD initiation 2015-2017  
 
# Section 2 - Process data  
On R, run ATD_evol_Process.R    

## merged_add_filter: merge db of interest, add other vars; further filtering  
From FC_4,  
left join with Admissions (from 2015 to 2019),  
left join with Other meds, pregnancy, prescriber (from 2015 to 2019)
left join with EDI and denom_ps_commune (from rf_commun)  

## merged_checks_recode: explore #cols, col names, unique values, tables, NA/distributions; NA in ID and col; obvious recode (1,2,3 to More than etc ... inc. na_if, make categ)  

## merged_find_gp: Group/arrange levels based on 30-2% & not too many levels (<7) rules and checks steps; recode var (e.g. G027B=Citizen, S022= Year + Month);  

## merged_gp:  after last round of merged_find_gp i.e. final set of var and last mdif (inc. char, numeric) - check NA, levels and distrib  

## merged_ignore: CHECK corr, naniar and drymice; RMV var/cases you can ignore: obvious rmv (no value in observation) and more strategic rmv (influx-outflux); save merged_ignore  

# merged_listwise complete cases - compare included-full sample using zombie_process_for_full.R and compare_inc_full.R; calculate attrition weights if necessary  

# merged_sensit for sensitivity analyses; save merged_sensit
