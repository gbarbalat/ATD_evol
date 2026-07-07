rm(list=ls())

library(haven)
library(data.table)
library(dplyr)
library(lubridate)

# read file ----
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


#merged_ create cohort ----
merged_[, id := stringi::stri_c(BEN_NIR_PSA, "_", BEN_RNG_GEM)]

# Filter id for whom there is at least one ATD
# 1. rows where the ATC class starts with N06A or N06C (ATD or ATD+)
# 2. Extract only the unique 'id' values from those rows
matching_ids <- unique(merged_[PHA_ATC_CLA %like% "^N06A|^N06C", id])

# 1. Set the key (indexes the data by ID instantly)
setkey(merged_, id)

# 2. Filter using the indexed key (blistering fast)
merged_ <- merged_[.(matching_ids)]

colnames(merged_)
colSums(is.na(merged_))
unique(merged_$PHA_ATC_LIB)
ATD <- c( "ESCITALOPRAM", "MILNACIPRAN", "SERTRALINE", "TIANEPTINE", "VENLAFAXINE", "PAROXETINE",
          "MIRTAZAPINE", "FLUOXETINE", "CLOMIPRAMINE", "CITALOPRAM",  "MIANSERINE", "MOCLOBEMIDE", "FLUVOXAMINE")

# merged_add_select_filter_recode ----
#Add on obvious var, obvious select, filter (excl criteria) & recode (e.g. G027B=Citizen, S022= Year + Month) inc. na_if, make categ; Explore NA/distributions; 
merged_add_select_filter_recode <- merged_ %>% 
  select(-BEN_NIR_PSA, -BEN_RNG_GEM)
#for each id, make the long wide for each prescription 
# Convert to data.table if it isn't one already
setDT(merged_add_select_filter_recode)
# Collapse to one row per id and date group, creating the 'nrows' column
# merged_add_select_filter_recode <- merged_add_select_filter_recode[, c(
#   .(nrows = .N),               # Create the count column
#   lapply(.SD, first)           # Grab the first row's value for all other columns
# ), by = .(id, EXE_SOI_DTD)]

#recode medication class
# Assign labels based on the start of the ATC code string
merged_add_select_filter_recode[, Rx_class := fcase(
  startsWith(PHA_ATC_CLA, "N05AN01"), "Lithium",
  startsWith(PHA_ATC_CLA, "N05A"),    "Antipsychotics (excl. Lithium)",
  startsWith(PHA_ATC_CLA, "N05B"),    "Anxiolytics",
  startsWith(PHA_ATC_CLA, "N05C"),    "Hypnotics and Sedatives",
  startsWith(PHA_ATC_CLA, "N06A"),    "Antidepressants",
  startsWith(PHA_ATC_CLA, "N06BA"),   "Stimulants",
  startsWith(PHA_ATC_CLA, "N06C"),    "Antidepressants+",
  
  startsWith(PHA_ATC_CLA, "N03A"),    "Antiepileptics",
  default = "Other"
)]
table(merged_add_select_filter_recode$Rx_class, useNA = "always")

#Filter out individuals where their first prescription is an antiepileptic, antipsychotic or a stimulant
setDT(merged_add_select_filter_recode)

# 1. Identify the 'id's whose absolute first prescription matches the exclusions
excluded_ids <- merged_add_select_filter_recode[
  order(EXE_SOI_DTD),                    # Sort chronologically by dispense date
  .(first_atc = PHA_ATC_CLA[1]),         # Extract the very first ATC code
  by = id
][
  # Filter this lookup table for the forbidden starting codes
  first_atc %like% "^N03A|^N05A|^N06BA", 
  id                                     # Keep only the vector of IDs
]

# 2. Remove these individuals completely from your main dataset
merged_excl_1 <- merged_add_select_filter_recode[(id %in% excluded_ids)] %>%
  select(id, EXE_SOI_DTD, PHA_ATC_LIB, PHA_SUB_DOS)
