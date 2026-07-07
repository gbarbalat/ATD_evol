library(dplyr)
library(lubridate)
library(slider) # Required for efficient rolling means in dplyr

run_classic_idp_dplyr <- function(df, product_var = "PHA_PRS_C13", quantity_var = "PHA_ACT_QSN", date_var = "EXE_SOI_DTD") {
  
  # 1. PREPARE THE DATA CORE
  # Use rename with injection (!!) to handle dynamic column strings safely
  analysis_data <- df %>%
    rename(
      product_code       = !!sym(product_var),
      quantity_dispensed = !!sym(quantity_var),
      dispensed_date     = !!sym(date_var)
    ) %>%
    mutate(dispensed_date = as.Date(dispensed_date)) %>%
    # Force chronological sort order by patient and product timeline
    arrange(id, product_code, dispensed_date) %>%
    # Track timeline position per distinct product group
    group_by(id, product_code) %>%
    mutate(disp_index = row_number()) %>%
    ungroup()
  
  # 2. POPULATION CALIBRATION: Calculate e_pop via Valid Inter-dispensing Gaps
  analysis_data <- analysis_data %>%
    group_by(id, product_code) %>%
    mutate(
      next_date    = lead(dispensed_date),
      days_to_next = as.numeric(next_date - dispensed_date)
    ) %>%
    ungroup()
  
  # Isolate valid intervals (>= 2 dispensings under 180 days apart) to calibrate epop
  epop_table <- analysis_data %>%
    filter(days_to_next > 0 & days_to_next < 180) %>%
    group_by(product_code) %>%
    summarise(
      epop_factor = quantile(days_to_next / quantity_dispensed, probs = 0.80, na.rm = TRUE),
      .groups = "drop"
    )
  
  # Merge epop factors back into the main timeline matrix
  analysis_data <- analysis_data %>%
    left_join(epop_table, by = "product_code") %>%
    arrange(id, product_code, dispensed_date)
  
  # 3. INDIVIDUAL DYNAMIC WINDOWS (Moving Average Engine)
  analysis_data <- analysis_data %>%
    group_by(id, product_code) %>%
    mutate(
      # slider::slide_mean calculates right-aligned rolling mean on the active group matrix
      rolling_3_interval = lag(slider::slide_mean(days_to_next, before = 2, after = 0, complete = TRUE)),
      
      epop_duration = epop_factor * quantity_dispensed,
      
      estimated_duration = case_when(
        disp_index <= 3 ~ epop_duration,
        disp_index > 3 & !is.na(rolling_3_interval) ~ rolling_3_interval,
        TRUE ~ epop_duration # fallback to epop baseline if rolling calculation is missing
      )
    ) %>%
    ungroup()
  
  # 4. EPISODE CONSTRUCTION
  analysis_data <- analysis_data %>%
    group_by(id, product_code) %>%
    mutate(
      coverage_end_date  = dispensed_date + estimated_duration,
      prior_coverage_end = lag(coverage_end_date),
      gap_days           = as.numeric(dispensed_date - prior_coverage_end),
      
      is_new_episode = if_else(disp_index == 1 | (disp_index > 1 & gap_days > 15), TRUE, FALSE),
      episode_id     = cumsum(is_new_episode)
    ) %>%
    ungroup()
  
  # 5. AGGREGATE INTO TREATMENT EPISODES
  treatment_episodes <- analysis_data %>%
    group_by(id, product_code, episode_id) %>%
    summarise(
      episode_start           = min(dispensed_date),
      last_dispense_date      = max(dispensed_date),
      final_dispense_duration = last(estimated_duration),
      .groups = "drop"
    ) %>%
    mutate(
      episode_end        = last_dispense_date + final_dispense_duration,
      total_duration_days = as.numeric(episode_end - episode_start)
    ) %>%
    # Restore the original product variable name for output clarity
    rename(!!sym(product_var) := product_code)
  
  return(treatment_episodes)
}
