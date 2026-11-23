rm(list=ls())

library(haven)
library(data.table)
library(dplyr)
library(lubridate)
library(stringr)
library(purrr)
library(ggplot2)
library(survival)

grace <- 45
LM_start <- 0 
LM_end <- 365 
imputation_on <- T
clean <- FALSE
LM_end_anal <- "_lastpu_" #"_lastpu_" "_lastatd_" "_lastsri_" 
filename <- paste0("./sasdata1/merged_mult" , LM_end_anal , grace, ".sas7bdat")# 

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

merged_checks_recode <- read_sas(filename) 

if (clean) {
  glimpse(merged_checks_recode)
  date_id_too_many_col <- c("ben_idt_ano", "BEN_RES_DPT", "MAX_TRT_DTD", "BEN_DCD_DTE", #"BEN_RES_COM","depcom",, "next_exe_date", "EXE_SOI_DTD"
                            #"PHA_ATC_CLA",  "PHA_ATC_LIB", "net_qsn", "PHA_FRM_LIB", "PSP_SPE_COD" ,
                            #"PSP_ACT_NAT", "RGO_ASU_NAT", "RGM_COD", "RGM_GRG_COD" ,
                            #"Lead_Prescriber", "_prev_psp", 
                            #"all_n06ab", "all_n06a", "has_n06ab", 
                            "DT_FIRST_AD",  "psy_meds")
  lapply(merged_checks_recode %>% select(-all_of(date_id_too_many_col)), unique)
  colSums(is.na(merged_checks_recode))
  merged_checks_recode %>%
    count(PSP_SPE_COD, sort = TRUE)
  View(merged_checks_recode)
  tmp <- merged_checks_recode %>%
    select(ben_idt_ano, DT_FIRST_AD, BEN_DCD_DTE, MAX_TRT_DTD, calc_stop, RIP_0_Length, CumulAnx, CumulOtherMeds, CumulGP,
           CumulNonMed, CumulOtherMed, CumulPsych) #%>% filter(BEN_IDT_ANO=="B--Cu_dnPMU7V2awV")
  
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
}

#recode CRTO variables
merged_checks_recode <- merged_checks_recode %>%
  mutate(
    TPS_SED = {
      # 1. Extract all TPS_ANX_ and TPS_HYP_ columns and convert non-"No" values to numeric
      mat <- across(
        starts_with(c("TPS_ANX_", "TPS_HYP_")),
        ~ suppressWarnings(as.numeric(as.character(.x)))
      )
      
      # 2. Compute row-wise max ignoring NAs (which represent "No")
      max_val <- do.call(pmax, c(mat, list(na.rm = TRUE)))
      
      # 3. Return "No" if all columns were "No" (or NA), otherwise the max value as character
      if_else(is.na(max_val), "No", as.character(max_val))
    }, 
    
    TPS_ADR = {
      mat <- across(
        starts_with(c("TPS_ADR")),
        ~ suppressWarnings(as.numeric(as.character(.x)))
      )
      
      max_val <- do.call(pmax, c(mat, list(na.rm = TRUE)))
      
      if_else(is.na(max_val), "No", as.character(max_val))
    }, 
    
    TPS_NLE = {
      mat <- across(
        starts_with(c("TPS_NLE")),
        ~ suppressWarnings(as.numeric(as.character(.x)))
      )
      
      max_val <- do.call(pmax, c(mat, list(na.rm = TRUE)))
      
      if_else(is.na(max_val), "No", as.character(max_val))
    }, 
    
    PSY_ADD_AU = {
      mat <- across(
        starts_with(c("PSY_ADD_ALC", "PSY_ADD_CNB", "PSY_ADD_AUT")),
        ~ suppressWarnings(as.numeric(as.character(.x)))
      )
      
      max_val <- do.call(pmax, c(mat, list(na.rm = TRUE)))
      
      if_else(is.na(max_val), "No", as.character(max_val))
    }, 
    
    PSY_PSC_BIP = {
      mat <- across(
        starts_with(c("PSY_PSC_IND", "PSY_TNH_BIP")),
        ~ suppressWarnings(as.numeric(as.character(.x)))
      )
      
      max_val <- do.call(pmax, c(mat, list(na.rm = TRUE)))
      
      if_else(is.na(max_val), "No", as.character(max_val))
    }, 
    
    PSY_DEP_NEV = {
      mat <- across(
        starts_with(c("PSY_TNH_NEV", "PSY_TNH_DEP")),
        ~ suppressWarnings(as.numeric(as.character(.x)))
      )
      
      max_val <- do.call(pmax, c(mat, list(na.rm = TRUE)))
      
      if_else(is.na(max_val), "No", as.character(max_val))
    }, 
    
    PSY_AU = {
      mat <- across(
        starts_with(c("PSY_AUT_IND", "PSY_DME_IND", "PSY_ENF_IND")),
        ~ suppressWarnings(as.numeric(as.character(.x)))
      )
      
      max_val <- do.call(pmax, c(mat, list(na.rm = TRUE)))
      
      if_else(is.na(max_val), "No", as.character(max_val))
    }, 
  )


