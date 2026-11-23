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

first_trials <- TRUE
LM_start <- 0
LM_end <- 365
grace <- 45
LM_end_anal <- "_lastpu_" #"_lastpu_" "_lastatd_" "_lastsri_" 
load(file=paste0("./sasdata1/MRow_data", LM_end_anal, grace, ".RData")) 
CR_anal <-"_survival";# "_survival" "_cr"

if (CR_anal=="_survival") {
  #no CR anal
  MRow_data <- MRow_data %>%
    mutate(event_num=case_when(
      event_num==0 | event_num==4 ~ 0,
      TRUE ~ 1
    ))
} else if (CR_anal=="_cr") {
  MRow_data <- MRow_data %>%
    mutate(event_num=case_when(
      event_num==0 | event_num==4 ~ 0,
      TRUE ~ as.numeric(event_num)
    ))
}

#recode all Nos with zeros
MRow_data <- MRow_data %>%
  mutate(
    across(
      where(~ is.character(.x) || is.factor(.x)),
      ~ if_else(as.character(.x) == "No", "0", as.character(.x))
    )
  )

bsl_cat_set <- c("First_Prescriber", 
                 
                 "HasALDNonPsy", "HasALDPsy", "HasATMPInvAAH","HasC2S",
                 
                 select(MRow_data,all_of(ends_with("_cat",ignore.case = FALSE))) %>% colnames(), #BEN_AMA_COD_cat
                 
                 select(MRow_data,all_of(starts_with(c("TPS_","PSY_","Prev_Psy_Adm"),ignore.case = FALSE))) %>% colnames(),#5 var
                 
                 select(MRow_data,all_of(ends_with("_Length",ignore.case = FALSE))) %>% colnames(),#MCO_SSR_HAD_Length RIP_Length
                 
                 "Pregnant", 
                 
                 "season_year", "region", "FDEP20_quint"
)

bsl_num_set <- c( 
  # BEN_AMA_COD
  
  "CumulAnx", "CumulOtherMeds", "CumulGP", "CumulPsych", "CumulOtherMed", "CumulNonMed", 
  
  "P20_POP","Nb_GP", "Nb_Psych"
) 

all_covar <- c(bsl_cat_set, bsl_num_set
)

formula_surv_models  <<- as.formula(paste0("Surv(start, stop, event_num) ~ ", paste0(all_covar, collapse = " + ")))

#as factor exposure
MRow_data$First_Prescriber <- factor(MRow_data$First_Prescriber, levels = c("GP", "Other", "Psych"))

# IPW ----

den_formula <-as.formula(paste0("~ ", paste0(all_covar, collapse = " + ")))
temp <- ipwtm(
  exposure = First_Prescriber,
  family = "multinomial",
  numerator = ~ 1,
  denominator = ~ HasALDNonPsy + HasALDPsy + HasATMPInvAAH + 
    HasC2S + BEN_AMA_COD_cat + PSY_DEP_NEV_ADR_SED + PSY_PSC_BIP_NLE + 
    PSY_ADD + PSY_AU + Prev_Psy_Adm + MCO_SSR_HAD_Length + RIP_Length + 
    Pregnant + season_year + region + FDEP20_quint + CumulAnx + 
    CumulOtherMeds + CumulGP + CumulPsych + CumulOtherMed + CumulNonMed + 
    P20_POP + Nb_GP + Nb_Psych,
  id = BEN_IDT_ANO,
  timevar     = stop,
  type        = "first",## only "first" is implemented for multinomial in ipwtm()
  data = as.data.frame(MRow_data),
  trunc = 0.01
  )
summary(temp$ipw.weights)
summary(temp$weights.trunc)
hist(temp$weights.trunc)
MRow_data$w <- temp$weights.trunc

#Cox ----
if (CR_anal=="_survival") {
  cox_data <- MRow_data

  if (first_trials) {
    #just to see if it works
    cox_fit <- coxph(Surv(start,stop, event_num) ~ First_Prescriber , 
                     cluster=BEN_IDT_ANO,
                     weights = w,
                     data = cox_data )
    summary(cox_fit)
    y_hat <- predict(cox_fit)
    plot(cox_data$First_Prescriber, y_hat)
    
    # Loop through each covariate and run the bivariate Cox model
    biv_models <- lapply(bsl_set, function(covar) {
      # Dynamically construct the formula
      formula_str <- paste0("Surv(start, stop, event_num) ~ ", covar)
      
      # Fit the model
      coxph(as.formula(formula_str), data = cox_data, cluster=BEN_IDT_ANO,
            weights = w)
    })
    names(biv_models) <- bsl_set
  }
  
  #multivar model
  cox_fit <- coxph(formula_surv_models , 
                   #id=BEN_IDT_ANO, #necessary if more than one event type
                   robust=T,
                   cluster=BEN_IDT_ANO,
                   weights = cox_data$w,
                   data = cox_data %>% 
                     select(event_num, start, stop, all_of(all_covar),BEN_IDT_ANO)
  )
  summary(cox_fit)
  cox.zph(cox_fit)
}

#competing risk ----
