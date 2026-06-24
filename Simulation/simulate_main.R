rm(list=ls())
library(mstate)
library(survival)

# ==========================================
# 1. DEFINE THE FULLY REVERSIBLE MATRIX
# ==========================================
# States 1 through 6 are fully interconnected (can transition to each other). 
# State 7 (Death) is the sole absorbing state.
state_names <- c("Init_ATD", "Stopped_Meds", "Aug_Another_ATD", "Aug_AP_MoodStb", 
                 "Aug_Z_BZD", "Switch_Other_Class", "Death")

tmat_psych <- transMat(x = list(
  c(2, 3, 4, 5, 6, 7), # 1. Init_ATD           -> can go anywhere
  c(1, 3, 4, 5, 6, 7), # 2. Stopped_Meds        -> can go anywhere
  c(1, 2, 4, 5, 6, 7), # 3. Aug_Another_ATD     -> can go anywhere
  c(1, 2, 3, 5, 6, 7), # 4. Aug_AP_MoodStb      -> can go anywhere
  c(1, 2, 3, 4, 6, 7), # 5. Aug_Z_BZD           -> can go anywhere
  c(1, 2, 3, 4, 5, 7), # 6. Switch_Other_Class  -> can go anywhere
  NULL                 # 7. Death (Absorbing)
), names = state_names)

print(tmat_psych)
# Note: This creates 36 unique transition pathways in total!

# ==========================================
# 2. SIMULATE HISTORY WITH REVERSIBLE TRANSITIONS
# ==========================================
set.seed(123)
n <- 500   # Reduced cohort size slightly due to massive row-generation from 36 transitions
max_followup <- 60 

long_rows <- list()

for (i in 1:n) {
  current_time <- 0
  current_state <- 1 # Everyone enters on initial ATD monotherapy
  age_baseline <- runif(1, 18, 65)
  
  individual_censor_time <- pmin(rexp(1, rate = 0.005), max_followup)
  if(individual_censor_time == 0) individual_censor_time <- max_followup
  
  while (current_time < individual_censor_time) {
    
    # Identify which transitions are valid out of the current state
    allowed_transitions_idx <- which(!is.na(tmat_psych[current_state, ]))
    allowed_to_states <- allowed_transitions_idx
    actual_trans_numbers <- tmat_psych[current_state, allowed_transitions_idx]
    
    # Simulate a competitive race (holding times) for all outbound paths
    # We assign general exit rates (Death is rare, changing meds is common)
    rates <- rep(0.04, length(allowed_to_states))
    rates[allowed_to_states == 7] <- 0.002 # Low mortality hazard
    
    holding_times <- rexp(length(allowed_to_states), rate = rates)
    delta <- min(holding_times)
    evt_time <- current_time + delta
    
    if (evt_time >= individual_censor_time) {
      # Censored: Record 0 status for all available pathways from this state
      for (k in 1:length(actual_trans_numbers)) {
        long_rows[[length(long_rows) + 1]] <- data.frame(
          id=i, Tstart=current_time, Tstop=individual_censor_time, 
          trans=actual_trans_numbers[k], status=0, age=age_baseline
        )
      }
      current_time <- individual_censor_time
    } else {
      # Event occurs: Find which transition won the race
      winning_idx <- which.min(holding_times)
      next_state <- allowed_to_states[winning_idx]
      winning_trans <- actual_trans_numbers[winning_idx]
      
      # Record the lines for this time step
      for (k in 1:length(actual_trans_numbers)) {
        long_rows[[length(long_rows) + 1]] <- data.frame(
          id=i, Tstart=current_time, Tstop=evt_time, 
          trans=actual_trans_numbers[k], 
          status=ifelse(actual_trans_numbers[k] == winning_trans, 1, 0), 
          age=age_baseline
        )
      }
      
      current_time <- evt_time
      current_state <- next_state
      
      # Stop if the user hits the ultimate absorbing state (Death)
      if (current_state == 7) break
    }
  }
}

# Combine into valid long mstate format
ms_psych_reversible <- do.call(rbind, long_rows)
class(ms_psych_reversible) <- c("msdata", "data.frame")
attr(ms_psych_reversible, "trans") <- tmat_psych

# ==========================================
# 3. FIT THE MODEL & CALCULATE TRANSITION PROBABILITIES
# ==========================================
# Fit across all 36 stratified transitions
fit_reversible <- coxph(
  Surv(Tstart, Tstop, status) ~ age + strata(trans), 
  data = ms_psych_reversible, 
  method = "breslow", 
  cluster = id
)

# Generate baseline prediction matrix for an average age across all 36 transitions
ref_profile <- data.frame(age = rep(mean(ms_psych_reversible$age), 36), trans = 1:36, strata = 1:36)
hazards_reversible <- msfit(object = fit_reversible, newdata = ref_profile, trans = tmat_psych)