merged_checks_recode <- merged_checks_recode %>%
  mutate(
    across(
      starts_with(c("TPS_","PSY_", "Prev_Psy_Adm"), ignore.case = F),
      ~ if_else(
        .x == "No",
        "No",
        as.character(year(DT_FIRST_AD) - as.numeric(.x))
      )
    )
  )  

#recode First Prescriber, and remove NA in First_prescriber (2 occurences DPN_QLF issue: No First prescriber as start is not 0 on the db)
merged_checks_recode <- merged_checks_recode %>%
  filter(!is.na(PSP_SPE_COD)) %>%
  mutate(First_Prescriber = case_when(PSP_SPE_COD %in% c(1,22,23) ~ "GP",
                                      PSP_SPE_COD %in% c(17,33,75) ~ "Psych",
                                      TRUE ~ "Other"))

#Recode empty character cells as NA
merged_checks_recode <- merged_checks_recode %>%
  mutate(across(where(is.character), ~ na_if(trimws(.), "")))

#filter out BEN_RES_DPT="991" 2 individuals
id_overseas <- merged_checks_recode %>%
  filter(BEN_RES_DPT=="991") %>%
  pull(BEN_IDT_ANO) %>% unique
merged_checks_recode <- merged_checks_recode %>%
  filter(!BEN_IDT_ANO %in% id_overseas)




# Find BEN_IDT_ANO where age is < 18 or > 39
excluded_ids <- merged_checks_recode %>%
  group_by(BEN_IDT_ANO) %>%
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


if (clean) {
  # Observations with Discordant BEN_AMA_COD 
  ABerrant_BEN_AMA_COD <- merged_checks_recode  %>%
    group_by(BEN_IDT_ANO) %>%
    filter(BEN_AMA_COD < 18 | BEN_AMA_COD > 40) %>%
    arrange(BEN_IDT_ANO)
  
  
  #look up individuals with neg time
  inconsistent_ids <- merged_checks_recode %>%
    arrange(BEN_IDT_ANO) %>%
    group_by(BEN_IDT_ANO) %>%
    filter(calc_stop<0 | calc_stop > 370) %>%
    pull(BEN_IDT_ANO) %>%
    unique() 
  summary(merged_checks_recode$calc_stop)
  
  #look up individuals (BEN_IDT_ANO) that should be marked as censored or dead
  #in merged_checks_recode
  #those where calc_stop + grace < MAX_TRT_DTD or BEN_DCD_DTE
  censored_or_dead_ids <- merged_checks_recode %>%
    filter(
      (!is.na(MAX_TRT_DTD) & (calc_stop + grace > as.numeric(MAX_TRT_DTD-DT_FIRST_AD))) |
        (!is.na(BEN_DCD_DTE) & (calc_stop + grace > as.numeric(BEN_DCD_DTE-DT_FIRST_AD)))
    ) %>%
    select(BEN_IDT_ANO, calc_stop, DT_FIRST_AD, MAX_TRT_DTD,BEN_DCD_DTE)
  
  # View just their IDs or the full rows
  head(censored_or_dead_ids)
  
}

