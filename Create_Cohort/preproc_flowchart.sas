/* Macro variable for date start threshold */
%let cutoff_start = %sysfunc(inputn(01JAN2022:00:00:00, datetime20.));

/* Macro variables matching your environment setup */
%let start     = 01JAN2015:00:00:00;
%let end       = 31DEC2016:23:59:59;
%let grace = %eval(30);  

%let exe_start = %sysfunc(inputn(&start, datetime20.));
%let exe_end   = %sysfunc(inputn(&end, datetime20.));

/* Format definition for Datetime handling 
format dt_first_ad DATETIME20.;*/

/* Find First Antidepressant Date per Beneficiary  */
proc sql;
   create table work.first_ad_date as
   select *, 
          min(EXE_SOI_DTD) format=DATETIME20. as dt_first_ad_dt,
          datepart(min(EXE_SOI_DTD)) format=YYMMDD10. as dt_first_ad
   from sasdata1.FC1_2
   where upcase(PHA_ATC_CLA) like 'N06AB%'
     and EXE_SOI_DTD >= &cutoff_start.
   group by BEN_IDT_ANO;
quit;

/* Append date to FC1_1 */
proc sql;
   create table sasdata1.fc1_1_with_dt as
   select a.*, 
          b.dt_first_ad_dt,
          b.dt_first_ad
   from orauser.FC1_1 as a
   inner join work.first_ad_date as b
     on a.BEN_IDT_ANO = b.BEN_IDT_ANO;
quit;

/* Take individuals whose first antidepressant prescription occurred after other psychotropic prescription in FC1_2 */
proc sql;
   create table work.excl_prior_ad as
   select distinct f1.BEN_IDT_ANO
   from sasdata1.fc1_1_with_dt as f1
   inner join sasdata1.FC1_2 as f2
      on f1.BEN_IDT_ANO = f2.BEN_IDT_ANO
   where (
          (datepart(f2.EXE_SOI_DTD) - f1.dt_first_ad >= -365 
           and datepart(f2.EXE_SOI_DTD) - f1.dt_first_ad < 0)
          
          /* Grace period window: 0 to &grace days, EXCLUDING SSRIs (N06AB%) */
          or 
          (datepart(f2.EXE_SOI_DTD) - f1.dt_first_ad >= 0 
           and datepart(f2.EXE_SOI_DTD) - f1.dt_first_ad <= &grace. 
           and upcase(f2.PHA_ATC_CLA) not like 'N06AB%')
         );
quit;

/* Remove these individuals */
proc sql;
   create table orauser.FC2 as
   select distinct BEN_IDT_ANO
   from sasdata1.fc1_1_with_dt
   where BEN_IDT_ANO not in (select BEN_IDT_ANO from work.excl_prior_ad);
quit;