# Compute probabilities over time from baseline
fixed_prob_matrix <- probtrans(hazards_reversible, predt = 0)

# ==========================================
# 4. PLOT COHORT TRAJECTORIES OVER TIME
# ==========================================
plot_colors <- c("#E0E0E0", "#FA8072", "#9370DB", "#4169E1", "#3CB371", "#FFD700", "#1A1A1A")

plot(
  fixed_prob_matrix, 
  from = 1, # Plots the destiny of those starting in Init_ATD
  ord = c(1, 2, 3, 4, 5, 6, 7), 
  col = plot_colors, 
  xlab = "Months of Follow-up", 
  ylab = "Proportion of Active Cohort",
  main = "5-Year Fully Reversible Psychiatric State System Plot"
)

legend(
  "topright", 
  legend = state_names, 
  fill = plot_colors, 
  bty = "n",
  cex = 0.8
)

##############
##############
# Calculate probabilities conditional on being in State 1 at Month 12
##############
##############
prob_after_1year <- probtrans(hazards_reversible, predt = 12)

# Plot the forward trajectory of these long-term monotherapy patients
plot(
  prob_after_1year, 
  from = 1, # Conditioned on being in State 1 at landmark
  ord = c(1, 2, 3, 4, 5, 6, 7), 
  col = plot_colors, 
  xlab = "Months of Follow-up (Starting at Month 12)", 
  ylab = "Proportion of Cohort",
  main = "Destiny of Individuals on ATD Monotherapy at 1 Year"
)
legend("topright", legend = state_names, fill = plot_colors, bty = "n", cex = 0.8)


##############
##############
# What happens after you augment (Specific)
##############
##############
# Generate transition probabilities from a common early landmark when augmentation may have occurred (e.g., month 6)
prob_at_aug_landmark <- probtrans(hazards_reversible, predt = 6)

# Set up a multi-panel layout to compare augmentation types side-by-side
par(mfrow = c(1, 3))

# 1. Initiated Augmentation with Another ATD (State 3)
plot(prob_at_aug_landmark, from = 3, ord = c(3, 1, 2, 4, 5, 6, 7), col = plot_colors[c(3, 1, 2, 4, 5, 6, 7)],
     xlab = "Months", ylab = "Proportion", main = "From: Augment with Another ATD")

# 2. Initiated Augmentation with AP/Mood Stabilizer (State 4)
plot(prob_at_aug_landmark, from = 4, ord = c(4, 1, 2, 3, 5, 6, 7), col = plot_colors[c(4, 1, 2, 3, 5, 6, 7)],
     xlab = "Months", ylab = "Proportion", main = "From: Augment with AP/MoodStb")

# 3. Initiated Augmentation with Z-Drug/BZD (State 5)
plot(prob_at_aug_landmark, from = 5, ord = c(5, 1, 2, 3, 4, 6, 7), col = plot_colors[c(5, 1, 2, 3, 4, 6, 7)],
     xlab = "Months", ylab = "Proportion", main = "From: Augment with Z-BZD")

# Reset layout
par(mfrow = c(1, 1))


##############
##############
# What happens after you have switched to a different class?
##############
##############
# Calculate trajectories for individuals who are in the 'Switch' state at Month 6
plot(
  prob_at_aug_landmark, 
  from = 6, # From Switch_Other_Class
  ord = c(6, 1, 2, 3, 4, 5, 7), 
  col = plot_colors[c(6, 1, 2, 3, 4, 5, 7)], 
  xlab = "Months of Follow-up", 
  ylab = "Proportion of Cohort",
  main = "Destiny of Individuals After Switching Drug Class"
)
legend("topright", legend = state_names[c(6, 1, 2, 3, 4, 5, 7)], fill = plot_colors[c(6, 1, 2, 3, 4, 5, 7)], bty = "n", cex = 0.8)




##############
##############
# Plots
##############
##############


library(dplyr)
library(tidyr)
library(ggplot2)

