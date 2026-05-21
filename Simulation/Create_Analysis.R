# -------------------------------------------------------------------------
# 1. Load Required Libraries & Set Seed
# -------------------------------------------------------------------------
if (!requireNamespace("msm", quietly = TRUE)) install.packages("msm")
library(msm)
set.seed(42)

# -------------------------------------------------------------------------
# 2. Simulate Synthetic Multi-State Data
# -------------------------------------------------------------------------
# Setup parameters
n_patients <- 200
max_visits <- 5

# Create a baseline dataframe
data_list <- list()

for (i in 1:n_patients) {
  # Generate a random number of scheduled visits for this patient (2 to 5)
  n_vis <- sample(2:max_visits, 1)
  
  # Time of visits (strictly increasing)
  years <- sort(runif(n_vis, 0, 4))
  
  # Baseline Intervention (5 distinct categories: A, B, C, D, E)
  intervention <- sample(c("A", "B", "C", "D", "E"), 1)
  
  # Simulate states (1 = Health, 2 = Illness, 3 = Death)
  # For simplicity, we ensure states are generally forward-progressing
  states <- numeric(n_vis)
  states[1] <- 1  # Everyone starts healthy
  for (v in 2:n_vis) {
    # Simple probability transition rule to simulate realistic sequences
    if (states[v-1] == 1) {
      states[v] <- sample(1:3, 1, prob = c(0.6, 0.3, 0.1))
    } else if (states[v-1] == 2) {
      states[v] <- sample(2:3, 1, prob = c(0.7, 0.3)) # State 3 is absorbing
    } else {
      states[v] <- 3 # Dead stays dead
    }
  }
  
  # Generate Time-Dependent Covariates (values change at each visit)
  td_cov1 <- rnorm(n_vis, mean = 50, sd = 10)  # e.g., Continuous biomarker
  td_cov2 <- rbinom(n_vis, 1, prob = 0.4)       # e.g., Binary medication flag
  
  # Assemble patient dataframe
  data_list[[i]] <- data.frame(
    id = i,
    years = years,
    state = states,
    intervention = factor(intervention, levels = c("A", "B", "C", "D", "E")),
    td_cov1 = td_cov1,
    td_cov2 = td_cov2
  )
}

# Combine into a final longitudinal dataset
df_msm <- do.call(rbind, data_list)

# Clean up absorbing state records (no visits tracked after death)
df_msm <- df_msm[!duplicated(interaction(df_msm$id, df_msm$state == 3)) | df_msm$state != 3, ]

print("Data simulation complete. Previewing first few rows:")
print(head(df_msm, 10))

# -------------------------------------------------------------------------
# 3. Define the Transition Matrix (Q-Matrix)
# -------------------------------------------------------------------------
# 0 means transition is impossible, non-zero initial guesses for allowed ones
# 1 -> 2 (Health to Illness), 1 -> 3 (Health to Death), 2 -> 3 (Illness to Death)
q_initial <- matrix(c(
  0, 0.2, 0.1,
  0,   0, 0.3,
  0,   0,   0
), nrow = 3, byrow = TRUE)

# -------------------------------------------------------------------------
# 4. Fit the Model with Covariates and Interactions
# -------------------------------------------------------------------------
# We model the hazard rates using our covariates.
# To check interactions between intervention categories and time-dependent covariates,
# we pass the formula syntax directly into the covariates argument.

msm_model <- msm(
  state ~ years, 
  subject = id, 
  data = df_msm, 
  qmatrix = q_initial,
  covariates = ~ intervention * td_cov1 + td_cov2
)

# -------------------------------------------------------------------------
# 5. Extract and Analyze Results
# -------------------------------------------------------------------------
cat("\n==================================================\n")
cat("1. ESTIMATED TRANSITION INTENSITY MATRIX (Q)\n")
cat("==================================================\n")
print(qmatrix.msm(msm_model))

cat("\n==================================================\n")
cat("2. HAZARD RATIOS FOR COVARIATES AND INTERACTIONS\n")
cat("==================================================\n")
# This provides the effect of the 5 categories (B, C, D, E vs reference A), 
# the time-dependent covariates, and their interaction terms.
print(hazard.msm(msm_model))