setDT(merged_excl_1)
setorder(merged_excl_1, EXE_SOI_DTD)
first_records <- merged_excl_1[, .SD[1], by = id]
#which meds
unique(first_records$PHA_ATC_LIB)
#low dose OLA or QUE?
OLA_first <- first_records %>% filter(PHA_ATC_LIB == "OLANZAPINE")
QUE_first <- first_records %>% filter(PHA_ATC_LIB == "QUETIAPINE" & PHA_SUB_DOS==25)

merged_add_select_filter_recode2 <- merged_add_select_filter_recode[!(id %in% excluded_ids)] %>% 
  distinct(id,PHA_PRS_C13, EXE_SOI_DTD, PRE_PRE_DTD, PHA_ACT_QSN, .keep_all=T) %>%
  mutate(
    window_start = as.Date(EXE_SOI_DTD) - days(3),
    window_end   = as.Date(EXE_SOI_DTD) + days(3)
  ) %>%
  group_by(id, PHA_PRS_C13, EXE_SOI_DTD) %>%
  mutate(
    # Save all dates matching this group as a list element
    # EXE_SOI_DTD_l  = list(EXE_SOI_DTD),
    # EXE_SOI_DTD  = first(EXE_SOI_DTD),
    
    # Get all unique quantities present inside this specific window
    unique_vals = list(unique(PHA_ACT_QSN)),
    unique_count = n_distinct(PHA_ACT_QSN)
  ) %>% ungroup() %>%
  mutate(
    PHA_ACT_QSN2 = case_when(
      # Rule 1: Just 1 unique value -> Set to unique_vals (and not 1)
      unique_count == 1 ~ sapply(unique_vals, function(x) x[1]),
      unique_count >= 2 ~ sapply(unique_vals, function(x) sum(x, na.rm = TRUE)),
      
      # # Rule 2: Exactly 2 unique values -> Keep the one that is NOT negative
      # unique_count == 2 ~ sapply(unique_vals, function(x) x[x >= 0][1]),
      # 
      # # Rule 3: 3 or more unique values -> Sum up all the unique values
      # unique_count >= 3 ~ sapply(unique_vals, function(x) sum(x, na.rm = TRUE))
    )
  )

## checks ----
# 1. Identify the unique combinations of id and PHA_PRS_ATC that meet your criteria
target_groups <- merged_add_select_filter_recode2 %>%
  filter(unique_count %in% c(2, 3)) %>%
  distinct(id, PHA_PRS_C13)

# 2. Extract all rows for those matching id and PHA_PRS_ATC pairs to create the 'tmp' database
tmp <- merged_add_select_filter_recode2 %>%
  # Semi-join acts as a filtering join, keeping rows that match target_groups keys perfectly
  semi_join(target_groups, by = c("id", "PHA_PRS_C13")) %>%
  # Select and arrange the specific columns you want to view/keep
  select(id, PHA_PRS_C13, unique_vals, PHA_ACT_QSN2, EXE_SOI_DTD) %>%
  arrange(id, PHA_PRS_C13, as.Date(EXE_SOI_DTD))


table(merged_add_select_filter_recode2$PHA_ATC_LIB, useNA = "always")
table(merged_add_select_filter_recode2$PHA_FRM_LIB, useNA = "always")
table(merged_add_select_filter_recode2$PHA_ACT_QSN2, useNA = "always")
table(merged_add_select_filter_recode2$PHA_UPC_NBR, useNA = "always")
unique_couples <- merged_add_select_filter_recode2 %>%
  # Filter for rows matching your exact formulation descriptions
  #filter(PHA_FRM_LIB %in% c("SOLUTION", "SUSPENSION", "")) %>%
  # Select only the columns you want to pair up
  select(PHA_FRM_LIB, PHA_ATC_LIB, PHA_SUB_DOS, PHA_UPC_NBR, PHA_ACT_QSN2) %>%
  # Keep only the unique combinations
  distinct()
print(unique_couples)



# #Apply recommendations for negative PHA_ACT_QSN 
# neg_rows <- merged_add_select_filter_recode %>%
#   #filter(PHA_ACT_QSN < 0) %>%
#   mutate(
#     window_start = as.Date(EXE_SOI_DTD) - days(3),
#     window_end   = as.Date(EXE_SOI_DTD) + days(3)
#   ) %>%
#   select(id, PHA_PRS_C13, window_start, window_end) %>% #
#   distinct()

