# Section 1 - Create cohort on sas

## Collect dbs  
_based on first steps of flowchart  
On SAS, run gather_raw_dbs_etc..._  

## Pre-process dbs  
_based on flowchart: obvious filter (excl criteria from flowchart) and obvious select on Out, Exp, Cv 
on SAS, run preproc_flowchart.sas_  

## Run preproc_gather scripts, then preproc_merged scripts  
_includes first steps of data cleaning that I typically do on R because databases are too big, here done on SAS_  


# Section 2 - Process data  
ATD_evol_Process.R  

## merged_add_filter  
_merge dbs of interest, add other vars; further filtering_ done on SAS  

## merged_checks_recode  
_explore #cols, col names, unique values, tables, NA/distributions; NA in ID and col; obvious recode (1,2,3 to More than etc ... inc. na_if, make categ)_ done on SAS and R    

## merged_find_gp  
Group/arrange levels based on 30-2% & not too many levels (<7) rules and checks steps; recode var (e.g. G027B=Citizen, S022= Year + Month)  

## merged_gp  
after last round of merged_find_gp i.e. final set of var and last mdif (inc. char, numeric) - 
check NA, levels and distrib  

## merged_ignore  
CHECK corr, naniar and drymice; RMV var/cases you can ignore: obvious rmv (no value in observation) and more strategic rmv (influx-outflux); save merged_ignore  

## merged_listwise  
complete cases - compare included-full sample using zombie_process_for_full.R and compare_inc_full.R; calculate attrition weights if necessary  

## merged_sensit  
for sensitivity analyses; save merged_sensit