# make numeric categorical
numeric_to_categ_col <- c( "CumulAnx", "CumulOtherMeds",
                           "CumulGP","CumulNonMed", "CumulOtherMed", "CumulPsych",
                           "P20_POP", "Nb_GP","Nb_Psych")


merged_checks_recode2 <- merged_checks_recode 
rm(merged_checks_recode)
table(merged_checks_recode2$HAD_Length,useNA="always")

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
merged_checks_recode3 <- categorize_gamma_vars(merged_checks_recode2, numeric_to_categ_col,
                                               probs = seq(0, 1, length.out = 10)) 
#do not categorize, use numeric variables as is
merged_checks_recode3 <- merged_checks_recode2
rm(merged_checks_recode2)

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
rm(merged_checks_recode3)
glimpse(merged_find_gp)
covar_set <- c("First_Prescriber",
               
               #select(merged_find_gp,all_of(starts_with("Cumul"))) %>% colnames(),
               
               select(merged_find_gp,all_of(c(starts_with("PSY_",ignore.case = F),starts_with("TPS_")))) %>% colnames(),
               
               "Pregnant", select(merged_find_gp,all_of(starts_with("Has"))) %>% colnames(),
               
               select(merged_find_gp,all_of(starts_with("Length_"))) %>% colnames(),
               
               "season_year", "region", "FDEP20_quint",
               
               select(merged_find_gp,all_of(ends_with("_cat"))) %>% colnames() #includes BEN_AMA_COD (age)
)
fn_merged_find_gp(merged_find_gp, covar_set)

#round 2
merged_find_gp2 <- merged_find_gp %>%
  group_by (BEN_IDT_ANO) %>%
  
  mutate(
    RIP_Length = if_else(
      row_number() == 1,
      # First row per patient: 1 if any equals 1, 0 if all equal 0
      as.integer(RIP_0_Length == 1 | RIP_2_Length == 1),
      # Second row onward: 1 if any >= 0, 0 if all < 0
      as.integer(RIP_0_Length >= 0 | RIP_2_Length >= 0)
    ),
    
    MCO_SSR_HAD_Length = if_else(
      row_number() == 1,
      # First row per patient: 1 if any equals 1, 0 if all equal 0
      as.integer(MCO_Length == 1 | SSR_Length == 1 | HAD_Length == 1),
      # Second row onward: 1 if any >= 0, 0 if all < 0
      as.integer(MCO_Length >= 0 | SSR_Length >= 0 | HAD_Length >= 0)
    )
  ) %>% ungroup() %>%
  
  mutate(
    HasATMPInvAAH=case_when((HasATMPInv=="Yes" |
                               HasAAH=="Yes")  ~ "Yes",
                            TRUE ~ "No")
    
  ) %>%
  mutate(
    across(
      starts_with(c("PSY_", "TPS_", "Prev_Psy"),ignore.case = F),
      ~ if_else(.x == "No", "No", "Yes", missing = "Yes")
    )
  ) %>%
  mutate(
    # 1. Create PSY_PSC_BIP_NLE
    PSY_PSC_BIP_NLE = case_when(
      # If either is "Yes" (handling NA safely), return "Yes"
      coalesce(TPS_NLE == "Yes", FALSE) | coalesce(PSY_PSC_BIP == "Yes", FALSE) ~ "Yes",
      # Otherwise return "No"
      TRUE ~ "No"
    ),
    
    PSY_DEP_NEV_ADR_SED = case_when(
      # If either is "Yes" (handling NA safely), return "Yes"
      coalesce(TPS_ADR == "Yes", FALSE) | coalesce(TPS_SED == "Yes", FALSE) | coalesce(PSY_DEP_NEV == "Yes", FALSE) ~ "Yes",
      # Otherwise return "No"
      TRUE ~ "No"
    ),
    
    # 2. Create PSY_ADD
    PSY_ADD = case_when(
      # If either is "Yes" (handling NA safely), return "Yes"
      # Note: Assuming typo in request "PSY_ASS_TAB" intended to be "PSY_ADD_TAB" based on previous context.
      # If it truly is PSY_ASS_TAB, change it back below.
      coalesce(PSY_ADD_TAB == "Yes", FALSE) | coalesce(PSY_ADD_AU == "Yes", FALSE) ~ "Yes",
      # Otherwise return "No"
      TRUE ~ "No"
    )
  )
