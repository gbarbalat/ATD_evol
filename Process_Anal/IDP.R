IDP_function <- function(data, drug_name, strength, formulation, dispensed_date) {

# ==============================================================================
# 2. DATA PREPARATION & CHRONOLOGICAL KEYING
# ==============================================================================
  sim_data <- data
  
  sim_data[, molecule  := drug_name] 
sim_data[, unit_spec := paste(molecule, strength, formulation, sep = "_")]

# Force chronological sort order
setkey(sim_data, id, molecule, dispensed_date)

# Track the prescription number per individual molecule timeline
sim_data[, disp_index := 1:.N, by = .(id, molecule)]

# ==============================================================================
# 3. POPULATION CALIBRATION: Calculate e_pop via Valid Strength Pairs
# ==============================================================================
# Calculate gaps to the next dispensing forward in time
sim_data[, next_date := shift(dispensed_date, type = "lead"), by = .(id, molecule)]
sim_data[, days_to_next := as.numeric(next_date - dispensed_date)]

# Isolate valid pairs (individuals with >= 2 dispensings under 180 days apart)
valid_pairs <- sim_data[days_to_next > 0 & days_to_next < 180]
valid_pairs[, days_per_unit := days_to_next / quantity_dispensed]

# Calculate the 80th percentile factor strictly per specific unit strength configuration
epop_table <- valid_pairs[, .(
  epop_factor = quantile(days_per_unit, probs = 0.80, na.rm = TRUE)
), by = .(unit_spec)]

# Merge the strength-calibrated epop factor back into the main cohort matrix
analysis_data <- merge(sim_data, epop_table, by = "unit_spec", all.x = TRUE)
setkey(analysis_data, id, molecule, dispensed_date)
analysis_data[, disp_index := 1:.N, by = .(id, molecule)] # Re-index to ensure safety

# ==============================================================================
# 4. INDIVIDUAL DYNAMIC WINDOWS (Moving Average Engine)
# ==============================================================================
# Calculate the moving average of the prior 3 intervals along the continuous timeline
analysis_data[, rolling_3_interval := shift(
  frollmean(days_to_next, n = 3, align = "right", fill = NA), 
  n = 1, type = "lag", fill = NA
), by = .(id, molecule)]

analysis_data[, estimated_duration := as.numeric(NA)]

# Rule A: The absolute first dispensing uses epop * individual quantity volume
analysis_data[disp_index == 1, estimated_duration := epop_factor * quantity_dispensed]

# Rule B: Subsequent rows use the moving window average. Fall back to epop if < 3 intervals exist.
analysis_data[disp_index > 1, estimated_duration := ifelse(
  is.na(rolling_3_interval), 
  epop_factor * quantity_dispensed, 
  rolling_3_interval
)]

# ==============================================================================
# 5. EPISODE CONSTRUTION: Backward Gap Evaluation & 15-Day Grace Check
# ==============================================================================
analysis_data[, coverage_end_date := dispensed_date + estimated_duration]
analysis_data[, prior_coverage_end := shift(coverage_end_date, type = "lag"), by = .(id, molecule)]
analysis_data[, gap_days := as.numeric(dispensed_date - prior_coverage_end)]

analysis_data[, is_new_episode := FALSE]
analysis_data[disp_index == 1, is_new_episode := TRUE]
analysis_data[disp_index > 1 & gap_days > 15, is_new_episode := TRUE]

# Assign unique episode IDs using the cumulative sum engine
analysis_data[, episode_id := cumsum(is_new_episode), by = .(id, molecule)]

# ==============================================================================
# 6. ANALYSIS OUTPUTS
# ==============================================================================
# Display granular per-prescription line calculation details
cat("\n--- DETAILED PRESCRIPTION-LINE TRACKING ---\n")
print(analysis_data[, .(id, strength, dispensed_date, quantity_dispensed, epop_factor, estimated_duration, gap_days, episode_id)])

# Aggregate data into continuous treatment episodes
treatment_episodes <- analysis_data[, .(
  episode_start           = min(dispensed_date),
  last_dispense_date      = max(dispensed_date),
  final_dispense_duration = last(estimated_duration)
), by = .(id, molecule, episode_id)]

treatment_episodes[, episode_end := last_dispense_date + final_dispense_duration]
treatment_episodes[, total_duration_days := as.numeric(episode_end - episode_start)]

cat("\n--- FINAL COLLAPSED TREATMENT EPISODES ---\n")
print(treatment_episodes)

  }
