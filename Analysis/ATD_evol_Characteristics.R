library(gtsummary)
library(dplyr)

# Assuming 'merged_ignore' is your data frame
# and 'First_Prescriber' is the column defining exposure groups.
# Ensure 'First_Prescriber' is a factor or character for correct grouping.

table1 <- merged_gp %>%
  select(-BEN_IDT_ANO, calc_stop, #stop, start,
         all_of(categ_var),all_of(num_var), 
         event) %>% #psy_meds, 

  # Start the gtsummary table
  tbl_summary(
    by = First_Prescriber, # Define the exposure variable used for columns
    
    # Customize labels for better presentation
    # label = list(
    #   Age ~ "Age (years)",
    #   Sex ~ "Biological Sex",
    #   Region ~ "Geographic Region",
    #   Comorbidity_Score ~ "Charlson Comorbidity Index",
    #   Medication_Count ~ "Number of Concomitant Medications"
    # ),
    
    # Define how different types of variables should be summarized
    statistic = list(
      # For continuous variables, show Mean (SD) and Median (IQR)
      all_continuous() ~ "{mean} ({sd}); {median} ({p25}, {p75})",
      # For categorical variables, show count and column percentage
      all_categorical() ~ "{n} ({p}%)"
    ),
    
    # Specify digits for rounding (optional)
    # digits = list(
    #   Age ~ c(1, 1), # Round Age mean/sd to 1 decimal
    #   Comorbidity_Score ~ c(2, 2) # Round Comorbidity Score to 2 decimals
    # ),
    
    # Handle missing data: If less than 5% missing, hide the 'Unknown' row.
    # If more, display it to show patterns. (Adjust threshold as needed)
    missing_text = "Missing"
  ) %>%
  
  # Add overall column summarizing all participants regardless of exposure
  add_overall(last = FALSE) %>% # Set to TRUE to place Overall column on the right
  
  # Add p-values comparing the groups defined by First_Prescriber
  # Appropriate tests (t-test, ANOVA, Chi-square, Fisher's) are chosen automatically based on data distribution
  add_p(
    # Optional: Specify particular tests for specific variables if needed
    # test = list(Age ~ "t.test")
  ) %>%
  
  # Add bold formatting to variable names
  bold_labels() %>%
  
  # Add a spanning header for the groups
  modify_spanning_header(c("stat_0", "stat_1", "stat_2") ~ "**Exposure Group (First Prescriber)**") %>% # Adjust stat_# columns to match your data
  
  # Set the main title of the table
  modify_header(label = "**Variable**") %>%
  modify_caption("**Table 1. Baseline Characteristics by Exposure Group**")

# Print the table
print(table1)

# Optional: Save the table to a file (e.g., Word or HTML)
# table1 %>% as_flex_table() %>% flextable::save_as_docx(path = "Table1_Baseline_Characteristics.docx")
# table1 %>% as_gt() %>% gt::gtsave(filename = "Table1_Baseline_Characteristics.html")
