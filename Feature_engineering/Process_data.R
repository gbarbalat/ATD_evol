# flowchart ----
library(DiagrammeR)

# Create the flowchart using Graphviz DOT language
flowchart_code <- "
digraph cohort_flowchart {
  
  # Graph setup for top-to-bottom layout
  rankdir=TB;
  node [shape = box, style = 'rounded,filled', fillcolor = '#F8F9FA', color = '#2C3E50', fontname = 'Helvetica', fontsize = 12, margin = 0.3];
  edge [fontname = 'Helvetica', fontsize = 10, color = '#2C3E50'];

  # Define Nodes
  box1 [label = 'Women 18-39 with SSRI\\n2022-2023', fillcolor = '#EBF5FB'];
  
  box2 [label = 'Women 18-39 with first SSRI\\n2022-2023', fillcolor = '#EBF5FB'];
  
  # Invisible intermediate port on the vertical line for the horizontal arrow to branch from
  mid_point [shape = point, width = 0, height = 0, label = ''];

  exclusion [label = '- Psychotropic medication within the year,\\n- Antiepileptics, antipsychotics, lithium\\n  within the first 30 days after SSRI initiation', 
             shape = box, style = 'rounded,filled', fillcolor = '#FDEDEC', color = '#E74C3C', fontname = 'Helvetica', fontsize = 11];

  # Define Strict Vertical Flow
  box1 -> mid_point [arrowhead = none, weight = 10];
  mid_point -> box2 [weight = 10];
  
  # Horizontal Red Exclusion Arrow branching from the vertical path
  edge [style = solid, color = '#E74C3C', constraint = false];
  mid_point -> exclusion [label = ''];

  # Force exact horizontal alignment between the midpoint on the arrow and the exclusion box
  { rank = same; mid_point; exclusion; }
}
"

# Render the flowchart
grViz(flowchart_code)


rm(list=ls())

library(haven)
library(data.table)
library(dplyr)
library(lubridate)
library(stringr)
library(purrr)
library(ggplot2)
library(mstate)

# Antipsychotics
APsych <- c(
  "AMISULPRIDE", "ARIPIPRAZOLE", "CLOZAPINE", "OLANZAPINE", 
  "QUETIAPINE", "RISPERIDONE", "SULPIRIDE", "TIAPRIDE"
)

# Antidepressants
ATD <- c(
  "CITALOPRAM", "CLOMIPRAMINE", "ESCITALOPRAM", "FLUOXETINE", 
  "FLUVOXAMINE", "MILNACIPRAN", "MIRTAZAPINE", "MOCLOBEMIDE", 
  "PAROXETINE", "SERTRALINE", "TIANEPTINE", "VENLAFAXINE"
)

# Antiepileptics / Mood Stabilizers
AEpi <- c(
  "ACIDE VALPROIQUE", "CARBAMAZEPINE", "GABAPENTINE", "LAMOTRIGINE", 
  "LEVETIRACETAM", "OXCARBAZEPINE", "TOPIRAMATE", "VALPROIQUE ACIDE"
)

# Anxiolytics
Anx <- c(
  "ALPRAZOLAM", "BROMAZEPAM", "DIAZEPAM", "HYDROXYZINE", 
  "LORAZEPAM", "PRAZEPAM"
)

# Hypnotics and Sedatives
HypSed <- c(
  "LOPRAZOLAM", "LORMETAZEPAM", "ZOLPIDEM", "ZOPICLONE"
)

#merged_checks_recode ----
#explore #cols, col names, unique values, tables, NA/distributions; NA in ID and col; 
#obvious recode (1,2,3 to More than etc ... inc. na_if, make categ)

merged_checks_recode <- read_sas("./sasdata1/merged_checks_recode6.sas7bdat") 
glimpse(merged_checks_recode)

