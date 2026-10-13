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

data work.filtered_prs2;
   set work.filtered_prs;
   
   /* Extract pure dates from the datetime timestamps */
   DT_FIRST_AD = datepart(DT_FIRST_AD);
   EXE_SOI_DTD = datepart(EXE_SOI_DTD);
   
   /* Apply standard date formatting */
   format DT_FIRST_AD EXE_SOI_DTD DATE9.;
run;

/* Step 3: Add next_exe_date using a universal correlated subquery */
proc sql;
   create table work.filtered_prs3 as
   select 
      t1.*,
      /* Finds the earliest dispensing date that occurs strictly after the current one */
      (select min(t2.EXE_SOI_DTD) 
       from work.filtered_prs2 as t2 
       where t2.BEN_IDT_ANO = t1.BEN_IDT_ANO 
         and t2.EXE_SOI_DTD > t1.EXE_SOI_DTD) as next_exe_date
   from work.filtered_prs2 as t1;
quit;

/* Step 4: Apply date formats cleanly in a DATA step */
data work.prs_intervals;
   set work.filtered_prs4;
   format next_exe_date DATE9.; /* You can also use YYMMDD10. if you prefer YYYY-MM-DD */
run;


/* check for other meds in prs_rx */
proc sql;
   create table work.prs_intervals_flagged as
   select 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.EXE_SOI_DTD,
      f.next_exe_date,
      f.PHA_ATC_CLA,
      f.PHA_ATC_LIB, 
      f.PHA_ACT_QSN,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
      
      /* Check for Anxiolytics / Hypnotics */
      case when coalesce(max(r.is_anx), 0) = 1 then 'Yes' else 'No' end as HasAnx,
      
      /* Check for Other Meds (Neither N05B nor N05C) */
      case when coalesce(max(r.is_other), 0) = 1 then 'Yes' else 'No' end as HasOtherMeds

   from work.prs_intervals as f
   left join (
      select 
         BEN_IDT_ANO,
         datepart(EXE_SOI_DTD) as exe_date,
         case when PHA_ATC_CLA like 'N05B%' or PHA_ATC_CLA like 'N05C%' then 1 else 0 end as is_anx,
         case when not (PHA_ATC_CLA like 'N05B%' or PHA_ATC_CLA like 'N05C%') then 1 else 0 end as is_other
      from sasdata1.prs_rx
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.exe_date > f.EXE_SOI_DTD
     and (f.next_exe_date is null or r.exe_date < f.next_exe_date)
     
   group by 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.EXE_SOI_DTD,
      f.next_exe_date,
      f.PHA_ATC_CLA,
      f.PHA_ATC_LIB, 
      f.PHA_ACT_QSN,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD;
quit;



/* Now count visits between EXE_SOI_DTD and next_exe_date */
proc sql;
   create table work.prs_intervals_meds_visits as
   select 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.EXE_SOI_DTD,
      f.next_exe_date,
      f.PHA_ATC_CLA,
      f.PHA_ATC_LIB, 
      f.PHA_ACT_QSN,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
	  f.HasAnx,
	  f.HasOtherMeds,
      
      /* Check for ATMPInv */
      case when coalesce(max(r.is_ATMPInv), 0) = 1 then 'Yes' else 'No' end as HasATMPInv,
      
      /* Check for AAH */
      case when coalesce(max(r.is_AAH), 0) = 1 then 'Yes' else 'No' end as HasAAH,

	   /* Check for Seen by */
      case when coalesce(max(r.is_GP), 0) = 1 then 'Yes' else 'No' end as SeenGP,
      case when coalesce(max(r.is_Psych), 0) = 1 then 'Yes' else 'No' end as SeenPsych,
	  case when coalesce(max(r.is_OtherMed), 0) = 1 then 'Yes' else 'No' end as SeenOtherMed,
	  case when coalesce(max(r.is_SeenNonMed), 0) = 1 then 'Yes' else 'No' end as SeenNonMed

   from work.prs_intervals_flagged as f
   left join (
      select 
         BEN_IDT_ANO,
         datepart(EXE_SOI_DTD) as exe_date,
		 case when PSE_SPE_COD=1 then 1 else 0 end as is_GP,
		 case when PSE_SPE_COD=33 then 1 else 0 end as is_Psych,
         case when PSE_SPE_COD not in (0, 1,33) then 1 else 0 end as is_OtherMed,
		 case when PSE_SPE_COD=0 then 1 else 0 end as is_SeenNonMed,

         case when RGO_ASU_NAT in (40,80) then 1 else 0 end as is_ATMPInv,
         case when (RGM_COD in (180,181, 188, 189) and RGM_GRG_COD=1) then 1 else 0 end as is_AAH,

		 case when PRS_GRS_DTD in (40,80) then 1 else 0 end as is_ATMPInv
      from sasdata1.prs_au
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.exe_date > f.EXE_SOI_DTD
     and (f.next_exe_date is null or r.exe_date < f.next_exe_date)
     
   group by 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.EXE_SOI_DTD,
      f.next_exe_date,
      f.PHA_ATC_CLA,
      f.PHA_ATC_LIB, 
      f.PHA_ACT_QSN,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
	  f.HasAnx,
	  f.HasOtherMeds;
quit;