# # 2. Join the main dataset to the windows to find all records within the brackets
# matched_windows <- merged_add_select_filter_recode %>% #filter(id=="BZzWge3AcIQM0xJRZ_1") %>%
#   mutate(EXE_SOI_DTD = as.Date(EXE_SOI_DTD)) %>%
#   left_join(
#     neg_rows, 
#     by = join_by(
#       id, 
#       PHA_PRS_C13, 
#       #EXE_SOI_DTD,
#       EXE_SOI_DTD >= window_start, 
#       EXE_SOI_DTD <= window_end
#     )
#   ) %>%
#   group_by(id, PHA_PRS_C13) %>%
#   mutate(
#     # Indicate 1 if within the window boundaries, 0 otherwise
#     is_within_window = if_else(!is.na(window_start), 1, 0),
#     
#     # Generate a specific number that updates each time a row moves inside/outside a window block
#     specific_group_number = consecutive_id(is_within_window)
#   ) %>%
#   ungroup()

# # 3. Calculate your window metrics and evaluate the rules
# window_summaries <- matched_windows %>%
#   group_by(id, PHA_PRS_C13, specific_group_number) %>% #EXE_SOI_DTD
#   summarise(
#     # Save all dates matching this group as a list element
#     EXE_SOI_DTD_l  = list(EXE_SOI_DTD),
#     EXE_SOI_DTD  = first(EXE_SOI_DTD),
#     
#     # Get all unique quantities present inside this specific window
#     unique_vals = list(unique(PHA_ACT_QSN)),
#     unique_count = n_distinct(PHA_ACT_QSN),
#     .groups = "drop"
#   ) %>%
#   mutate(
#     PHA_ACT_QSN2 = case_when(
#       # Rule 1: Just 1 unique value -> Set to unique_vals (and not 1)
#       unique_count == 1 ~ sapply(unique_vals, function(x) x[1]),
#       unique_count >= 2 ~ sapply(unique_vals, function(x) sum(x, na.rm = TRUE)),
#       
#       # # Rule 2: Exactly 2 unique values -> Keep the one that is NOT negative
#       # unique_count == 2 ~ sapply(unique_vals, function(x) x[x >= 0][1]),
#       # 
#       # # Rule 3: 3 or more unique values -> Sum up all the unique values
#       # unique_count >= 3 ~ sapply(unique_vals, function(x) sum(x, na.rm = TRUE))
#     )
#   )
# 
# # 4. Merge the new calculated values back onto the master dataset
# merged_add_select_filter_recode2 <- merged_add_select_filter_recode %>%
#   left_join(
#     window_summaries %>% select(id, PHA_PRS_C13, EXE_SOI_DTD, EXE_SOI_DTD_l, specific_group_number, PHA_ACT_QSN2),
#     by = c("id", "PHA_PRS_C13", "EXE_SOI_DTD")
#   ) %>%
#   # For all non-negative rows, fallback to their original value
#   mutate(PHA_ACT_QSN2 = if_else(PHA_ACT_QSN2<=0, 0, PHA_ACT_QSN2)) #%>% #or remove those lines?






#recode formulation (PHA_FRM_LIB) as injection vs. non-injection 
#No injection in PHA_FRM_LIB
merged_add_select_filter_recode2$PHA_FRM_LIB <- "NonInjection"

## IDP ----
#Apply Individualized dispensing pattern method
stop()
Attention ---- 
source("./sasdata1/IDP.R")
colnames(merged_add_select_filter_recode2)

# Execute the classic IDP algorithm across the cohort matrix
final_episodes <- run_classic_idp_dplyr (df=merged_add_select_filter_recode2, 
                 product_var = "PHA_PRS_C13", 
                 quantity_var = "PHA_ACT_QSN2", 
                 date_var = "EXE_SOI_DTD")
  

#merged_gp: Add on new set of var; Group/arrange levels based on 30-2% per level & not too many levels (<7) & further steps
#explore with tables, NA, na_if
#gp variables if necessary
merged_gp <- merged_add_select_filter_recode2[final_episodes, on = "id"]

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
