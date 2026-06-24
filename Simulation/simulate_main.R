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
