/* Step 1: Extract the first 10 distinct beneficiaries and their DT_FIRST_AD */
proc sql outobs=10;
   create table work.top10_ids as
   select distinct BEN_IDT_ANO, DT_FIRST_AD
   from sasdata1.prs_rx;
quit;
proc sql;
   create table work.top10_ids as
   select distinct BEN_IDT_ANO, DT_FIRST_AD
   from sasdata1.prs_rx;
quit;

/* Step 2: Join back to prs_rx to get candidate Rx lines on or after DT_FIRST_AD */
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
	  r.PHA_FRM_LIB,
	  r.PSP_SPE_COD,
	  r.PSP_ACT_NAT,
	  r.RGO_ASU_NAT,
	  r.RGM_COD,
	  r.RGM_GRG_COD,
	  r.BEN_DCD_DTE, 
	  r.MAX_TRT_DTD

   from work.top10_ids as t
   inner join sasdata1.prs_rx as r
      on t.BEN_IDT_ANO = r.BEN_IDT_ANO
   and r.EXE_SOI_DTD >= t.DT_FIRST_AD
     where (
                 (r.PHA_ATC_CLA like 'N05A%' and r.PHA_ATC_CLA not like 'N05AA%') /* antipsychotics - lithium but not so-called sedative NLP*/
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
/* 1. Find the next dispensing date via a self-join on work.filtered_prs2 */
proc sql;
   create table work.next_dates as
   select 
      t1.BEN_IDT_ANO,
      t1.EXE_SOI_DTD,
      min(t2.EXE_SOI_DTD) as next_exe_date
   from work.filtered_prs2 as t1
   left join work.filtered_prs2 as t2
      on t1.BEN_IDT_ANO = t2.BEN_IDT_ANO
     and t2.EXE_SOI_DTD > t1.EXE_SOI_DTD
   group by t1.BEN_IDT_ANO, t1.EXE_SOI_DTD;
quit;

/* 2. Merge back and apply the fallback logic */
proc sql;
   create table work.filtered_prs3 as
   select 
      t1.*,
      coalesce(
         n.next_exe_date,
         min(
            intnx('year', t1.DT_FIRST_AD, 1, 'same'), 
            datepart(t1.MAX_TRT_DTD), 
            case 
               when t1.BEN_DCD_DTE = . or year(datepart(t1.BEN_DCD_DTE)) < 1960 then . 
               else datepart(t1.BEN_DCD_DTE) 
            end
         )
      ) as next_exe_date format=date9.
   from work.filtered_prs2 as t1
   left join work.next_dates as n
      on t1.BEN_IDT_ANO = n.BEN_IDT_ANO
     and t1.EXE_SOI_DTD = n.EXE_SOI_DTD;
quit;

/* Step 4: Apply date formats cleanly in a DATA step */
data work.prs_intervals;
   set work.filtered_prs3;
   format next_exe_date DATE9.; /* You can also use YYMMDD10. if you prefer YYYY-MM-DD */
run;


/* check for other meds in prs_rx */
proc sql;
   create table work.prs_meds as
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
	  f.PHA_FRM_LIB,
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
         case when PHA_ATC_CLA like 'N05B%' or PHA_ATC_CLA like 'N05C%'  or PHA_ATC_CLA like 'N05AA%' then 1 else 0 end as is_anx,
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
	  f.PHA_FRM_LIB,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD;
quit;



/* Now count visits between EXE_SOI_DTD and next_exe_date */
proc sql;
   create table work.prs_meds_visits as
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
	  f.PHA_FRM_LIB,

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
	  case when coalesce(max(r.is_SeenNonMed), 0) = 1 then 'Yes' else 'No' end as SeenNonMed,

	   /* Check for Pregnancy */
      case when coalesce(max(r.is_Pregnant), 0) = 1 then 'Yes' else 'No' end as Pregnant

   from work.prs_meds as f
   left join (
      select 
         BEN_IDT_ANO,
         datepart(EXE_SOI_DTD) as exe_date,
		 case when PSE_SPE_COD=1 or PSE_SPE_COD=22 or PSE_SPE_COD=23 then 1 else 0 end as is_GP,
		 case when PSE_SPE_COD=33 or PSE_SPE_COD=17 or PSE_SPE_COD=75  then 1 else 0 end as is_Psych,
         case when PSE_SPE_COD not in (0,1,22,23,17,33,75) then 1 else 0 end as is_OtherMed,
		 case when PSE_SPE_COD=0 then 1 else 0 end as is_SeenNonMed,

         case when RGO_ASU_NAT in (40,80) then 1 else 0 end as is_ATMPInv,
         case when (RGM_COD in (180,181, 188, 189) and RGM_GRG_COD=1) then 1 else 0 end as is_AAH,
		 
		 case when PRS_GRS_DTD is not null then 1 else 0 end as is_Pregnant
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
	  f.PHA_FRM_LIB,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
	  f.HasAnx,
	  f.HasOtherMeds;
quit;





/* Now check for ALD */
proc sql;
   create table work.prs_meds_visits_ald as
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
	  f.PHA_FRM_LIB,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
	  f.HasAnx,
	  f.HasOtherMeds,
	  f.HasATMPInv,
	  f.HasAAH,
	  f.SeenGP,
	  f.SeenPsych,
	  f.SeenOtherMed,
	  f.SeenNonMed,
	  f.Pregnant,
      
      /* Check for ALD Psy */
      case when coalesce(max(r.is_ALD23), 0) = 1 then 'Yes' else 'No' end as HasALDPsy,
      
      /* Check for AAH */
      case when coalesce(max(r.is_ALDNot23), 0) = 1 then 'Yes' else 'No' end as HasALDNonPsy

   from work.prs_meds_visits as f
   left join (
      select 
         BEN_IDT_ANO,
         datepart(IMB_ALD_DTD) as exe_date,
		 datepart(IMB_ALD_DTF) as end_date,
		case when ALD_030_LIB = "Affections psychiatriques de longue durée" then 1 else 0 end as is_ALD23,
		case when ALD_030_LIB ne "Affections psychiatriques de longue durée" and ALD_030_LIB ne ' ' then 1 else 0 end as is_ALDNot23
		 
      from sasdata1.ald
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
	 and r.end_date > f.EXE_SOI_DTD
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
	  f.PHA_FRM_LIB,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
	  f.HasAnx,
	  f.HasOtherMeds,
	  f.HasATMPInv,
	  f.HasAAH,
	  f.SeenGP,
	  f.SeenPsych,
	  f.SeenOtherMed,
	  f.SeenNonMed,
	  f.Pregnant;
quit;



/* Now check for ORC */
data sasdata1.orc;
   set sasdata1.orc;
   exe_date = datepart(MLL_CTA_DSD);
   end_date = datepart(MLL_CTA_DSF);
   format exe_date end_date DATE9.;
run;
proc sql;
   create table work.prs_meds_visits_ald_orc as
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
	  f.PHA_FRM_LIB,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
      f.HasAnx,
      f.HasOtherMeds,
      f.HasATMPInv,
      f.HasAAH,
      f.SeenGP,
      f.SeenPsych,
      f.SeenOtherMed,
      f.SeenNonMed,
	  f.Pregnant,
      f.HasALDPsy,
      f.HasALDNonPsy,
      
      /* Check for C2S */
      case when coalesce(max(r.is_C2S), 0) = 1 then 'Yes' else 'No' end as HasC2S
      
   from work.prs_meds_visits_ald as f
   left join (
      select 
         BEN_IDT_ANO,
         exe_date,
         end_date,
         case when BEN_CTA_TYP = 89 then 1 else 0 end as is_C2S
      from sasdata1.orc
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.end_date > f.EXE_SOI_DTD
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
	  f.PHA_FRM_LIB,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
      f.HasAnx,
      f.HasOtherMeds,
      f.HasATMPInv,
      f.HasAAH,
      f.SeenGP,
      f.SeenPsych,
      f.SeenOtherMed,
      f.SeenNonMed,
	  f.Pregnant,
      f.HasALDPsy,
      f.HasALDNonPsy;
quit;


/* Now check for SSR admission */
proc sql;
   create table work.prs_meds_visits_ald_orc_ssr as
   select 
      f.*,
      
      /* Safely calculate SSR length, forcing 0 if missing interval or no match */
      case 
         when f.next_exe_date is null then 0
         else coalesce(sum(
            case 
               when r.ssr_start < f.next_exe_date 
                and r.ssr_end > f.EXE_SOI_DTD 
               then min(f.next_exe_date, r.ssr_end) - max(f.EXE_SOI_DTD, r.ssr_start) 
               else -1 
            end
         ), 0)
      end as SSR_Length, 
	  r.AGE_SSR

   from work.prs_meds_visits_ald_orc as f
   left join (
      select distinct
         BEN_IDT_ANO as BEN_IDT_ANO,
         EXE_SOI_DTD as ssr_start,   
         EXE_SOI_DTF as ssr_end,
		 AGE_ANN as AGE_SSR
      from sasdata1.ssr
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.ssr_start < f.next_exe_date
     and r.ssr_end > f.EXE_SOI_DTD
     
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
	  f.PHA_FRM_LIB,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
      f.HasAnx,
      f.HasOtherMeds,
      f.HasATMPInv,
      f.HasAAH,
      f.SeenGP,
      f.SeenPsych,
      f.SeenOtherMed,
      f.SeenNonMed,
	  f.Pregnant,
      f.HasALDPsy,
      f.HasALDNonPsy,
      f.HasC2S;
quit;


/* Same with MCO admissions */
proc sql;
   create table work.prs_meds_visits_ald_orc_ssr_mco as
   select 
      f.*,
      
      /* Safely calculate MCO length, forcing 0 if missing interval or no match */
      case 
         when f.next_exe_date is null then 0
         else coalesce(sum(
            case 
               when r.mco_start < f.next_exe_date 
                and r.mco_end > f.EXE_SOI_DTD 
               then min(f.next_exe_date, r.mco_end) - max(f.EXE_SOI_DTD, r.mco_start) 
               else -1 
            end
         ), 0)
      end as MCO_Length,
	  r.AGE_MCO


   from work.prs_meds_visits_ald_orc_ssr as f
   left join (
      select distinct
         BEN_IDT_ANO as BEN_IDT_ANO,
         EXE_SOI_DTD as mco_start,   
         EXE_SOI_DTF as mco_end,    
		 AGE_ANN as AGE_MCO

      from sasdata1.mco
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.mco_start < f.next_exe_date
     and r.mco_end > f.EXE_SOI_DTD
     
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
	  f.PHA_FRM_LIB,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
      f.HasAnx,
      f.HasOtherMeds,
      f.HasATMPInv,
      f.HasAAH,
      f.SeenGP,
      f.SeenPsych,
      f.SeenOtherMed,
      f.SeenNonMed,
	  f.Pregnant,
      f.HasALDPsy,
      f.HasALDNonPsy,
      f.HasC2S,
	  f.SSR_Length;
quit;



/* Same with HAD */
proc sql;
   create table work.prs_ald_orc_ssr_mco_had_after as
   select 
      f.*,
      
      /* Safely calculate HAD length, forcing 0 if missing interval or no match */
      case 
         when f.next_exe_date is null then 0
         else coalesce(sum(
            case 
               when r.had_start < f.next_exe_date 
                and r.had_end > f.EXE_SOI_DTD 
               then min(f.next_exe_date, r.had_end) - max(f.EXE_SOI_DTD, r.had_start) 
               else -1 
            end
         ), 0)
      end as HAD_Length,
	  r.AGE_HAD


   from work.prs_meds_visits_ald_orc_ssr_mco as f
   left join (
      select distinct
         BEN_IDT_ANO as BEN_IDT_ANO,
         EXE_SOI_DTD as had_start,   
         EXE_SOI_DTF as had_end,
		 AGE_ANN as AGE_HAD
      from sasdata1.had
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.had_start < f.next_exe_date
     and r.had_end > f.EXE_SOI_DTD
     
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
	  f.PHA_FRM_LIB,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
      f.HasAnx,
      f.HasOtherMeds,
      f.HasATMPInv,
      f.HasAAH,
      f.SeenGP,
      f.SeenPsych,
      f.SeenOtherMed,
      f.SeenNonMed,
	  f.Pregnant,
      f.HasALDPsy,
      f.HasALDNonPsy,
      f.HasC2S,
	  f.SSR_Length,
	  f.MCO_Length;
quit;



/* Same with RIP */
proc sql;
   create table work.prs_ald_orc_hosp_after as
   select 
      f.*,
      
 /* RIP Length for FOR_ACT starting with '0' */
      case 
         when f.next_exe_date is null then 0
         else coalesce(sum(
            case 
               when r.rip_start < f.next_exe_date 
                and r.rip_end > f.EXE_SOI_DTD 
                and r.FOR_ACT like '0%' 
               then min(f.next_exe_date, r.rip_end) - max(f.EXE_SOI_DTD, r.rip_start)  /*+ 1 */
               else -1 
            end
         ), 0)
      end as RIP_0_Length,

      /* RIP Length for FOR_ACT starting with '1' */
      case 
         when f.next_exe_date is null then 0
         else coalesce(sum(
            case 
               when r.rip_start < f.next_exe_date 
                and r.rip_end > f.EXE_SOI_DTD 
                and r.FOR_ACT like '2%' 
               then min(f.next_exe_date, r.rip_end) - max(f.EXE_SOI_DTD, r.rip_start) /*+ 1 */
               else -1 
            end
         ), 0)
      end as RIP_2_Length,
 	  r.AGE_RIP


   from work.prs_ald_orc_ssr_mco_had_after as f
   left join (
      select distinct
         BEN_IDT_ANO as BEN_IDT_ANO,
         rip_start,   
         rip_end, 
		 FOR_ACT, 
		 AGE_ANN as AGE_RIP
      from sasdata1.rip
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.rip_start < f.next_exe_date
     and r.rip_end > f.EXE_SOI_DTD
     
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
	  f.PHA_FRM_LIB,
      f.PSP_SPE_COD,
      f.PSP_ACT_NAT,
      f.RGO_ASU_NAT,
      f.RGM_COD,
      f.RGM_GRG_COD,
      f.HasAnx,
      f.HasOtherMeds,
      f.HasATMPInv,
      f.HasAAH,
      f.SeenGP,
      f.SeenPsych,
      f.SeenOtherMed,
      f.SeenNonMed,
	  f.Pregnant,
      f.HasALDPsy,
      f.HasALDNonPsy,
      f.HasC2S,
	  f.SSR_Length,
	  f.MCO_Length,
	  f.HAD_Length;
quit;

proc sort data=work.prs_ald_orc_hosp_after nodupkey;
   by _all_;
run;