merged_find_gp2$FDEP20_quint <- as.character(merged_find_gp2$FDEP20_quint)
glimpse(merged_find_gp2)
covar_set2 <- c("First_Prescriber", 
                
                "HasALDNonPsy", "HasALDPsy", "HasATMPInvAAH","HasC2S",
                
                #select(merged_find_gp,all_of(ends_with("_cat"))) %>% colnames(),
                
                "PSY_DEP_NEV_ADR_SED",
                "PSY_PSC_BIP_NLE",#"PSY_PSC_BIP"
                # "TPS_NLE","TPS_ADR","TPS_SED",
                "PSY_ADD","PSY_AU", #"PSY_ADD_TAB","PSY_ADD_AU",
                "Prev_Psy_Adm",
                
                "MCO_SSR_HAD_Length", "RIP_Length",
                
                "Pregnant", 
                "BEN_AMA_COD_cat",
                
                "season_year", "region", "FDEP20_quint")
fn_merged_find_gp(merged_find_gp2, covar_set2)
rm(merged_find_gp)

#plot var-outcome ----
categ_var <- c(covar_set2)
num_var <- c( 
  "CumulAnx", "CumulOtherMeds",
  "CumulPsych",   "CumulGP",  "CumulOtherMed",  "CumulNonMed",
  
  "P20_POP","Nb_GP", "Nb_Psych") #"BEN_AMA_COD",

if (clean) {
  
  #too computationnally intensive
  # for (v in num_var) {
  #   p <- ggplot(merged_find_gp2, aes(x = .data[[v]], y = calc_stop)) +
  #     geom_smooth(method = "lm", color = "blue", fill = "lightblue", se = F) + # LOESS curve + confidence band
  #     labs(
  #       y = "Calc_stop",
  #       x = v
  #     ) +
  #     theme_minimal() +
  #     theme(plot.title = element_text(face = "bold", hjust = 0.5))
  #   
  #   print(p)
  # }
  
  # 2. Column charts for categorical variables (X = event, fill = category)
  for (v in categ_var) {
    p <- ggplot(merged_find_gp2, aes(x = .data[[v]], y = calc_stop)) +
      geom_boxplot(fill = "skyblue", outlier.alpha = 0.6) + # Fixed geom and arguments
      labs(
        y = "Calc_stop",
        x = v
      ) +
      theme_minimal() +
      theme(plot.title = element_text(face = "bold", hjust = 0.5))
    
    
    print(p)
  }
}

# merged_gp ----
merged_gp <- merged_find_gp2 %>%
  select(BEN_IDT_ANO, BEN_RES_DPT, calc_stop, stop, start, DT_FIRST_AD,
         BEN_DCD_DTE, MAX_TRT_DTD,
         all_of(categ_var),all_of(num_var), 
         psy_meds, event) %>%
  mutate(calc_stop = calc_stop + grace + 1,
         stop = coalesce(calc_stop, as.numeric(.data$stop))
         )
rm(merged_find_gp2)
colSums(is.na(merged_gp))

