rm(list=ls())

library(mstate)
library(survival)

# ==========================================
# 1. DEFINE THE COMPLETE REVERSIBLE MATRIX
# ==========================================
tmat <- transMat(x = list(
  c(2, 3, 5),    # 1. On_ATD_NoPreg   -> Off_ATD_NoPreg (2), Preg_On_ATD (3), Death (5)
  c(1, 4, 5),    # 2. Off_ATD_NoPreg  -> On_ATD_NoPreg (1), Preg_Off_ATD (4), Death (5)
  c(1, 4, 5),    # 3. Preg_On_ATD     -> On_ATD_NoPreg [Delivery] (1), Preg_Off_ATD [Stop Meds] (4), Death (5)
  c(2, 3, 5),    # 4. Pregnant_Off_ATD-> Off_ATD_NoPreg [Delivery] (2), Preg_On_ATD [Start Meds] (3), Death (5)
  NULL           # 5. Death           -> Pure absorbing state
), names = c("On_ATD_NoPreg", "Off_ATD_NoPreg", "Preg_On_ATD", "Preg_Off_ATD", "Death"))

print(tmat)

# ==========================================
# 2. SIMULATE FULL HISTORY (FIXED GESTATIONAL CLOCK)
# ==========================================
set.seed(42)
n <- 1000
max_followup <- 60 

long_rows <- list()

for (i in 1:n) {
  current_time <- 0
  current_state <- 1 
  age_baseline <- runif(1, 20, 40)
  
  # Track remaining pregnancy duration globally across mid-pregnancy transitions
  pregnancy_time_left <- 0
  
  individual_censor_time <- pmin(rexp(1, rate = 0.004), max_followup)
  if(individual_censor_time == 0) individual_censor_time <- max_followup
  
  while (current_time < individual_censor_time) {
    
    # STATE 1: On ATD, Not Pregnant
    if (current_state == 1) {
      t_to_2 <- rexp(1, rate = 0.08)  # Stop ATD
      t_to_3 <- rexp(1, rate = 0.04)  # Get Pregnant
      t_to_5 <- rexp(1, rate = 0.002) # Die
      
      delta <- pmin(t_to_2, t_to_3, t_to_5)
      evt_time <- current_time + delta
      
      if (evt_time >= individual_censor_time) {
        for(tr in 1:3) long_rows[[length(long_rows) + 1]] <- data.frame(id=i, Tstart=current_time, Tstop=individual_censor_time, trans=tr, status=0, age=age_baseline)
        current_time <- individual_censor_time
      } else {
        s2 <- ifelse(delta == t_to_2, 1, 0); s3 <- ifelse(delta == t_to_3, 1, 0); s5 <- ifelse(delta == t_to_5, 1, 0)
        for(tr in 1:3) long_rows[[length(long_rows) + 1]] <- data.frame(id=i, Tstart=current_time, Tstop=evt_time, trans=tr, status=ifelse(tr==1, s2, ifelse(tr==2, s3, s5)), age=age_baseline)
        
        if (s3 == 1) { pregnancy_time_left <- runif(1, 8, 10) }
        
        current_time <- evt_time
        current_state <- ifelse(s2==1, 2, ifelse(s3==1, 3, 5))
      }
      
      # STATE 2: Off ATD, Not Pregnant
    } else if (current_state == 2) {
      t_to_1 <- rexp(1, rate = 0.10)  # Restart ATD
      t_to_4 <- rexp(1, rate = 0.03)  # Get Pregnant
      t_to_5 <- rexp(1, rate = 0.002) # Die
      
      delta <- pmin(t_to_1, t_to_4, t_to_5)
      evt_time <- current_time + delta
      
      if (evt_time >= individual_censor_time) {
        for(tr in 4:6) long_rows[[length(long_rows) + 1]] <- data.frame(id=i, Tstart=current_time, Tstop=individual_censor_time, trans=tr, status=0, age=age_baseline)
        current_time <- individual_censor_time
      } else {
        s1 <- ifelse(delta == t_to_1, 1, 0); s4 <- ifelse(delta == t_to_4, 1, 0); s5 <- ifelse(delta == t_to_5, 1, 0)
        for(tr in 4:6) long_rows[[length(long_rows) + 1]] <- data.frame(id=i, Tstart=current_time, Tstop=evt_time, trans=tr, status=ifelse(tr==4, s1, ifelse(tr==5, s4, s5)), age=age_baseline)
        
        if (s4 == 1) { pregnancy_time_left <- runif(1, 8, 10) }
        
        current_time <- evt_time
        current_state <- ifelse(s1==1, 1, ifelse(s4==1, 4, 5))
      }
      
      # STATE 3: Pregnant and On ATD
    } else if (current_state == 3) {
      t_to_1 <- pregnancy_time_left   
      t_to_4 <- rexp(1, rate = 0.15)  
      t_to_5 <- rexp(1, rate = 0.001) 
      
      delta <- pmin(t_to_1, t_to_4, t_to_5)
      evt_time <- current_time + delta
      
      if (evt_time >= individual_censor_time) {
        for(tr in 7:9) long_rows[[length(long_rows) + 1]] <- data.frame(id=i, Tstart=current_time, Tstop=individual_censor_time, trans=tr, status=0, age=age_baseline)
        current_time <- individual_censor_time
      } else {
        s1 <- ifelse(delta == t_to_1, 1, 0); s4 <- ifelse(delta == t_to_4, 1, 0); s5 <- ifelse(delta == t_to_5, 1, 0)
        for(tr in 7:9) long_rows[[length(long_rows) + 1]] <- data.frame(id=i, Tstart=current_time, Tstop=evt_time, trans=tr, status=ifelse(tr==7, s1, ifelse(tr==8, s4, s5)), age=age_baseline)
        
        pregnancy_time_left <- pregnancy_time_left - delta
        
        current_time <- evt_time
        current_state <- ifelse(s1==1, 1, ifelse(s4==1, 4, 5))
      }
      
      # STATE 4: Pregnant and Off ATD
    } else if (current_state == 4) {
      t_to_2 <- pregnancy_time_left   
      t_to_3 <- rexp(1, rate = 0.05)  
      t_to_5 <- rexp(1, rate = 0.001) 
      
      delta <- pmin(t_to_2, t_to_3, t_to_5)
      evt_time <- current_time + delta
      
      if (evt_time >= individual_censor_time) {
        for(tr in 10:12) long_rows[[length(long_rows) + 1]] <- data.frame(id=i, Tstart=current_time, Tstop=individual_censor_time, trans=tr, status=0, age=age_baseline)
        current_time <- individual_censor_time
      } else {
        s2 <- ifelse(delta == t_to_2, 1, 0); s3 <- ifelse(delta == t_to_3, 1, 0); s5 <- ifelse(delta == t_to_5, 1, 0)
        for(tr in 10:12) long_rows[[length(long_rows) + 1]] <- data.frame(id=i, Tstart=current_time, Tstop=evt_time, trans=tr, status=ifelse(tr==10, s2, ifelse(tr==11, s3, s5)), age=age_baseline)
        
        pregnancy_time_left <- pregnancy_time_left - delta
        
        current_time <- evt_time
        current_state <- ifelse(s2==1, 2, ifelse(s3==1, 3, 5))
      }
      
    } else {
      break
    }
  }
}