#recode First Prescriber
merged_checks_recode <- merged_checks_recode %>%
  mutate(First_Prescriber = case_when(First_Prescriber %in% c(1,22,23) ~ "GP",
                                      First_Prescriber %in% c(17,33,75) ~ "Psych",
                                      TRUE ~ "Other"))

#Recode empty events as Cens
merged_checks_recode <- merged_checks_recode %>%
  mutate(event = case_when(
    event == "" ~ "Cens",
    TRUE ~ event
  ))

#Recode empty character cells as NA 
merged_checks_recode <- merged_checks_recode %>%
  mutate(across(where(is.character), ~ na_if(trimws(.), "")))

glimpse(merged_checks_recode)
date_id_too_many_col <- c("BEN_IDT_ANO", "MAX_TRT_DTD", "BEN_DCD_DTE", "DT_FIRST_AD", "last_pickup_dt", "psy_meds")
lapply(merged_checks_recode %>% select(-all_of(date_id_too_many_col)), unique)
colSums(is.na(merged_checks_recode))
merged_checks_recode %>%
  count(First_Prescriber, sort = TRUE)

# Identify non-numeric columns
non_numeric_cols <- merged_checks_recode %>% 
  select(-all_of(date_id_too_many_col)) %>%
  select(where(~ !is.numeric(.))) %>% 
  names()

# Loop through and print frequency tables including NA counts
for (col in non_numeric_cols) {
  cat("\n==============================\n")
  cat("Percentage Table for:", col, "\n")
  cat("==============================\n")
  
  # Convert to percentage and round to 2 decimal places for readability
  pct_table <- prop.table(table(merged_checks_recode[[col]], useNA = "always")) * 100
  print(round(pct_table, 2))
}

# Summary statistics for all numeric columns
numeric_summary <- merged_checks_recode %>% 
  select(-all_of(date_id_too_many_col)) %>%
  select(where(is.numeric)) %>% 
  summary()

print(numeric_summary)

(id_high_refill <- merged_checks_recode %>%
  filter(refill_Nb==88) %>% 
  pull(BEN_IDT_ANO) %>% unique)

(id_high_cumulAnx<- merged_checks_recode %>%
  filter(CumulAnx==29) %>% 
  pull(BEN_IDT_ANO) %>% unique)

id_high_cumulOtherMeds<- merged_checks_recode %>%
  filter(CumulOtherMeds==30) %>% 
  pull(BEN_IDT_ANO) %>% unique

(id_high_cumulPsych<- merged_checks_recode %>%
  filter(CumulPsych==50) %>% 
  pull(BEN_IDT_ANO) %>% unique)

# Identify numeric columns
numeric_cols <- merged_checks_recode %>% 
  select(-all_of(date_id_too_many_col)) %>%
  select(where(is.numeric)) %>% 
  names()

# Generate histograms for each numeric column
for (col in numeric_cols) {
  p <- ggplot(merged_checks_recode, aes(x = .data[[col]])) +
    geom_histogram(bins = 30, fill = "#2c3e50", color = "white") +
    theme_minimal() +
    labs(
      title = paste("Histogram of", col), 
      x = col, 
      y = "Frequency"
    )
  
  print(p)
}

#make numeric categorical
# Find BEN_IDT_ANO where age is < 18 or > 39
excluded_ids <- merged_checks_recode %>%
  group_by(BEN_IDT_ANO) %>%
  filter(start == 0) %>%
  ungroup() %>%
  filter(BEN_AMA_COD < 18 | BEN_AMA_COD > 40) %>%
  pull(BEN_IDT_ANO)

age_merged_checks_recode <- merged_checks_recode %>%
  filter(BEN_IDT_ANO %in% excluded_ids)

