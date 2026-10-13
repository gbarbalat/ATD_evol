/* Step 1: Extract the first 10 distinct beneficiaries and their DT_FIRST_AD */
proc sql outobs=10;
   create table work.top10_ids as
   select distinct BEN_IDT_ANO, DT_FIRST_AD
   from sasdata1.prs_rx;
quit;

/* Step 2: Join back to prs_rx to get candidate antidepressant lines on or after DT_FIRST_AD */
proc sql;
   create table work.filtered_prs as
   select 
      t.BEN_IDT_ANO,
      t.DT_FIRST_AD,
	  r.BEN_AMA_COD,
	  r.BEN_RES_DPT,
	  r.BEN_RES_COM,
      r.EXE_SOI_DTD,
      r.PHA_ATC_CLA,
      r.PHA_ATC_LIB, 
	  r.PHA_ACT_QSN,
	  r.PSP_SPE_COD,
	  r.PSP_ACT_NAT,
	  r.RGO_ASU_NAT,
	  r.RGM_COD,
	  r.RGM_GRG_COD

   from work.top10_ids as t
   inner join sasdata1.prs_rx as r
      on t.BEN_IDT_ANO = r.BEN_IDT_ANO
   where r.EXE_SOI_DTD >= t.DT_FIRST_AD
     and (
                    r.PHA_ATC_CLA like 'N05A%' /* antipsychotics - lithium */
                /* or ref.PHA_ATC_CLA like 'N05B%' 
                 or ref.PHA_ATC_CLA like 'N05C%' anxiolytics, hypnotics */
                 or r.PHA_ATC_CLA like 'N06A%' /* antidepressants */
				 or r.PHA_ATC_CLA like 'N06BA%' /* stimulants */
                 or r.PHA_ATC_CLA like 'N03A%'  /* antiepileptics */
              );
		
quit;

proc sort data=work.filtered_prs nodup;
   by BEN_IDT_ANO EXE_SOI_DTD;
run;  

/* Step 3: Add next_exe_date using a universal correlated subquery */
proc sql;
   create table work.filtered_prs2 as
   select 
      t1.*,
      /* Finds the earliest dispensing date that occurs strictly after the current one */
      (select min(t2.EXE_SOI_DTD) 
       from work.filtered_prs as t2 
       where t2.BEN_IDT_ANO = t1.BEN_IDT_ANO 
         and t2.EXE_SOI_DTD > t1.EXE_SOI_DTD) as next_exe_date format=DATE9.
   from work.filtered_prs as t1;
quit;