if (clean) {
  # Loop through and print frequency tables including NA counts
  for (col in c(categ_var)) {
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
}

# merged_imputed ----
if (imputation_on) {
#impute missing Nb_GP, Nb_Psych, FDEP and P20
denb_summary <- read_sas("./rfcommun/denb_ps_commune_01jan2022.sas7bdat") %>%
  group_by(DEP) %>%
  dplyr::summarize(
    Nb_GP_imp = mean(if_else(SPE %in% c("01", "22", "23"), NB_PS, 0), na.rm = TRUE),
    Nb_Psych_imp = mean(if_else(SPE %in% c("17", "33", "75"), NB_PS, 0), na.rm = TRUE),
    .groups = "drop"
  )

get_mode <- function(v, na.rm = TRUE) {
  if (na.rm) {
    v <- na.omit(v)
  }
  if (length(v) == 0) return(NA)
  
  uniqv <- unique(v)
  uniqv[which.max(tabulate(match(v, uniqv)))]
}
defa_summary <- read_sas("./rfcommun/defa_uu2020.sas7bdat") %>%
  mutate(DEP = paste0("0", substr(CODGEO, 1, 2))) %>%
  group_by(DEP) %>%
  dplyr::summarize(
    FDEP20_quint_imp = get_mode(FDEP20_quint, na.rm = TRUE),
    P20_POP_imp = mean(P20_POP, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(FDEP20_quint_imp=as.character(FDEP20_quint_imp))
merged_imputed <- merged_gp %>%
  # 1. Bring in the reference data based on department matching
  left_join(select(denb_summary, DEP, Nb_GP_imp, Nb_Psych_imp), by = c("BEN_RES_DPT" = "DEP")) %>%
  left_join(select(defa_summary, DEP, FDEP20_quint_imp, P20_POP_imp), by = c("BEN_RES_DPT" = "DEP")) %>%
  # 2. Impute missing Nb_GP using sum_group1 (or whichever group represents your GPs)
  mutate(
    Nb_GP = if_else(is.na(Nb_GP), Nb_GP_imp, Nb_GP),
    Nb_Psych = if_else(is.na(Nb_Psych), Nb_Psych_imp, Nb_Psych),
    FDEP20_quint = if_else(is.na(FDEP20_quint), FDEP20_quint_imp, FDEP20_quint),
    P20_POP = if_else(is.na(P20_POP), P20_POP_imp, P20_POP)
  ) %>%
  # 3. Clean up the extra columns brought in by the join
  select(-Nb_GP_imp, -Nb_Psych_imp, -FDEP20_quint_imp, -P20_POP_imp)
colSums(is.na(merged_imputed))
}

#merged_listwise ----
#do not select variables where at least one missing value
colSums(is.na(merged_gp))

# merged_listwise <- merged_gp %>%
#   select(-Nb_GP, -Nb_Psych, -FDEP20_quint, -P20_POP)
#or na.omit
merged_listwise <- na.omit(merged_gp %>% select(-psy_meds, -event, -calc_stop)) 
merged_listwise <- merged_gp %>%
  # Ensure psy_meds and event are treated as character (if not already)
  # to prevent na.omit from potentially dropping them due to factors with levels,
  # although na.omit generally checks for complete cases across selected rows.
  mutate(
    across(c(psy_meds, event), as.character)
  ) %>%
  # Perform listwise deletion considering all columns EXCEPT psy_meds, event, and calc_stop
  # This keeps rows where all covariates (everything else) are non-NA,
  # regardless of whether psy_meds, event, or calc_stop are NA.
  filter(if_all(-c(psy_meds, event, calc_stop), complete.cases))
rm(merged_gp)


#prepare to anal ----
#B0bZiV-OlT5nZ1B1W B-SclApBAH_FqrFdh B---DV4-HNQn4kVPX B-4VvGqbGHgPv1USA

if (LM_end_anal=="_lastpu_") {
  MRow_data <- merged_listwise %>%
    #filter(BEN_IDT_ANO=="B--2kAo3JfSKkHwHc") %>% # B--2kAo3JfSKkHwHc B---DV4-HNQn4kVPX
    
    group_by(BEN_IDT_ANO) %>%
    
    mutate(
      stop = case_when(stop >= 365 ~ 366.5, #so that stop>start 
                       TRUE ~ as.numeric(stop)),
      
      # Define event status based on your conditions
      event_num = case_when(
        
        stop - start <= grace ~ 0, 
        
        # 1. If stop exceeds LM_end (administrative censoring)
        stop >= LM_end ~ 0,
        
        # 2. If death date falls within the window
        !is.na(BEN_DCD_DTE) & (stop > as.numeric(BEN_DCD_DTE - DT_FIRST_AD)) ~ 0,
        
        # 3. If max treatment duration falls within the window
        !is.na(MAX_TRT_DTD) & (stop > as.numeric(MAX_TRT_DTD - DT_FIRST_AD)) ~ 0,
        
        # Default: event is 1 otherwise (now properly inside case_when)
        TRUE ~ 1
      )
    ) %>%
    ungroup
} else if (LM_end_anal=="_lastsri_") {
  collapsed_data <- merged_listwise %>%
    group_by(BEN_IDT_ANO) %>%
    mutate(
      # 1. Stop calculation: no grace period, 
      #this analysis is not about coverage but rough dates of 
      # discontinuation or switches
      stop = calc_stop,
      stop = case_when(stop >= 365 ~ 366.5, 
                       TRUE ~ as.numeric(stop)),
      
      # Event number and censoring logic
      event_num = case_when(
        # 6. Administrative censoring overrides everything if stop exceeds LM_end
        stop >= LM_end ~ 0,
        
        # 2. SSRI death censoring condition
        !event %in% c("SWI_", "ATD_") & !is.na(BEN_DCD_DTE) & (stop > as.numeric(BEN_DCD_DTE - DT_FIRST_AD)) ~ 0,
        
        # 3. SSRI max treatment censoring condition
        !event %in% c("SWI_", "ATD_") & !is.na(MAX_TRT_DTD) & (stop > as.numeric(MAX_TRT_DTD - DT_FIRST_AD)) ~ 0,
        
        # 4. Otherwise if event is SSRI, event_num = 1
        #event == "SSRI" ~ 1,
        
        # 5. Non-SSRI event codes (using grepl to catch ATD_ and SWI_ prefixes/values)
        grepl("^ATD_", event) ~ 2,
        grepl("^SWI_", event) ~ 3,
        
        # Fallback default if any other values exist
        TRUE ~ 1
      )
    ) %>%
    ungroup()
} else if (LM_end_anal=="_lastatd_") {
  collapsed_data <- merged_listwise %>%
    group_by(BEN_IDT_ANO) %>%
    mutate(
      # 1. Stop calculation: no grace period, this analysis is not about coverage but rough dates of 
      # discontinuation or switches
      stop = calc_stop,
      stop = case_when(stop >= 365 ~ 365, 
                       TRUE ~ as.numeric(stop)),
      # Event number and censoring logic
      event_num = case_when(
        # 6. Administrative censoring overrides everything if stop exceeds LM_end
        stop >= LM_end ~ 0,
        
        # 2. SSRI/ATD death censoring condition
        !event %in% c("SWI_") & !is.na(BEN_DCD_DTE) & (stop > as.numeric(BEN_DCD_DTE - DT_FIRST_AD)) ~ 0,
        
        # 3. SSRI/ATD max treatment censoring condition
        !event %in% c("SWI_") & !is.na(MAX_TRT_DTD) & (stop > as.numeric(MAX_TRT_DTD - DT_FIRST_AD)) ~ 0,
        
        # # 4. Otherwise if event is SSRI/ATD, event_num = 1
        # event %in% c("SSRI","ATD_") ~ 1,
        
        # 5. Non-ATD event codes (using grepl to catch SWI_ prefixes/values)
        grepl("^SWI_", event) ~ 2,
        
        # Fallback default if any other values exist
        TRUE ~ 1
      )
    ) %>%
    ungroup()
}

tmp <- MRow_data %>%
  select(BEN_IDT_ANO, DT_FIRST_AD, MAX_TRT_DTD, BEN_DCD_DTE, 
         start,  stop, event, event_num
  )
hist(MRow_data$stop);table(MRow_data$event_num); summary(MRow_data$stop)
hist(MRow_data %>% filter(event_num==1) %>% pull(stop))
save(MRow_data, file=paste0("./sasdata1/MRow_data", LM_end_anal, grace, ".RData"))