#rmv these individuals and create categorical age
merged_checks_recode <- merged_checks_recode %>%
  filter(!BEN_IDT_ANO %in% excluded_ids) %>%
  # Recode age into categories
  mutate(BEN_AMA_COD_cat = case_when(
    BEN_AMA_COD >= 18 & BEN_AMA_COD < 25 ~ "18-24",
    BEN_AMA_COD >= 25 & BEN_AMA_COD < 30 ~ "25-29",
    BEN_AMA_COD >= 30 & BEN_AMA_COD < 35 ~ "30-34",
    BEN_AMA_COD >= 35 & BEN_AMA_COD <= 40 ~ "35-40",
    TRUE ~ NA_character_ # Assigns NA to any ages outside these specific ranges
  )) 

# Observations with Discordant BEN_AMA_COD 
ABerrant_BEN_AMA_COD <- merged_checks_recode  %>%
  group_by(BEN_IDT_ANO) %>%
  filter(BEN_AMA_COD < 18 | BEN_AMA_COD > 40) %>%
  arrange(BEN_IDT_ANO, start)


#look up individuals with neg time
inconsistent_ids <- merged_checks_recode %>%
  arrange(BEN_IDT_ANO, start) %>%
  group_by(BEN_IDT_ANO) %>%
  filter(stop<=0 | stop > 370) %>%
  pull(BEN_IDT_ANO) %>%
  unique() 


#Look up individuals with short difference between start and stop
# if difference btw start and stop is positive and less than 15
# find these individuals 
inconsistent_ids <- merged_checks_recode %>%
  filter((stop - start) > 0 & (stop - start) < 7 & stop<365) %>%
  pull(BEN_IDT_ANO) %>%
  unique()
Short_time_refill <- merged_checks_recode %>%
  filter(BEN_IDT_ANO %in% inconsistent_ids) %>%
  #filter((stop - start) > 0 & (stop - start) < 7 & stop<365) %>%
  mutate(diff=stop-start) %>%
  select(BEN_IDT_ANO, DT_FIRST_AD, start, stop,  diff, psy_meds, refill_Nb, event, MAX_TRT_DTD, BEN_DCD_DTE) 


#look up individuals that should have been marked as censored or dead
target_ids <- merged_checks_recode %>%
  group_by(BEN_IDT_ANO) %>%
  summarise(
    max_stop = max(stop, na.rm = TRUE),
    # Assuming these dates are constant per patient, take the first value
    DT_FIRST_AD = first(DT_FIRST_AD),
    BEN_DCD_DTE = first(BEN_DCD_DTE),
    MAX_TRT_DTD = first(MAX_TRT_DTD),
    .groups = "drop"
  ) %>%
  filter(
    max_stop < 365,
    BEN_DCD_DTE > DT_FIRST_AD + years(1),
    MAX_TRT_DTD > DT_FIRST_AD + years(1)
  ) %>%
  pull(BEN_IDT_ANO)


# make numeric categorical
numeric_to_categ_col <- c("refill_Nb", "CumulAnx", "CumulOtherMeds",
                          "CumulPsych", "P20_POP", "Nb_GP",
                          "Nb_Psych")

categorize_gamma_vars <- function(df, cols, probs = seq(0, 1, length.out = 5)) {
  
  for (col in cols) {
    # Extract the column data
    x <- df[[col]]
    
    # Compute explicit quantile thresholds
    cuts <- quantile(x, probs = probs, na.rm = TRUE)
    
    # Check for duplicate cutoffs (common with zero-inflated gamma variables)
    if (anyDuplicated(cuts) > 0) {
      message(sprintf("Note: Duplicate cutoffs found for '%s' due to ties/zeros. Using unique thresholds.", col))
      cuts <- unique(cuts)
    }
    
    # Automatically generate range-based labels from the cutoffs
    n_intervals <- length(cuts) - 1
    bin_labels <- character(n_intervals)
    
    for (i in 1:n_intervals) {
      lower <- cuts[i]
      upper <- cuts[i+1]
      
      # Format integers cleanly, or keep 1 decimal place for continuous metrics
      if (all(floor(cuts) == cuts, na.rm = TRUE)) {
        bin_labels[i] <- paste0(round(lower), "–", round(upper))
      } else {
        bin_labels[i] <- paste0(round(lower, 1), "–", round(upper, 1))
      }
    }
    
    # Create the new categorical column (e.g., length_of_stay_cat)
    new_col_name <- paste0(col, "_cat")
    
    df <- df %>%
      mutate(
        !!new_col_name := cut(
          !!sym(col), 
          breaks = cuts, 
          include.lowest = TRUE, 
          labels = bin_labels
        )
      )
    
    # Print out a clean mapping for your paper/supplement text
    cat(sprintf("\n--- Mapped Categories for %s ---\n", col))
    mapping_table <- data.frame(
      Interval = bin_labels,
      Lower_Bound = cuts[1:n_intervals],
      Upper_Bound = cuts[2:(n_intervals + 1)]
    )
    print(mapping_table)
  }
  
  return(df)
}

