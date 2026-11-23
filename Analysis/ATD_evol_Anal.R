#hdr ----
rm(list=ls())

library(haven)
library(data.table)
library(dplyr)
library(lubridate)
library(stringr)
library(purrr)
library(ggplot2)
library(survival)
library(ranger)
library(prodlim)
library(caret)

ML<-FALSE
first_trials <- FALSE
LM_start <- 0
LM_end <- 365
grace <- 45
LM_end_anal <- "_lastpu_" #"_lastpu_" "_lastatd_" "_lastsri_" 
load(file=paste0("./sasdata1/collapsed_data", LM_end_anal, grace, ".RData")) 
CR_anal <-"_survival";# "_survival" "_cr"
POGEE_IA <- FALSE

if (CR_anal=="_survival") {
#no CR anal
collapsed_data <- collapsed_data %>%
  mutate(event_num=case_when(
    event_num==0 | event_num==4 ~ 0,
    TRUE ~ 1
  ))
} else if (CR_anal=="_cr") {
  collapsed_data <- collapsed_data %>%
    mutate(event_num=case_when(
      event_num==0 | event_num==4 ~ 0,
      TRUE ~ as.numeric(event_num)
    ))
}

#recode all Nos with zeros
collapsed_data <- collapsed_data %>%
  mutate(
    across(
      where(~ is.character(.x) || is.factor(.x)),
      ~ if_else(as.character(.x) == "No", "0", as.character(.x))
    )
  )

bsl_cat_set <- c("First_Prescriber", 
                 
                 "HasALDNonPsy", "HasALDPsy", "HasATMPInvAAH","HasC2S",
     
     select(collapsed_data,all_of(ends_with("_cat",ignore.case = FALSE))) %>% colnames(),
     
     select(collapsed_data,all_of(starts_with(c("TPS_","PSY_","Prev_Psy_Adm"),ignore.case = FALSE))) %>% colnames(),

     select(collapsed_data,all_of(ends_with("_Length",ignore.case = FALSE))) %>% colnames(),
     
     "Pregnant", 
      
     "season_year", "region", "FDEP20_quint"
     )

bsl_num_set <- c( 
  "CumulAnx", "CumulOtherMeds", "CumulGP", "CumulPsych", "CumulOtherMed", "CumulNonMed", 
  
  "P20_POP","Nb_GP", "Nb_Psych"
) 

all_covar <- c(bsl_cat_set, bsl_num_set#, td_cat_set, td_num_set
)

formula_models  <<- as.formula(paste0("outcome ~ ", paste0(all_covar, collapse = " + ")))

formula_surv_models  <<- as.formula(paste0("Surv(stop, event_num) ~ ", paste0(all_covar, collapse = " + ")))



#KM ----
KM_data <- collapsed_data
KM_data$start <- LM_start
KM_fit <- survfit(Surv(start,stop, event_num) ~ 1, data=KM_data)
print(KM_fit, rmean=LM_end)

#Cox ----
if (CR_anal=="_survival") {
cox_data <- collapsed_data
cox_data$start <- LM_start

if (first_trials) {
#just to see if it works
cox_fit <- coxph(Surv(start,stop, event_num) ~ First_Prescriber + pspline(P20_POP,3), 
      data = cox_data )
summary(cox_fit)
y_hat <- predict(cox_fit)
plot(cox_data$P20_POP, y_hat)

# Loop through each covariate and run the bivariate Cox model
biv_models <- lapply(bsl_set, function(covar) {
  # Dynamically construct the formula
  formula_str <- paste0("Surv(start, stop, event_num) ~ ", covar)
  
  # Fit the model
  coxph(as.formula(formula_str), data = cox_data)
})
names(biv_models) <- bsl_set
}

#multivar model
cox_fit <- coxph(formula_surv_models , 
      data = cox_data %>% 
        select(event_num, start, stop, all_of(all_covar))
)
summary(cox_fit)
cox.zph(cox_fit)
plot(cox.zph(cox_fit))

}

# pseudo val ----
dt <-10 #computational issues if dt <- 1
tau <- max(collapsed_data$stop) #LM_end
times <- seq(0, tau, by = dt)  # discretized times up to restriction time tau
time <- collapsed_data$stop; 
pseudo <- function(data=collapsed_data, anal="RMST_survival", var="event_num", cause=1, weights = NULL) { 
  
  status <- data %>% select(var) %>% pull
  table(status, useNA="always")
  f <- prodlim(Hist(time, status)~1, data=data)
  pv <- jackknife(f, times = times, cause = cause)  # pseudo-values matrix: subjects x times
  head(pv) %>% print
  #same if CR model
  # but if CR: pv are CIF pseudo-values, have to transform to make it survival
  # Overall Survival (Non-Competing): pv are already survival pseudo-values - no transformation!!!
  
  ## RMST survival ----
  if (anal=="RMST_survival") {
    outcome <- apply(pv, 1, function(s) {
      sum(diff(times) * (head(s, -1) + tail(s, -1)) / 2)
    })
  } else if (anal=="RMST_cr") {
    ## RMST competing risks ----
    outcome <- apply(pv, 1, function(s) {
      surv_pv <- 1 - s  # CIF → survival
      sum(diff(times) * (head(surv_pv, -1) + tail(surv_pv, -1)) / 2)
    }) 
  }
  
  hist(outcome)
  return(outcome)
  
}
outcome1 <- pseudo(data=collapsed_data, anal=paste0("RMST", CR_anal), var="event_num",
                  cause=1)
# outcome2 <- pseudo(data=collapsed_data, anal=paste0("RMST", CR_anal), var="event_num",
#                    cause=2)
POGEE_data <- collapsed_data %>% 
  mutate(id=1:nrow(collapsed_data),
         outcome = outcome1
  )
