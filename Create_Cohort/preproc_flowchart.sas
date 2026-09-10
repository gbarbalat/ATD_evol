/* Step 1: Find First Antidepressant Date per Beneficiary & Append to FC1_1 */

/* 1a. Extract earliest antidepressant date per BEN_IDT_ANO */
proc sql;
   create table work.first_ad_date as
   select BEN_IDT_ANO, 
          min(EXE_SOI_DTD) as dt_first_ad format=YYMMDD10.
   from sasdata1.FC1_2
   where upcase(PHA_ATC_CLA) like 'N06A%'
   group by BEN_IDT_ANO;
quit;

/* 1b. Merge dt_first_ad onto FC1_1 */
proc sql;
   create table work.fc1_1_with_dt as
   select a.*, 
          b.dt_first_ad
   from sasdata1.FC1_1 as a
   left join work.first_ad_date as b
     on a.BEN_IDT_ANO = b.BEN_IDT_ANO;
quit;

/* Step 2:For individuals whose first antidepressant prescription occurred in 2015, check FC1_2 for any antidepressant (N06A) in the 2-year lookback window. Exclude those individuals */
/* 2a. Identify individuals in 2015 with antidepressant use in the 2 years prior */
proc sql;
   create table work.excl_prior_ad as
   select distinct f1.BEN_IDT_ANO
   from work.fc1_1_with_dt as f1
   inner join sasdata1.FC1_2 as f2
      on f1.BEN_IDT_ANO = f2.BEN_IDT_ANO
   where year(f1.dt_first_ad) = 2015
     and upcase(f2.PHA_ATC_CLA) like 'N06A%'
     and f2.EXE_SOI_DTD < f1.dt_first_ad
     and f2.EXE_SOI_DTD >= intnx('year', f1.dt_first_ad, -2, 'same');
quit;

/* 2b. Build FC2 by excluding those individuals */
proc sql;
   create table sasdata1.FC2 as
   select *
   from work.fc1_1_with_dt
   where BEN_IDT_ANO not in (select BEN_IDT_ANO from work.excl_prior_ad);
quit;

/* Step 3:From FC2, check FC1_3, FC1_4, FC1_5, and FC1_6 for any diagnosis code starting with "F" that occurred prior to their first ATD prescription. Exclude those individuals */
/* 3a. Union diagnostic tables and find IDs with prior 'F' diagnoses */
proc sql;
   create table work.excl_prior_f_dx as
   select distinct fc2.BEN_IDT_ANO
   from sasdata1.FC2 as fc2
   inner join (
      select BEN_IDT_ANO, EXE_SOI_DTD, dx from sasdata1.FC1_3
      union all
      select BEN_IDT_ANO, EXE_SOI_DTD, dx from sasdata1.FC1_4
      union all
      select BEN_IDT_ANO, EXE_SOI_DTD, dx from sasdata1.FC1_5
      union all
      select BEN_IDT_ANO, EXE_SOI_DTD, dx from sasdata1.FC1_6
   ) as dx_all
      on fc2.BEN_IDT_ANO = dx_all.BEN_IDT_ANO
   where upcase(dx_all.dx) like 'F%'
     and dx_all.EXE_SOI_DTD < fc2.dt_first_ad;
quit;

/* 3b. Build FC3 */
proc sql;
   create table sasdata1.FC3 as
   select *
   from sasdata1.FC2
   where BEN_IDT_ANO not in (select BEN_IDT_ANO from work.excl_prior_f_dx);
quit;


