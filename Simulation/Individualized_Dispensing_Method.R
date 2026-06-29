#Individualized dispensing pattern method
#need to construct unit type variable as paste(drug_name, strength, formulation)
#for epop, group by the exact strength to find out how fast a single table vanishes
#for rolling3 and episodes at the invidual level, group strictly by patient and base molecule

library(data.table)

# Example data structure
rm(list=ls())
set.seed(456)
n_records <- 1000
dispensing_data <- data.table(
  id = sample(1:100, n_records, replace = TRUE),
  dispensed_date = as.Date("2022-01-01") + sample(0:365, n_records, replace = TRUE),
  #unit_type = sample(c("Tablet", "Injection"), n_records, replace = TRUE),
  unit_type = sample(c("Tablet"), n_records, replace = TRUE),
  
  quantity_dispensed = sample(c(28, 30, 56, 90), n_records, replace = TRUE)
)
# Sort strictly by individual and date
setorder(dispensing_data, id, dispensed_date, unit_type)
dispensing_data <- dispensing_data[order(id,dispensed_date )]

# 1. Calculate time gaps between consecutive dispensings for the same drug unit type
dispensing_data[, next_date := shift(dispensed_date, type = "lead"), by = .(id, unit_type)]
dispensing_data[, days_to_next := as.numeric(next_date - dispensed_date)]

# 2. Estimate days covered per individual unit (only for pairs < 180 days apart)
valid_pairs <- dispensing_data[days_to_next > 0 & days_to_next < 180] 
#days to next>0 means that it restricts dataset to indiv with at least 2 dispensings
valid_pairs[, days_per_unit := days_to_next / quantity_dispensed]

# 3. Calculate the global 80th percentile threshold (e_pop) per unit type
epop_table <- valid_pairs[, .(
  epop_factor = quantile(days_per_unit, probs = 0.80, na.rm = TRUE)
), by = .(unit_type)]

print(epop_table)

# Merge the baseline epop factors back into the main dataset
dispensing_data <- merge(dispensing_data, epop_table, by = "unit_type", all.x = TRUE)

# Clean up structural indicators per individual group
dispensing_data[, disp_index := 1:.N, by = .(id, unit_type)]

# Use a rolling index to get the mean days_to_next of the PRIOR 3 dispensings
# (frollmean naturally calculates the rolling mean of the current and prior rows, 
# so we shift it)
dispensing_data[, rolling_3_interval := shift(
  frollmean(days_to_next, n = 3, align = "right", fill = NA),
  n=1, type="lag", fill=NA
  ), by = .(id, unit_type)]

# Assign durations using conditional evaluation rule checks
dispensing_data[, estimated_duration := as.numeric(NA)]

# Rule A: The first dispensing uses epop * quantity
dispensing_data[disp_index == 1, estimated_duration := epop_factor * quantity_dispensed]

# Rule B: Subsequent dispensings use the individual's prior moving pattern.
# If they don't have 3 prior gaps yet, default back to the population epop rule
dispensing_data[disp_index > 1, estimated_duration := ifelse(
  is.na(rolling_3_interval), 
  epop_factor * quantity_dispensed, 
  rolling_3_interval
)]

# Calculate the absolute coverage end boundary per prescription line
dispensing_data[, coverage_end_date := dispensed_date + estimated_duration]

# Determine if a gap exists between this line's coverage and the next purchase date
dispensing_data[, next_dispensed_date := shift(dispensed_date, type = "lead"), by = .(id, unit_type)]
dispensing_data[, prior_coverage_end := shift(coverage_end_date, type = "lag"), by = .(id, unit_type)]
dispensing_data[, gap_days := as.numeric(next_dispensed_date - coverage_end_date)]
dispensing_data[, gap_days := as.numeric(dispensed_date - prior_coverage_end)]

# A gap occurs only if the patient refills LATER than the estimated coverage + 15 days grace
dispensing_data[, is_new_episode := FALSE]
dispensing_data[disp_index == 1, is_new_episode := TRUE] # First row is always a start
dispensing_data[disp_index > 1 & gap_days > 15, is_new_episode := TRUE]   # Gap breached grace period

# Generate an ascending episode counter index
dispensing_data[, episode_id := cumsum(is_new_episode), by = .(id, unit_type)]

treatment_episodes <- dispensing_data[, .(
  episode_start = min(dispensed_date),
  last_dispense_date = max(dispensed_date),
  final_dispense_duration = last(estimated_duration),
  total_quantity = sum(quantity_dispensed)
), by = .(id, unit_type, episode_id)]

# Apply the mathematical execution: (Last - First) + Final Estimated Duration
treatment_episodes[, episode_end := last_dispense_date + final_dispense_duration]
treatment_episodes[, total_episode_duration_days := as.numeric(episode_end - episode_start)]

# View structural final model output
print(head(treatment_episodes[, .(id, unit_type, episode_id, episode_start, episode_end, total_episode_duration_days)]))

stop()

library(data.table)

# ==============================================================================
# 1. CREATE REALISTIC SIMULATED PHARMACY DATA
# ==============================================================================
# We will simulate 3 patients with different behavioral patterns:
# Patient 101: Standard User (Takes 1 tablet of 50mg daily, stays stable)
# Patient 102: High-Dose User (Takes 3 tablets of 50mg daily, runs out fast)
# Patient 103: Dose Titrator (Switches from 50mg to 100mg smoothly, then stops)

sim_data <- data.table(
  id = c(
    rep(101, 5), # Patient 101
    rep(102, 5), # Patient 102
    rep(103, 5)  # Patient 103
  ),
  drug_name = "Sertraline",
  strength = c(
    rep("50mg", 5),                 # 101: Stable 50mg
    rep("50mg", 5),                 # 102: Stable 50mg (but high dose)
    c("50mg", "50mg", "100mg", "100mg", "100mg") # 103: Switches strengths
  ),
  formulation = "Tablet",
  quantity_dispensed = c(
    rep(30, 5),  # 101: Gets 30 tabs each time
    rep(90, 5),  # 102: Gets 90 tabs each time
    c(30, 30, 30, 30, 30) # 103: Gets 30 tabs each time
  ),
  dispensed_date = as.Date(c(
    # Patient 101: Returns roughly every 30 days (1 tab/day)
    "2025-01-01", "2025-01-31", "2025-03-02", "2025-04-01", "2025-05-01",
    # Patient 102: Returns roughly every 30 days for 90 tabs (3 tabs/day)
    "2025-01-01", "2025-01-29", "2025-03-01", "2025-03-28", "2025-04-26",
    # Patient 103: Titrates. Fills 50mg, fills 100mg on time, then experiences a massive gap
    "2025-01-01", "2025-01-28", "2025-02-25", "2025-03-25", "2025-06-15"
  ))
)

# ==============================================================================
# 2. DATA PREPARATION & CHRONOLOGICAL KEYING
# ==============================================================================
dispensing_data <- dispensing_data[order(id,dispensed_date )]

# 'molecule' preserves the continuous individual timeline during titration
# 'unit_spec' captures the specific strength for population calibration
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