ms_ultimate_long <- do.call(rbind, long_rows)
class(ms_ultimate_long) <- c("msdata", "data.frame")
attr(ms_ultimate_long, "trans") <- tmat

# ==========================================
# 3. MODEL ESTIMATION (FIXED PROPER CLUSTER SYNTAX)
# ==========================================
fit_ultimate <- coxph(
  Surv(Tstart, Tstop, status) ~ age + strata(trans) + cluster(id), # Corrected placement
  data = ms_ultimate_long, 
  method = "breslow"
)

pat_profile <- data.frame(age = rep(mean(ms_ultimate_long$age), 12), trans = 1:12, strata = 1:12)
ms_hazards  <- msfit(object = fit_ultimate, newdata = pat_profile, trans = tmat)

# ==========================================
# 4. PROBABILITY MATRICES GENERATION
# ==========================================
# Baseline tracking for the full cohort (starts at Month 0)
prob_matrix_baseline <- probtrans(ms_hazards, predt = 0)

# Mid-study pregnancy detection forecasting (starts at Month 12)
pregnancy_start_time <- 12
prob_matrix_preg     <- probtrans(ms_hazards, predt = pregnancy_start_time, direction = "forward")

# ==========================================
# 5. INTEGRATED VISUALIZATION GRID
# ==========================================
# Adjust layout to fit 3 panels side-by-side
par(mfrow = c(1, 3))

state_colors <- c("#4A90E2", "#FFA500", "#2E7D32", "#81C784", "#C62828")
state_labels <- attr(tmat, "dimnames")[[1]]

# Panel 1: Complete Cohort Trajectory from Inception
plot(
  prob_matrix_baseline, 
  from = 1,                      # Starts everyone in State 1 (On_ATD_NoPreg) at Month 0
  ord = c(1, 2, 3, 4, 5), 
  col = state_colors, 
  xlab = "Months of Follow-up", 
  ylab = "Population Proportion", 
  main = "1. Overall Cohort Journey\n(From Baseline)"
)
legend("topright", legend = state_labels, fill = state_colors, cex = 0.55, bty = "n")

# Panel 2: Scenario A (Conditioned on being Pregnant & ON ATD at Month 12)
plot(
  prob_matrix_preg, 
  from = 3,                      # Forces state index 3 at Month 12
  ord = c(3, 4, 1, 2, 5), 
  col = state_colors, 
  xlab = "Months of Follow-up", 
  ylab = "State Probability", 
  main = "2. Scenario A: Pregnant & ON ATD\n(Trajectory from Month 12)"
)
legend("topright", legend = state_labels, fill = state_colors, cex = 0.55, bty = "n")

# Panel 3: Scenario B (Conditioned on being Pregnant & OFF ATD at Month 12)
plot(
  prob_matrix_preg, 
  from = 4,                      # Forces state index 4 at Month 12
  ord = c(3, 4, 1, 2, 5), 
  col = state_colors, 
  xlab = "Months of Follow-up", 
  ylab = "State Probability", 
  main = "3. Scenario B: Pregnant & OFF ATD\n(Trajectory from Month 12)"
)
legend("topright", legend = state_labels, fill = state_colors, cex = 0.55, bty = "n")

# Restore single plot display default
par(mfrow = c(1, 1))