# Automatically find all columns ending with "_before" and transform them
merged_checks_recode2 <- merged_checks_recode %>%
  mutate(
    across(
      ends_with("_before"), 
      ~ if_else(!is.na(.), "Yes", "No")
    )
  )
table(merged_checks_recode2$AGE_HAD_before,useNA="always")

merged_checks_recode3 <- categorize_gamma_vars(merged_checks_recode2, numeric_to_categ_col,
                                        probs = seq(0, 1, length.out = 3)) 

# merged_find_gp ----

fn_merged_find_gp <- function(merged_find_gp, covar_set) {
  
  # Select only non-numeric variables
  non_numeric_df <- merged_find_gp %>%
    select(all_of(covar_set))
  
  # Loop through each non-numeric column to print counts and percentages
  for (col_name in names(non_numeric_df)) {
    cat("\n==============================\n")
    cat("Variable:", col_name, "\n")
    cat("==============================\n")
    
    # Calculate counts and proportions (percentages)
    counts <- table(non_numeric_df[[col_name]], useNA = "ifany")
    percentages <- prop.table(counts) * 100
    
    # Combine into a clean summary data frame
    summary_table <- data.frame(
      Level = names(counts),
      Count = as.numeric(counts),
      Percentage = round(as.numeric(percentages), 2)
    )
    
    print(summary_table, row.names = FALSE)
  }
  
}

#round 1
merged_find_gp <- merged_checks_recode3
glimpse(merged_find_gp)
covar_set <- c("First_Prescriber", select(merged_find_gp,all_of(starts_with("Prev_"))) %>% colnames(),
              "Pregnant", select(merged_find_gp,all_of(starts_with("Has"))) %>% colnames(),
              select(merged_find_gp,all_of(starts_with("Seen"))) %>% colnames(),
              select(merged_find_gp,all_of(starts_with("Adm_"))) %>% colnames(),
              "season_year", "region", "FDEP20_quint",
              select(merged_find_gp,all_of(ends_with("_before"))) %>% colnames(),
              select(merged_find_gp,all_of(ends_with("_cat"))) %>% colnames()
)
fn_merged_find_gp(merged_find_gp, covar_set)
  
#round 2
#group Prev RIP, HAD, SSR
#merged_find_gp$Prev_SeenNonMed <- NULL
merged_find_gp2 <- merged_find_gp %>%
  mutate(Prev_NotMCO=case_when((Prev_RIP_0=="Yes" |
                                 Prev_RIP_2=="Yes" |
                                 Prev_HAD=="Yes" |
                                 Prev_SSR=="Yes") ~ "Yes",
                               TRUE ~ "No"),
         
         Prev_ATMPInvAAH=case_when((Prev_ATMPInv=="Yes" |
                                      Prev_AAH=="Yes")  ~ "Yes",
                                   TRUE ~ "No"),
         
         HasATMPInvAAH=case_when((HasATMPInv=="Yes" |
                                    HasAAH=="Yes")  ~ "Yes",
                                 TRUE ~ "No"),
         
         Prev_Psy_Adm_2015_2022=case_when(Prev_Psy_Adm=="No" ~ "No",
                                 TRUE ~ "Yes")
         )