# ==============================================================================
# FUNCTION TO TRACK POST-ACTION STATE DISTRIBUTION OVER TIME
# ==============================================================================
get_state_distribution_over_time <- function(data, tmat, target_state, max_time = 24) {
  
  # 1. Find the exact transition ID paths that land into our target state
  incoming_transitions <- which(tmat[, target_state] > 0)
  
  # 2. Extract the exact moment each individual transitioned into this state
  entry_times <- data %>%
    filter(trans %in% incoming_transitions & status == 1) %>%
    group_by(id) %>%
    summarise(entry_time = min(Tstop), .groups = "drop")
  
  if(nrow(entry_times) == 0) return(NULL) # Guard check if state was never hit
  
  # 3. Align all post-entry history and normalize the clock to 0
  post_entry_history <- data %>%
    inner_join(entry_times, by = "id") %>%
    filter(Tstart >= entry_time) %>%
    mutate(
      Tstart_new = Tstart - entry_time,
      Tstop_new = Tstop - entry_time
    )
  
  # 4. Reconstruct what state every individual is in at every month step
  time_grid <- seq(0, max_time, by = 1)
  grid_tracked <- list()
  
  # Determine current state at each slice by mapping back active transition origins
  for (t_step in time_grid) {
    active_states <- post_entry_history %>%
      filter(Tstart_new <= t_step & Tstop_new > t_step) %>%
      group_by(id) %>%
      # Deduplicate rows by taking the transition matrix source row index
      slice(1) %>% 
      ungroup()
    
    # Identify the state they are in. If they died during this interval, catch them
    # Otherwise, look at the row's baseline starting point for that interval
    # (Using tmat matching logic)
    states_present <- data.frame(id = active_states$id)
    states_present$Current_State <- sapply(1:nrow(active_states), function(idx) {
      curr_trans <- active_states$trans[idx]
      origin_state <- which(tmat == curr_trans, arr.ind = TRUE)[1]
      return(origin_state)
    })
    
    if(nrow(states_present) > 0) {
      counts <- table(factor(states_present$Current_State, levels = 1:7))
      proportions <- as.numeric(counts) / sum(counts)
      grid_tracked[[length(grid_tracked) + 1]] <- data.frame(
        Time = t_step,
        State = state_names,
        Proportion = proportions
      )
    }
  }
  
  return(bind_rows(grid_tracked))
}

# ==============================================================================
# GENERATE THE GRAPH VISUALIZATIONS
# ==============================================================================
# Set up a 2x2 grid layout to see all strategies separately
par(mfrow = c(2, 2))

# List of the distinct target strategies to analyze
strategies <- c(3, 4, 5, 6) 
strategy_titles <- c("Augment: Another ATD", "Augment: AP / Mood Stabilizer", 
                      "Augment: Z-Drug / BZD", "Switched Class Completely")

for (i in 1:length(strategies)) {
  df_plot <- get_state_distribution_over_time(ms_psych_reversible, tmat_psych, target_state = strategies[i], max_time = 36)
  
  if(!is.null(df_plot)) {
    # Pivot wide to match the signature probtrans look for plotting area
    wide_p <- df_plot %>% 
      pivot_wider(names_from = State, values_from = Proportion) %>% 
      arrange(Time)
    
    # Cumulative matrix structure for stack area filling look
    mat_p <- as.matrix(wide_p[, -1])
    cum_mat_p <- t(apply(mat_p, 1, cumsum))
    
    # Initialize blank structural plot frame
    plot(wide_p$Time, wide_p$Time, type = "n", ylim = c(0, 1), xlim = c(0, max(wide_p$Time)),
         xlab = "Months Since Strategy Action", ylab = "Proportion of Active Patients", 
         main = strategy_titles[i])
    
    # Fill in the multi-state areas step-by-step
    for(k in 7:1) {
      polygon(
        c(wide_p$Time, rev(wide_p$Time)),
        c(if(k == 1) rep(0, nrow(wide_p)) else cum_mat_p[, k - 1], rev(cum_mat_p[, k])),
        col = plot_colors[k], border = "white"
      )
    }
  }
}

# Reset layout viewing frames
par(mfrow = c(1, 1))



##############
##############
# What happens after you have switched to a different class? no matter when you switched
##############
##############
library(dplyr)

# 1. Find the exact Tstart where each individual first enters State 6 (Switch)
switched_cohort <- ms_psych_reversible %>%
  filter(trans %in% which(tmat_psych[, 6] > 0) & status == 1) %>% # transitions leading TO state 6
  group_by(id) %>%
  summarise(switch_time = min(Tstop))

# 2. Extract all history for those individuals AFTER their switch time
post_switch_history <- ms_psych_reversible %>%
  inner_join(switched_cohort, by = "id") %>%
  filter(Tstart >= switch_time) %>%
  mutate(
    # Reset the clock so the moment of switching is time 0
    Tstart_new = Tstart - switch_time,
    Tstop_new = Tstop - switch_time
  )

# 3. Now you can easily calculate descriptive statistics!
# For example, what state are they in 12 months after switching?
state_at_12m <- post_switch_history %>%
  filter(Tstart_new <= 12 & Tstop_new > 12) %>%
  # Identify their current state based on their available transitions at this time
  group_by(id) %>%
  slice(1) # Takes one representative row per person to check their current state profile
