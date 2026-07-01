run_hybrid_idp <- function(dt, molecule_var, formulation_var, quantity_var, date_var, prescribed_dose_mg_var, strength_mg_var) {
  
  # Copy data to avoid modifying the original data table by reference
  analysis_data <- copy(dt)
  
  # Standardize variable names inside the function
  setnames(analysis_data, 
           c(molecule_var, formulation_var, quantity_var, date_var, prescribed_dose_mg_var, strength_mg_var), 
           c("molecule", "formulation", "quantity_dispensed", "dispensed_date", "prescribed_dose_mg", "strength_mg"))
  
  # Ensure chronological sorting
  setkey(analysis_data, id, molecule, formulation, dispensed_date)
  
  # 1. TRACK THE INDIVIDUAL TIMELINE INDEX PER PAIR
  analysis_data[, disp_index := 1:.N, by = .(id, molecule, formulation)]
  
  # 2. CALCULATE INTER-DISPENSING GAPS FOR THE MOVING AVERAGE
  analysis_data[, next_date := shift(dispensed_date, type = "lead"), by = .(id, molecule, formulation)]
  analysis_data[, days_to_next := as.numeric(next_date - dispensed_date)]
  
  # 3. PRESCRIBED DOSE BASELINE (Replaces e_pop entirely)
  # Calculate exactly how many tablets are needed per day: Prescribed Dose / Tablet Strength
  analysis_data[, tabs_per_day := prescribed_dose_mg / strength_mg]
  # Intended duration = Total tablets / tablets per day
  analysis_data[, prescribed_duration := quantity_dispensed / tabs_per_day]
  
  # 4. INDIVIDUAL DYNAMIC WINDOWS (Moving Average Engine)
  # Calculate rolling mean of the prior 3 actual intervals along the timeline
  analysis_data[, rolling_3_interval := shift(
    frollmean(days_to_next, n = 3, align = "right", fill = NA), 
    n = 1, type = "lag", fill = NA
  ), by = .(id, molecule, formulation)]
  
  analysis_data[, estimated_duration := as.numeric(NA)]
  
  # Rule A: The first 3 lines utilize the doctor's explicit prescribed math
  analysis_data[disp_index <= 3, estimated_duration := prescribed_duration]
  
  # Rule B: Line 4 and beyond use actual behavioral moving averages if available; fallback to prescription
  analysis_data[disp_index > 3, estimated_duration := ifelse(
    is.na(rolling_3_interval), 
    prescribed_duration, 
    rolling_3_interval
  )]
  
  # 5. EPISODE CONSTRUCTION
  analysis_data[, coverage_end_date := dispensed_date + estimated_duration]
  analysis_data[, prior_coverage_end := shift(coverage_end_date, type = "lag"), by = .(id, molecule, formulation)]
  analysis_data[, gap_days := as.numeric(dispensed_date - prior_coverage_end)]
  
  analysis_data[, is_new_episode := FALSE]
  analysis_data[disp_index == 1, is_new_episode := TRUE]
  analysis_data[disp_index > 1 & gap_days > 15, is_new_episode := TRUE]
  
  analysis_data[, episode_id := cumsum(is_new_episode), by = .(id, molecule, formulation)]
  
  # 6. COLLAPSE INTO CONTINUOUS TREATMENT EPISODES
  treatment_episodes <- analysis_data[, .(
    episode_start           = min(dispensed_date),
    last_dispense_date      = max(dispensed_date),
    final_dispense_duration = last(estimated_duration)
  ), by = .(id, molecule, formulation, episode_id)]
  
  treatment_episodes[, episode_end := last_dispense_date + final_dispense_duration]
  treatment_episodes[, total_duration_days := as.numeric(episode_end - episode_start)]
  
  return(treatment_episodes)
}