summary(POGEE_data$outcome)

# POGEE_data1 <- collapsed_data %>% 
#   mutate(id=1:nrow(collapsed_data),
#          outcome = case_when(round(outcome)==0 ~ 0, 
#                              TRUE ~ 1)
#   )
# hist(POGEE_data1$outcome)
# 
# POGEE_data2 <- collapsed_data %>% 
#   mutate(outcome=outcome) %>%
#   filter(round(outcome)!=0) 
# POGEE_data2$id <- 1:nrow(POGEE_data2)
# hist(POGEE_data2$outcome)
# summary(POGEE_data2$outcome)

## db for IA ----
if (POGEE_IA) {
  if (!"id" %in% names(collapsed_data)) {
    collapsed_data$id <- seq_len(nrow(collapsed_data))
  }
  
  # 2. Build the Event 1 (Discontinuation) subset
  df_cause1 <- collapsed_data %>%
    select(id, all_of(all_covar)) %>%
    mutate(
      cause = "Event1", 
      pseudo_val = outcome1
    )
  
  # 3. Build the Event 2 (Switching) subset
  df_cause2 <- collapsed_data %>%
    select(id, all_of(all_covar)) %>%
    mutate(
      cause = "Event2", 
      pseudo_val = outcome2
    )
  
  # 4. Stack them together into POGEE_data_IA
  POGEE_data_IA <- bind_rows(df_cause1, df_cause2) %>%
    mutate(
      cause = factor(cause, levels = c("Event1", "Event2")) # Set Event1 as baseline reference
    )
  
  # Quick check of your stacked structure (should have 2 * nrow(collapsed_data) rows)
  dim(POGEE_data_IA)
  head(POGEE_data_IA)
}

#POGEE IA ----
if (POGEE_IA) {
formula_IA <- as.formula(
  paste("pseudo_val ~ cause + (", paste(all_covar, collapse = " + "), ") * cause")
)

gee_model <- geepack::geeglm(formula_IA  ,
                             id=id,
                             weights = NULL,#NULL,#sw,
                             data = POGEE_data_IA, 
                             corstr = "exchangeable",
                            family = gaussian #Gamma(link = "log") gaussian
) 
summary(gee_model)
}

# PO-GEE ----

formula_IA <- as.formula(
  paste("outcome1 ~  (", paste(all_covar, collapse = " + "), ") * First_Prescriber")
)
formula_IA <- as.formula(
  outcome1 ~ First_Prescriber + Prev_ALDNonPsy + Prev_ALDPsy + 
    Prev_ATMPInvAAH + Prev_C2S + BEN_AMA_COD_cat + CumulPrev_Anx_cat + 
    CumulPrev_Meds_cat + CumulPrev_SeenGP_cat + CumulPrev_SeenNonMed_cat + 
    CumulPrev_SeenOtherMed_cat + CumulPrev_SeenPsych_cat + P20_POP_cat + 
    Nb_GP_cat + Nb_Psych_cat + TPS_NLE + TPS_ADR + TPS_SED + 
    PSY_ADD_TAB + PSY_ADD_AU + PSY_PSC_BIP + PSY_DEP_NEV + PSY_AU + 
    Prev_Pregnant + Prev_Psy_Adm + season_year + region + FDEP20_quint +
    First_Prescriber : FDEP20_quint
)
gee_model <- geepack::geeglm(formula_models, #formula_IA formula_models
                             id=id,
                             weights = NULL,#NULL,#sw,
                             data = POGEE_data, 
                             corstr = "independence",
                             family = gaussian #Gamma(link = "log") gaussian
) 
summary(gee_model)


# PVML ----
if (ML) {
error    <- rep(0, length(bsl_set))
mtry_vec <- 1:(length(bsl_set))
folds <- createFolds(1:nrow(POGEE_data), k = 5, list = FALSE, returnTrain = FALSE)
#folds    <- chunk(1:nrow(collapsed_data), n.chunks = 5)
for(mtry in (mtry_vec)) {
  print(mtry)
  error_inner <- rep(0,5)
  for(k in 1:5) {
    
    d_train <- POGEE_data %>% select(all_of(all_covar), id, outcome) %>%
      slice(which(folds != k))
    
    d_test <- POGEE_data %>% select(all_of(all_covar), id, outcome) %>%
      slice(which(folds == k))
    
    rforest     <- ranger(formula = formula_models, data = d_train %>% na.omit, 
                          replace = FALSE, mtry = NULL) #, importance="permutation"
    rforest; #rforest$variable.importance#OOB performance
    preds       <- predict(rforest, data = d_test)$predictions
    error_inner[k] <- mean((d_test$outcome - preds)^2)
    R2(d_test$outcome , preds)
    
    #survival forest
    rforest_survival <- ranger(formula = formula_surv_models, data = cox_data %>% slice_sample(n=100000), 
                               replace = FALSE, mtry = NULL, importance="permutation")
    rforest_survival
    plot(rforest_survival$unique.death.times, rforest_survival$survival[1,])

    #glmnet
    train(formula = formula_models, data = d_train %>% na.omit, method="glmnet")
  }
  
  error[mtry] <- mean(error_inner)
  
}

mtry_opt <- mtry_vec[which.min(error)]

rforest           <- ranger(formula = formula_models, 
                            data = collapsed_data, #train, test, eval rather than total sample!!!!!
                            replace = FALSE, mtry = NULL)
RMST_rforest      <- predict(rforest, data = collapsed_data)$predictions


#pdp way too long 
#pdp::partial(rforest, pred.var = "Nb_Psych", prob = TRUE, which.class = "pos",plot = TRUE, rug = TRUE, train = d_train)
}


#PV-lmtp ----

