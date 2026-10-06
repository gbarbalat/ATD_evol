/* Macro variable for 01JAN2015 start threshold */
%let cutoff_start = %sysfunc(inputn(01JAN2015:00:00:00, datetime20.));

/* Macro variables matching your environment setup */
%let start     = 01JAN2015:00:00:00;
%let end       = 31DEC2016:23:59:59;
%let grace = %eval(365*2);  

%let exe_start = %sysfunc(inputn(&start, datetime20.));
%let exe_end   = %sysfunc(inputn(&end, datetime20.));

/* Format definition for Datetime handling 
format dt_first_ad DATETIME20.;*/

/* Step 1: Find First Antidepressant Date per Beneficiary & Append to FC1_1 */

/* 1a. Extract earliest antidepressant date per BEN_IDT_ANO >= 01JAN2015 */
proc sql;
   create table work.first_ad_date as
   select BEN_IDT_ANO, 
          min(EXE_SOI_DTD) format=DATETIME20. as dt_first_ad_dt,
          datepart(min(EXE_SOI_DTD)) format=YYMMDD10. as dt_first_ad
   from sasdata1.FC1_2
   where upcase(PHA_ATC_CLA) like 'N06A%'
     and EXE_SOI_DTD >= &cutoff_start.
   group by BEN_IDT_ANO;
quit;

/* 1b. Append date to FC1_1 */
proc sql;
   create table sasdata1.fc1_1_with_dt as
   select a.*, 
          b.dt_first_ad_dt,
          b.dt_first_ad
   from sasdata1.FC1_1 as a
   left join work.first_ad_date as b
     on a.BEN_IDT_ANO = b.BEN_IDT_ANO;
quit;

/* Step 2:For individuals whose first antidepressant prescription occurred 2 years before last atd prescription in FC1_2.
Exclude those individuals */

proc sql;
   create table work.excl_prior_ad as
   select distinct f1.BEN_IDT_ANO
   from sasdata1.fc1_1_with_dt as f1
   inner join sasdata1.FC1_2 as f2
      on f1.BEN_IDT_ANO = f2.BEN_IDT_ANO
   where f1.dt_first_ad_dt >= &exe_start. 
     and f1.dt_first_ad_dt <= &exe_end.
     and upcase(f2.PHA_ATC_CLA) like 'N06A%'
     and datepart(f2.EXE_SOI_DTD) < f1.dt_first_ad
     and datepart(f2.EXE_SOI_DTD) >= (f1.dt_first_ad - &grace.);
quit;

proc sql;
   create table sasdata1.FC2 as
   select *
   from sasdata1.fc1_1_with_dt
   where BEN_IDT_ANO not in (select BEN_IDT_ANO from work.excl_prior_ad);
quit;

/* Step 3:From FC2, check FC1_3, FC1_4, FC1_5, and FC1_6 for any diagnosis code starting with "F" that occurred prior to their first ATD prescription. Exclude those individuals 
Unfortunately, no dx in FC1_5
*/

proc sql;
   create table work.excl_prior_f_dx as
   select distinct BEN_IDT_ANO
   from (
      /* FC1_3: Any event prior to dt_first_ad (whatever the diagnosis) */
      select fc2.BEN_IDT_ANO
      from sasdata1.FC2 as fc2
      inner join sasdata1.FC1_3 as f3
         on fc2.BEN_IDT_ANO = f3.BEN_IDT_ANO
      where datepart(f3.EXE_SOI_DTD) < fc2.dt_first_ad

      union

      /* FC1_4: Prior event with DGN_PAL starting with F */
      select fc2.BEN_IDT_ANO
      from sasdata1.FC2 as fc2
      inner join sasdata1.FC1_4 as f4
         on fc2.BEN_IDT_ANO = f4.BEN_IDT_ANO
      where datepart(f4.EXE_SOI_DTD) < fc2.dt_first_ad
        and upcase(f4.DGN_PAL) like 'F%'

      union

      /* FC1_6: Prior event with DGN_PAL starting with F */
      select fc2.BEN_IDT_ANO
      from sasdata1.FC2 as fc2
      inner join sasdata1.FC1_6 as f6
         on fc2.BEN_IDT_ANO = f6.BEN_IDT_ANO
      where datepart(f6.EXE_SOI_DTD) < fc2.dt_first_ad
        and upcase(f6.DGN_PAL) like 'F%'
   );

   /* Create FC3 by removing excluded beneficiaries from FC2 */
   create table sasdata1.FC3 as
   select *
   from sasdata1.FC2
   where BEN_IDT_ANO not in (select BEN_IDT_ANO from work.excl_prior_f_dx);
quit;

/* Step 4:From FC3, check FC1_2 for any non-antidepressant drug (PHA_ATC_CLA not starting with "N06A") dispensed prior to their first ATD prescription. Exclude those individuals */
/* 4a. Identify IDs in FC3 with specified prior psychotropic drugs in FC1_2 */
proc sql;
   create table work.excl_prior_other_drugs as
   select distinct fc3.BEN_IDT_ANO
   from sasdata1.FC3 as fc3
   inner join sasdata1.FC1_2 as f2
      on fc3.BEN_IDT_ANO = f2.BEN_IDT_ANO
   where datepart(f2.EXE_SOI_DTD) < fc3.dt_first_ad
     and (
            upcase(f2.PHA_ATC_CLA) like 'N05A%'  /* Antipsychotics */
         or upcase(f2.PHA_ATC_CLA) like 'N06BA%' /* Psychostimulants */
         /* or upcase(f2.PHA_ATC_CLA) like 'N05B%'   Anxiolytics 
         or upcase(f2.PHA_ATC_CLA) like 'N05C%'   Hypnotics/Sedatives */
         or upcase(f2.PHA_ATC_CLA) like 'N03A%'  /* Antiepileptics */
     );

/* 4b. Create FC4 directly from FC3 */
   create table sasdata1.FC4 as
   select *
   from sasdata1.FC3
   where BEN_IDT_ANO not in (select BEN_IDT_ANO from work.excl_prior_other_drugs);
quit;

/* Step 5:From FC4, check FC1_2 for any non-antidepressant drug (PHA_ATC_CLA not starting with "N06A") dispensed prior to their first ATD prescription. Exclude those individuals */

