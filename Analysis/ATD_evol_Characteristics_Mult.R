library(dplyr)
library(gtsummary)
library(lubridate)

# Helper function to calculate the mode
get_mode <- function(x) {
  if (all(is.na(x))) return(NA_character_) # Handle all NA cases
  ux <- unique(na.omit(x))
  if (length(ux) == 0) return(NA_character_) # Handle cases where all are NA after omit
  ux[which.max(tabulate(match(x, ux)))]
}

# 1. Prepare the data: Collapse longitudinal data to one row per patient
patient_data <- merged_gp %>%
  group_by(BEN_IDT_ANO) %>%
  summarise(
    # -- Means for 'Cumul*' variables --
    # This selects all columns starting with 'Cumul', calculates mean,
    # and automatically names them e.g., "Mean_Cumul_Total_Remb"
    across(starts_with("Cumul"), 
           ~mean(.x, na.rm = TRUE), 
           .names = "Mean_{col}"),
    
    # -- Modes for specified categorical variables --
    Mode_Pregnant = get_mode(Pregnant),
    Mode_MCO_SSR_HAD_RIP_Length = get_mode(MCO_SSR_HAD_RIP_Length),
    Mode_First_Prescriber = get_mode(First_Prescriber),
    
    # -- Mean delay between start and stop --
    # Assumes 'start' and 'stop' are numeric (days).
    # If they are dates, use as.numeric(stop - start).
    Mean_Delay = mean(stop - start, na.rm = TRUE),
    
    # -- Last event_num --
    # Assumes data is ordered chronologically. If not, add arrange(date) before group_by.
    Last_Event_Num = last(event_num),
    
    # Optional: Keep static covariates if they are included in merged_gp
    # Replace 'Static_Covariate' with actual names if they exist
    # Static_Covariate = first(Static_Covariate), 
    
    .groups = "drop"
  )

# 2. Create the gtsummary Table 1
table1 <- patient_data %>%
  # Select columns to display in the table. Exclude the ID.
  select(-BEN_IDT_ANO) %>%
  tbl_summary(
    # Customize labels for better presentation
    label = list(
      Mean_Delay ~ "Mean Time to Event (days)", # Adjust based on your interpretation
      Last_Event_Num ~ "Event Status at End of Follow-up",
      Mode_Pregnant ~ "Pregnancy Status (Mode)",
      Mode_MCO_SSR_HAD_RIP_Length ~ "Care Facility Length (Mode)",
      Mode_First_Prescriber ~ "Initial Prescriber Specialty (Mode)"
      # Add labels for Mean_Cumul_* variables here if desired,
      # or let gtsummary use the clean names derived in summarise()
    ),
    
    # Define how to display different types of variables
    statistic = list(
      # For continuous variables, show Mean (SD)
      all_continuous() ~ "{mean} ({sd})",
      # For categorical variables (Mode columns and Last_Event_Num), show n (%)
      c(all_categorical(), Last_Event_Num) ~ "{n} ({p}%)"
    ),
    
    # Ensure event_num is treated as categorical for display
    type = list(Last_Event_Num = "categorical"),
    
    # Handle missing data
    missing_text = "Missing"
  ) %>%
  # Add overall column
  add_overall() %>%
  # Bold variable names
  bold_labels() %>%
  # Set table caption
  modify_caption("**Table 1. Patient Baseline Characteristics**")

# Print the table
print(table1)

# Optional: Export to Word
# table1 %>% as_flex_table() %>% flextable::save_as_docx(path = "Table1_Baseline.docx")
