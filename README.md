Factors influencing ATD pick up in women with child-bearing potential.  

Create_Cohort: SAS scripts  
gather dbs and preprocess according to flowchart  
dbs are too heavy to be processed on R  

Then R is used once db are well-filtered for processing and analysis  
analysis on the SNDS server, using survival package and coxph function.  

Main measures:  
- outcome: pick up dates, events being SSRI, ATD_OTH, SWI_CLA
- prescriber, and prescribing hx
- idx of severity
- socio-demo and socio-eco (FDep, C2S)
- healthcare consumption

Final dataframe 
- event
- tstart and tstop
- bsl covariates and time dependent; some would imply recurrence and cumsum

Cohort
-  Women 18-39
-  first SSRI = clock in
-  No ATDs, Antipsychotics, Lithium, AntiEpileptics, Stimulants, in previous year

Temporality
- Cohort selected in 2022-2023
- followed up for one year, up to last appearance in SNDS, or death (whichever comes first)


