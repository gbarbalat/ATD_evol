library(data.table)

run_classic_idp <- function(dt, molecule_var, formulation_var, strength_var, quantity_var, date_var) {
  
  # 1. PREPARE THE DATA CORE
  analysis_data <- copy(dt)
  
  setnames(analysis_data, 
           c(molecule_var, formulation_var, strength_var, quantity_var, date_var), 
           c("molecule", "formulation", "strength", "quantity_dispensed", "dispensed_date"))
  
  # Grouping key combining molecule profile configurations
  analysis_data[, unit_spec := paste(molecule, strength, formulation, sep = "_")]
  
  # Force chronological sort order
  setkey(analysis_data, id, molecule, formulation, dispensed_date)
  
  # Track timeline position per drug category
  analysis_data[, disp_index := 1:.N, by = .(id, molecule, formulation)]
  
  # 2. POPULATION CALIBRATION: Calculate e_pop via Valid Inter-dispensing Gaps
  analysis_data[, next_date := shift(dispensed_date, type = "lead"), by = .(id, molecule, formulation)]
  analysis_data[, days_to_next := as.numeric(next_date - dispensed_date)]
  
  # Isolate valid intervals (>= 2 dispensings under 180 days apart) to calibrate epop
  valid_pairs <- analysis_data[days_to_next > 0 & days_to_next < 180]
  valid_pairs[, days_per_unit := days_to_next / quantity_dispensed]
  
  # Group by the specific molecule/strength/formulation combo
  epop_table <- valid_pairs[, .(
    epop_factor = quantile(days_per_unit, probs = 0.80, na.rm = TRUE)
  ), by = .(unit_spec)]
  
  # Merge epop factors back into the main timeline matrix
  analysis_data <- merge(analysis_data, epop_table, by = "unit_spec", all.x = TRUE)
  setkey(analysis_data, id, molecule, formulation, dispensed_date)
  
  # 3. INDIVIDUAL DYNAMIC WINDOWS (Moving Average Engine)
  # Calculate the moving average of the prior 3 actual intervals
  analysis_data[, rolling_3_interval := shift(
    frollmean(days_to_next, n = 3, align = "right", fill = NA), 
    n = 1, type = "lag", fill = NA
  ), by = .(id, molecule, formulation)]
  
  analysis_data[, estimated_duration := as.numeric(NA)]
  
  # Baseline calculation using epop * quantity volume
  analysis_data[, epop_duration := epop_factor * quantity_dispensed]
  
  # Rule A: The absolute first 3 dispensings use epop proxy baseline
  analysis_data[disp_index <= 3, estimated_duration := epop_duration]
  
  # Rule B: Subsequent lines use the moving window average (fallback to epop if missing)
  analysis_data[disp_index > 3, estimated_duration := ifelse(
    is.na(rolling_3_interval), 
    epop_duration, 
    rolling_3_interval
  )]
  
  # 4. EPISODE CONSTRUCTION
  analysis_data[, coverage_end_date := dispensed_date + estimated_duration]
  analysis_data[, prior_coverage_end := shift(coverage_end_date, type = "lag"), by = .(id, molecule, formulation)]
  analysis_data[, gap_days := as.numeric(dispensed_date - prior_coverage_end)]
  
  analysis_data[, is_new_episode := FALSE]
  analysis_data[disp_index == 1, is_new_episode := TRUE]
  analysis_data[disp_index > 1 & gap_days > 15, is_new_episode := TRUE]
  
  analysis_data[, episode_id := cumsum(is_new_episode), by = .(id, molecule, formulation)]
  
  # 5. AGGREGATE INTO TREATMENT EPISODES
  treatment_episodes <- analysis_data[, .(
    episode_start           = min(dispensed_date),
    last_dispense_date      = max(dispensed_date),
    final_dispense_duration = last(estimated_duration)
  ), by = .(id, molecule, formulation, episode_id)]
  
  treatment_episodes[, episode_end := last_dispense_date + final_dispense_duration]
  treatment_episodes[, total_duration_days := as.numeric(episode_end - episode_start)]
  
  return(treatment_episodes)
}