merged_find_gp2$FDEP20_quint <- as.character(merged_find_gp2$FDEP20_quint)
glimpse(merged_find_gp2)
covar_set2 <- c("First_Prescriber", "Prev_ALDNonPsy", "Prev_ALDPsy", "Prev_Anx", "Prev_ATMPInvAAH",
                "Prev_C2S", "Prev_MCO", "Prev_NotMCO", "Prev_Meds", "Prev_Pregnant", 
                "Prev_SeenGP", "Prev_SeenNonMed", "Prev_SeenOtherMed", "Prev_SeenPsych",
                "Prev_Psy_Adm_2015_2022", "Prev_Psy_Dx_Rx", 
                "Pregnant", "HasAnx", "HasOtherMeds", "HasATMPInvAAH", "HasALDPsy", "HasALDNonPsy",
                "HasC2S", "SeenGP", "SeenPsych", "SeenOtherMed", "SeenNonMed", 
                "Adm_Psy_Cur", "Adm_Oth_Cur", "season_year", "region", "FDEP20_quint")
fn_merged_find_gp(merged_find_gp2, covar_set2)


#plot var-outcome ----
categ_var <- c(covar_set2, "BEN_AMA_COD_cat")
num_var <- c( "CumulAnx", "CumulOtherMeds", "CumulPsych", "P20_POP", "refill_Nb",
             "Nb_GP", "Nb_Psych") #"BEN_AMA_COD",

library(ggplot2)

# 1. Boxplots for numeric variables (X = event)
for (v in num_var) {
  p <- ggplot(merged_find_gp2, aes(x = event, y = .data[[v]])) +
    geom_boxplot(fill = "skyblue", outlier.alpha = 0.6) +
    coord_cartesian(ylim = c(0, 50)) +  # Sets the Y-axis limits from 0 to 10
    labs(
      title = paste("Boxplot of", v, "by Event"),
      x = "Event",
      y = v
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold", hjust = 0.5))
  
  print(p)
}

# 2. Column charts for categorical variables (X = event, fill = category)
for (v in categ_var) {
  p <- ggplot(merged_find_gp2, aes(x = event, fill = .data[[v]])) +
    geom_bar(position = "dodge") + # Use position = "fill" if you prefer proportions (0 to 1)
    labs(
      title = paste("Distribution of", v, "by Event"),
      x = "Event",
      y = "Count",
      fill = v
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5),
      axis.text.x = element_text(angle = 30, hjust = 1)
    )
  
  print(p)
}


# merged_gp ----
merged_gp <- merged_find_gp2 %>%
  select(BEN_IDT_ANO, start, stop, DT_FIRST_AD, last_pickup_dt,
         all_of(num_var), all_of(categ_var),
         event, psy_meds)

colSums(is.na(merged_gp))

# Loop through and print frequency tables including NA counts
for (col in c(categ_var, "event")) {
  cat("\n==============================\n")
  cat("Percentage Table for:", col, "\n")
  cat("==============================\n")
  
  # Convert to percentage and round to 2 decimal places for readability
  pct_table <- prop.table(table(merged_gp[[col]], useNA = "always")) * 100
  print(round(pct_table, 2))
}

# Summary statistics for all numeric columns
numeric_summary <- merged_gp %>% 
  select(all_of(num_var)) %>% 
  summary()
print(numeric_summary)

# Generate histograms for each numeric column
for (col in num_var) {
  p <- ggplot(merged_gp, aes(x = .data[[col]])) +
    geom_histogram(bins = 30, fill = "#2c3e50", color = "white") +
    theme_minimal() +
    labs(
      title = paste("Histogram of", col), 
      x = col, 
      y = "Frequency"
    )
  
  print(p)
}
