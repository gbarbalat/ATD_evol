library(haven)
library(dplyr)
library(data.table)

#merged_ merge Exp, Out, Cv - explore #, unique and NA in ID and col names (.x and .y)
merged_ <- read_sas("final_cohort.sas7bdat")
merged_ <- merged_ %>% mutate(id=paste0(BEN_NIR_PSA, "_", BEN_RNG_GEM))
colnames(merged_)
nrows(merged_)
unique(merged_$id)
colSums(is.na(merged_))


#merged_col_obs: Add on obvious var, obvious select, filter (excl criteria) & recode (e.g. G027B=Citizen, S022= Year + Month) inc. na_if, make categ; Explore NA/distributions; 
merged_col_obs <- merged_
#for each id, make the long wide for each prescription (Nrow -> Ndays) 
# Convert to data.table if it isn't one already
setDT(merged_col_obs)
# Collapse to one row per id and date group, creating the 'ndays' column
merged_col_obs <- merged_col_obs[, .(
  ndays = .N,
  # Keep the first occurrence of all other columns
  across(everything(), first) 
), by = .(id, FLX_DIS_DTD)]

#recode medication class
# Assign labels based on the start of the ATC code string
merged_col_obs[, Rx_class := fcase(
  startsWith(PHA_ATC_CLA, "N05AN01"), "Lithium",
  startsWith(PHA_ATC_CLA, "N05A"),    "Antipsychotics (excl. Lithium)",
  startsWith(PHA_ATC_CLA, "N05B"),    "Anxiolytics",
  startsWith(PHA_ATC_CLA, "N05C"),    "Hypnotics and Sedatives",
  startsWith(PHA_ATC_CLA, "N06A"),    "Antidepressants",
  startsWith(PHA_ATC_CLA, "N03A"),    "Antiepileptics",
  default = "Other"
)]

#Apply Individualized dispensing pattern method
source("IDP.R")
merged_col_obs <- merged_col_obs %>% mutate(dispensed_date=EXE_SOI_DTD, quantity_dispensed=ndays)
IDP_function(data=merged_col_obs, drug_name=PHA_ATC_LIB, strength=PHA_SUB_DOS, formulation = PHA_FRM_LIB, )


merged_gp: Add on new set of var; Group/arrange levels based on 30-2% per level & not too many levels (<7) & further steps
plot var-outcome & biV; redo merged_gp if necessary
merged_final: Add on final set of var and last mdif (inc. char, numeric)
merged_ignore: CHECK corr, naniar and drymice; rmv var/cases: obvious rmv (no value in observation) and more strategic rmv (influx-outflux); save merged_ignore
merged_imputed and compare_inc_imp.R: imp model, beware IA/non-linear, aux var, squeeze, post and passive imputation (trsf var e.g. BMI). sensitivity anal (MNAR). Data leak (ignore). save merged_imputed
imputation dx (inc. Table1Imputed/NonImputed, density, strip) - warnings - logged events - FMI/LAMBDA ...
merged_listwise complete cases - compare included-full sample using zombie_process_for_full.R and compare_inc_full.R; calculate attrition weights if necessary
pre-anal C/S multivar, easy lgtd (survival instead of cmprsk)/easy ML (glmnet)
reiterate step1 based on checks and pre-tests (e.g. fmi -> different grouping, remove)
merged_sensit for future sensitivity analyses; save merged_sensit
