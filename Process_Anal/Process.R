rm(list=ls())

library(haven)
library(data.table)

sas_file <- "./sasdata1/filtered_treatment_cohort.sas7bdat"

# Configurations
chunk_size <- 5000000
skip_rows <- 0
chunk_list <- list()
i <- 1

repeat {
  message(sprintf("Reading rows %s to %s...", skip_rows + 1, skip_rows + chunk_size))
  
  # Read a subset of the file
  df_chunk <- read_sas(sas_file, skip = skip_rows, n_max = chunk_size)
  
  # Break the loop if we have reached the end of the file
  if (nrow(df_chunk) == 0) {
    message("Finished reading all rows.")
    break
  }
  
  # Strip heavy SAS attributes and convert directly to data.table in memory
  dt_chunk <- as.data.table(lapply(df_chunk, function(x) {
    attr(x, "label") <- NULL
    attr(x, "format.sas") <- NULL
    class(x) <- setdiff(class(x), "haven_labelled")
    return(x)
  }))
  
  # Save the clean table chunk into our list
  chunk_list[[i]] <- dt_chunk
  
  # Advance row trackers
  skip_rows <- skip_rows + chunk_size
  i <- i + 1
  
  # Force R to clear deleted temporary memory allocations
  gc() 
}

# Combine the clean pieces into a single master data.table
merged_ <- rbindlist(chunk_list)

# Ultimate memory cleanup
rm(chunk_list, df_chunk, dt_chunk); gc()

merged_[, id := stringi::stri_c(BEN_NIR_PSA, "_", BEN_RNG_GEM)]

# 1. Filter the rows where the ATC class starts with N06A or N06C
# 2. Extract only the unique 'id' values from those rows
matching_ids <- unique(merged_[PHA_ATC_CLA %like% "^N06A|^N06C", id])

# 1. Set the key (indexes the data by ID instantly)
setkey(merged_, id)

# 2. Filter using the indexed key (blistering fast)
merged_ <- merged_[.(matching_ids)]

#merged_ merge Exp, Out, Cv - explore #, unique and NA in ID and col names (.x and .y)
colnames(merged_)
nrow(merged_)
unique(merged_$id)
colSums(is.na(merged_))


#Add on obvious var, obvious select, filter (excl criteria) & recode (e.g. G027B=Citizen, S022= Year + Month) inc. na_if, make categ; Explore NA/distributions; 
merged_add_select_filter_recode <- merged_ %>% select(-BEN_NIR_PSA, BEN_RNG_GEM)
#for each id, make the long wide for each prescription (Nrow -> Ndays) 
# Convert to data.table if it isn't one already
setDT(merged_add_select_filter_recode)
# Collapse to one row per id and date group, creating the 'ndays' column
merged_add_select_filter_recode <- merged_add_select_filter_recode[, c(
  .(ndays = .N),               # Create the count column
  lapply(.SD, first)           # Grab the first row's value for all other columns
), by = .(id, FLX_DIS_DTD)]

#recode medication class
# Assign labels based on the start of the ATC code string
merged_add_select_filter_recode[, Rx_class := fcase(
  startsWith(PHA_ATC_CLA, "N05AN01"), "Lithium",
  startsWith(PHA_ATC_CLA, "N05A"),    "Antipsychotics (excl. Lithium)",
  startsWith(PHA_ATC_CLA, "N05B"),    "Anxiolytics",
  startsWith(PHA_ATC_CLA, "N05C"),    "Hypnotics and Sedatives",
  startsWith(PHA_ATC_CLA, "N06A"),    "Antidepressants",
    startsWith(PHA_ATC_CLA, "N06BA"),    "Stimulants",
  startsWith(PHA_ATC_CLA, "N06C"),    "Antidepressants+",

  startsWith(PHA_ATC_CLA, "N03A"),    "Antiepileptics",
  default = "Other"
)]

#recode formulation (PHA_FRM_LIB) as injection vs. non-injection 
stop()

#Apply Individualized dispensing pattern method
source("IDP.R")
merged_add_select_filter_recode[, prescribed_dose := PHA_SUB_DOS * PHA_ACT_QSN]
final_episodes <- run_hybrid_idp(
  dt = merged_add_select_filter_recode, 
  molecule_var = "PHA_ATC_LIB", #"drug_name", 
  formulation_var = "PHA_FRM_LIB", 
  quantity_var = "ndays", #days of prescription ("quantity_dispensed")
  date_var = "EXE_SOI_DTD",#"dispensed_date", 
  prescribed_dose_mg_var = "prescribed_dose", # Prescribed daily dose in mg
  strength_mg_var = "PHA_SUB_DOS"     # Parsed numeric strength (e.g. 75 or 150 for EFFEXOR)
)

#merged_gp: Add on new set of var; Group/arrange levels based on 30-2% per level & not too many levels (<7) & further steps
#explore with tables, NA, na_if
#gp variables if necessary
merged_gp <- merged_add_select_filter_recode[final_episodes, on = "id"]

# Identify categorical or factor columns
char_cols <- names(merged_gp)[sapply(merged_gp, function(x) is.character(x) | is.factor(x) | is.logical(x))]

# Generate fast frequency tables for each categorical column
# (Excluding 'id' since it has too many unique values)
categorical_cols <- setdiff(char_cols, "id")

cat_distributions <- lapply(categorical_cols, function(col) {
  message("Processing: ", col)
  merged_gp[, .(Count = .N), by = col][order(-Count)]
})
names(cat_distributions) <- categorical_cols

# To view a specific table (e.g., Rx_class):
# print(cat_distributions$Rx_class)

# Identify numeric/date columns
num_cols <- names(merged_gp)[sapply(merged_gp, function(x) is.numeric(x) | inherits(x, "Date"))]

# Compute a swift distribution matrix (Min, 25th, Median, 75th, Max, and Missing counts)
numeric_distributions <- merged_gp[, lapply(.SD, function(x) {
  if(inherits(x, "Date")) x <- as.numeric(x) # Temporarily convert dates to calculate quantiles safely
  q <- quantile(x, probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE)
  list(
    Min    = q[1],
    Q25    = q[2],
    Median = q[3],
    Q75    = q[4],
    Max    = q[5],
    NAs    = sum(is.na(x))
  )
}), .SDcols = num_cols]

# Transpose for clean readability
print(t(numeric_distributions))
                                     

#NO: plot var-outcome & biV; redo merged_gp if necessary
#NO: merged_final: Add on final set of var and last mdif (inc. char, numeric)
#NO: merged_ignore: CHECK corr, naniar and drymice; rmv var/cases: obvious rmv (no value in observation) and more strategic rmv (influx-outflux); save merged_ignore
#NO: merged_imputed and compare_inc_imp.R: imp model, beware IA/non-linear, aux var, squeeze, post and passive imputation (trsf var e.g. BMI). sensitivity anal (MNAR). Data leak (ignore). save merged_imputed
#NO: imputation dx (inc. Table1Imputed/NonImputed, density, strip) - warnings - logged events - FMI/LAMBDA ...

#merged_listwise complete cases - compare included-full sample using zombie_process_for_full.R and compare_inc_full.R; calculate attrition weights if necessary
merged_listwise <- na.omit(merged_gp)

#NO: pre-anal C/S multivar, easy lgtd (survival instead of cmprsk)/easy ML (glmnet)
#NO: reiterate step1 based on checks and pre-tests (e.g. fmi -> different grouping, remove)

#merged_sensit for future sensitivity analyses; save merged_sensit
#Pregnancy; COVID; anti_cohort of 6, 12, 18M; Age of the woman
