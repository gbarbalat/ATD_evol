/* simply aggregates the 4 other preproc_merged_xxx.sas scripts to be run in one go
update: change where to join to increase computational efficiency
*/

/* ========== 
=== CHUNK 1 ===
=== _after ====
============= */
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
	  r.PRE_PRE_DTD,
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
   and r.PRE_PRE_DTD >= t.DT_FIRST_AD
     where (
                 (r.PHA_ATC_CLA like 'N05A%' and r.PHA_ATC_CLA not like 'N05AA%') /* antipsychotics - lithium */
                /* or ref.PHA_ATC_CLA like 'N05B%' 
                 or ref.PHA_ATC_CLA like 'N05C%' anxiolytics, hypnotics */
                 or r.PHA_ATC_CLA like 'N06A%' /* antidepressants */
				 or r.PHA_ATC_CLA like 'N06BA%' /* stimulants */
                 or r.PHA_ATC_CLA like 'N03A%'  /* antiepileptics */
              );
		
quit;

proc sort data=work.filtered_prs nodup;
   by BEN_IDT_ANO PRE_PRE_DTD EXE_SOI_DTD;
run;  

data work.filtered_prs2;
   set work.filtered_prs;
   
   /* Extract pure dates from the datetime timestamps */
   DT_FIRST_AD = datepart(DT_FIRST_AD);
   EXE_SOI_DTD = datepart(EXE_SOI_DTD);
   PRE_PRE_DTD = datepart(PRE_PRE_DTD);
   
   /* Apply standard date formatting */
   format DT_FIRST_AD EXE_SOI_DTD PRE_PRE_DTD DATE9.;
run;

/* Step 3: Add next_pre_date using a universal correlated subquery */
/* 1. Find the next dispensing date via a self-join on work.filtered_prs2 */
proc sql;
   create table work.next_dates as
   select 
      t1.BEN_IDT_ANO,
	  t1.PRE_PRE_DTD,
      t1.EXE_SOI_DTD,
      min(t2.PRE_PRE_DTD) as next_pre_date,
      min(t2.EXE_SOI_DTD) as next_exe_date
   from work.filtered_prs2 as t1
   left join work.filtered_prs2 as t2
      on t1.BEN_IDT_ANO = t2.BEN_IDT_ANO
     and t2.PRE_PRE_DTD > t1.PRE_PRE_DTD
   group by t1.BEN_IDT_ANO, t1.PRE_PRE_DTD;
quit;

/* 2. Merge back and apply the fallback logic */
proc sql;
   create table work.filtered_prs3 as
   select 
      t1.*,
      coalesce(
         n.next_pre_date,
         min(
            intnx('year', t1.DT_FIRST_AD, 1, 'same'), 
            datepart(t1.MAX_TRT_DTD), 
            case 
               when t1.BEN_DCD_DTE = . or year(datepart(t1.BEN_DCD_DTE)) < 1960 then . 
               else datepart(t1.BEN_DCD_DTE) 
            end
         )
      ) as next_pre_date format=date9.
   from work.filtered_prs2 as t1
   left join work.next_dates as n
      on t1.BEN_IDT_ANO = n.BEN_IDT_ANO
     and t1.PRE_PRE_DTD = n.PRE_PRE_DTD;
quit;

/* Step 4: Apply date formats cleanly in a DATA step */
data work.prs_intervals;
   set work.filtered_prs3;
   format next_pre_date DATE9.; /* You can also use YYMMDD10. if you prefer YYYY-MM-DD */
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
	  f.PRE_PRE_DTD,
      f.next_pre_date,
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
         datepart(PRE_PRE_DTD) as pre_date,
         case when PHA_ATC_CLA like 'N05B%' or PHA_ATC_CLA like 'N05C%'  or PHA_ATC_CLA like 'N05AA%' then 1 else 0 end as is_anx,
         case when not (PHA_ATC_CLA like 'N05B%' or PHA_ATC_CLA like 'N05C%') then 1 else 0 end as is_other
      from sasdata1.prs_rx
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.pre_date > f.PRE_PRE_DTD
     and (f.next_pre_date is null or r.pre_date < f.next_pre_date)
     
   group by 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.PRE_PRE_DTD,
      f.next_pre_date,
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



/* Now count visits between PRE_PRE_DTD and next_pre_date */
proc sql;
   create table work.prs_meds_visits as
   select 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.PRE_PRE_DTD,
      f.next_pre_date,
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
     and r.exe_date > f.PRE_PRE_DTD
     and (f.next_pre_date is null or r.exe_date < f.next_pre_date)
     
   group by 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.PRE_PRE_DTD,
      f.next_pre_date,
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
      f.PRE_PRE_DTD,
      f.next_pre_date,
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
	 and r.end_date > f.PRE_PRE_DTD
     and (f.next_pre_date is null or r.exe_date < f.next_pre_date)
     
   group by 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.PRE_PRE_DTD,
      f.next_pre_date,
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
      f.PRE_PRE_DTD,
      f.next_pre_date,
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
     and r.end_date > f.PRE_PRE_DTD
     and (f.next_pre_date is null or r.exe_date < f.next_pre_date)
     
   group by 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.PRE_PRE_DTD,
      f.next_preLA,
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
         when f.next_pre_date is null then 0
         else coalesce(sum(
            case 
               when r.ssr_start < f.next_pre_date 
                and r.ssr_end > f.PRE_PRE_DTD 
               then min(f.next_pre_date, r.ssr_end) - max(f.PRE_PRE_DTD, r.ssr_start) 
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
     and r.ssr_start < f.next_pre_date
     and r.ssr_end > f.PRE_PRE_DTD
     
   group by 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.PRE_PRE_DTD,
      f.next_pre_date,
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
         when f.next_pre_date is null then 0
         else coalesce(sum(
            case 
               when r.mco_start < f.next_pre_date 
                and r.mco_end > f.PRE_PRE_DTD 
               then min(f.next_pre_date, r.mco_end) - max(f.PRE_PRE_DTD, r.mco_start) 
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
     and r.mco_start < f.next_pre_date
     and r.mco_end > f.PRE_PRE_DTD
     
   group by 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.PRE_PRE_DTD,
      f.next_pre_date,
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
         when f.next_pre_date is null then 0
         else coalesce(sum(
            case 
               when r.had_start < f.next_pre_date 
                and r.had_end > f.PRE_PRE_DTD 
               then min(f.next_pre_date, r.had_end) - max(f.PRE_PRE_DTD, r.had_start) 
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
     and r.had_start < f.next_pre_date
     and r.had_end > f.PRE_PRE_DTD
     
   group by 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.PRE_PRE_DTD,
      f.next_pre_date,
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
         when f.next_pre_date is null then 0
         else coalesce(sum(
            case 
               when r.rip_start < f.next_pre_date 
                and r.rip_end > f.PRE_PRE_DTD 
                and r.FOR_ACT like '0%' 
               then min(f.next_pre_date, r.rip_end) - max(f.PRE_PRE_DTD, r.rip_start)  /*+ 1 */
               else -1 
            end
         ), 0)
      end as RIP_0_Length,

      /* RIP Length for FOR_ACT starting with '1' */
      case 
         when f.next_pre_date is null then 0
         else coalesce(sum(
            case 
               when r.rip_start < f.next_pre_date 
                and r.rip_end > f.PRE_PRE_DTD 
                and r.FOR_ACT like '2%' 
               then min(f.next_pre_date, r.rip_end) - max(f.PRE_PRE_DTD, r.rip_start) /*+ 1 */
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
     and r.rip_start < f.next_pre_date
     and r.rip_end > f.PRE_PRE_DTD
     
   group by 
      f.BEN_IDT_ANO,
      f.DT_FIRST_AD,
      f.BEN_AMA_COD,
      f.BEN_RES_DPT,
      f.BEN_RES_COM,
      f.PRE_PRE_DTD,
      f.next_pre_date,
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

/* ==========
== CHUNK 2 ===
== BEFORE ====
============ */
/* from prs_intervals, obtained from preproc_merged_after.sas */

/* check for other meds in prs_rx */
proc sql;
   create table work.prs_meds_before as
   select 
      f.*,
      
      /* Check for Anxiolytics / Hypnotics */
      case when coalesce(r.has_anx, 0) = 1 then 'Yes' else 'No' end as Prev_Anx,
      
      /* Check for Other Meds (Neither N05B nor N05C) */
      case when coalesce(r.has_other, 0) = 1 then 'Yes' else 'No' end as Prev_Meds

   from work.prs_intervals as f
   left join (
      select 
         p.BEN_IDT_ANO,
         max(case when r.PHA_ATC_CLA like 'N05B%' or r.PHA_ATC_CLA like 'N05C%' then 1 else 0 end) as has_anx,
         max(case when not (r.PHA_ATC_CLA like 'N05B%' or r.PHA_ATC_CLA like 'N05C%') then 1 else 0 end) as has_other
      from (select distinct BEN_IDT_ANO, DT_FIRST_AD from work.prs_intervals) as p
      inner join sasdata1.prs_rx as r
         on p.BEN_IDT_ANO = r.BEN_IDT_ANO
        and datepart(r.PRE_PRE_DTD) < p.DT_FIRST_AD
      group by p.BEN_IDT_ANO
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO;
quit;



/* Now count visits */
proc sql;
   create table work.prs_meds_visits_before as
   select 
      f.*,
      
      /* Check for ATMPInv */
      case when coalesce(r.has_ATMPInv, 0) = 1 then 'Yes' else 'No' end as Prev_ATMPInv,
      
      /* Check for AAH */
      case when coalesce(r.has_AAH, 0) = 1 then 'Yes' else 'No' end as Prev_AAH,

      /* Check for Seen by */
      case when coalesce(r.has_GP, 0) = 1 then 'Yes' else 'No' end as Prev_SeenGP,
      case when coalesce(r.has_Psych, 0) = 1 then 'Yes' else 'No' end as Prev_SeenPsych,
      case when coalesce(r.has_OtherMed, 0) = 1 then 'Yes' else 'No' end as Prev_SeenOtherMed,
      case when coalesce(r.has_SeenNonMed, 0) = 1 then 'Yes' else 'No' end as Prev_SeenNonMed,

      /* Check for Pregnancy */
      case when coalesce(r.has_Pregnant, 0) = 1 then 'Yes' else 'No' end as Prev_Pregnant

   from work.prs_meds_before as f
   left join (
      select 
         p.BEN_IDT_ANO,
         max(case when r.PSE_SPE_COD = 1 then 1 else 0 end) as has_GP,
         max(case when r.PSE_SPE_COD = 33 then 1 else 0 end) as has_Psych,
         max(case when r.PSE_SPE_COD not in (0, 1, 33) then 1 else 0 end) as has_OtherMed,
         max(case when r.PSE_SPE_COD = 0 then 1 else 0 end) as has_SeenNonMed,
         max(case when r.RGO_ASU_NAT in (40, 80) then 1 else 0 end) as has_ATMPInv,
         max(case when (r.RGM_COD in (180, 181, 188, 189) and r.RGM_GRG_COD = 1) then 1 else 0 end) as has_AAH,
         max(case when r.PRS_GRS_DTD is not null then 1 else 0 end) as has_Pregnant
      from (select distinct BEN_IDT_ANO, DT_FIRST_AD from work.prs_meds_before) as p
      inner join sasdata1.prs_au as r
         on p.BEN_IDT_ANO = r.BEN_IDT_ANO
        and datepart(r.EXE_SOI_DTD) < p.DT_FIRST_AD
      group by p.BEN_IDT_ANO
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO;
quit;



/* Now check for ALD */
proc sql;
   create table work.prs_ald_before as
   select 
      f.*,
      
      /* Check for ALD Psy */
      case when coalesce(r.has_ALD23, 0) = 1 then 'Yes' else 'No' end as Prev_ALDPsy,
      
      /* Check for ALD Non Psy */
      case when coalesce(r.has_ALDNot23, 0) = 1 then 'Yes' else 'No' end as Prev_ALDNonPsy

   from work.prs_meds_visits_before as f
   left join (
      select 
         p.BEN_IDT_ANO,
         max(case when r.ALD_030_LIB = "Affections psychiatriques de longue durée" then 1 else 0 end) as has_ALD23,
         max(case when r.ALD_030_LIB ne "Affections psychiatriques de longue durée" and r.ALD_030_LIB ne ' ' then 1 else 0 end) as has_ALDNot23
      from (select distinct BEN_IDT_ANO, DT_FIRST_AD from work.prs_meds_visits_before) as p
      inner join sasdata1.ald as r
         on p.BEN_IDT_ANO = r.BEN_IDT_ANO
        /* Ensures ALD start date is before the patient's first admission cutoff */
        and datepart(r.IMB_ALD_DTD) < p.DT_FIRST_AD
		and datepart(r.IMB_ALD_DTF) > p.DT_FIRST_AD - 365
      group by p.BEN_IDT_ANO
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO;
quit;



/* Now check for C2S in orc */
proc sql;
   create table work.prs_ald_orc_before as
   select 
      f.*,
      
      /* Check for C2S */
      case when coalesce(r.has_C2S, 0) = 1 then 'Yes' else 'No' end as Prev_C2S

   from work.prs_ald_before as f
   left join (
      select 
         p.BEN_IDT_ANO,
         max(case when r.BEN_CTA_TYP = 89 then 1 else 0 end) as has_C2S
      from (select distinct BEN_IDT_ANO, DT_FIRST_AD from work.prs_ald_before) as p
      inner join sasdata1.orc as r
         on p.BEN_IDT_ANO = r.BEN_IDT_ANO
        /* Ensure rights start before index and end within 365 days prior */
        and datepart(r.MLL_CTA_DSD) < p.DT_FIRST_AD
        and datepart(r.MLL_CTA_DSF) > p.DT_FIRST_AD - 365
      group by p.BEN_IDT_ANO
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO;
quit;




/* Now check for SSR admission */
proc sql;
   create table work.prs_ald_orc_ssr_before as
   select 
      f.*,
      
      /* Check for previous admission */
      case when coalesce(r.has_SSR, 0) = 1 then 'Yes' else 'No' end as Prev_SSR,
      r.AGE_SSR_before

   from work.prs_ald_orc_before as f
   left join (
      select 
         p.BEN_IDT_ANO,
         1 as has_SSR,
         max(r.AGE_ANN) as AGE_SSR_before
      from (select distinct BEN_IDT_ANO, DT_FIRST_AD from work.prs_ald_orc_before) as p
      inner join sasdata1.ssr as r
         on p.BEN_IDT_ANO = r.BEN_IDT_ANO
        /* Ensure admission start is before index and end overlaps within 365 days prior */
        and r.EXE_SOI_DTD < p.DT_FIRST_AD
        and r.EXE_SOI_DTF > p.DT_FIRST_AD - 365
      group by p.BEN_IDT_ANO
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO;
quit;


/* Same with MCO admissions */
proc sql;
   create table work.prs_ald_orc_ssr_mco_before as
   select 
      f.*,
      
      /* Check for previous admission */
      case when coalesce(r.has_MCO, 0) = 1 then 'Yes' else 'No' end as Prev_MCO,
      r.AGE_MCO_before

   from work.prs_ald_orc_ssr_before as f
   left join (
      select 
         p.BEN_IDT_ANO,
         1 as has_MCO,
         max(r.AGE_ANN) as AGE_MCO_before
      from (select distinct BEN_IDT_ANO, DT_FIRST_AD from work.prs_ald_orc_ssr_before) as p
      inner join sasdata1.mco as r
         on p.BEN_IDT_ANO = r.BEN_IDT_ANO
        /* Ensure admission start is before index and end overlaps within 365 days prior */
        and r.EXE_SOI_DTD < p.DT_FIRST_AD
        and r.EXE_SOI_DTF > p.DT_FIRST_AD - 365
      group by p.BEN_IDT_ANO
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO;
quit;


/* Same with HAD */
proc sql;
   create table work.prs_ald_orc_ssr_mco_had_before as
   select 
      f.*,
      
      /* Check for previous admission */
      case when coalesce(r.has_HAD, 0) = 1 then 'Yes' else 'No' end as Prev_HAD,
      r.AGE_HAD_before

   from work.prs_ald_orc_ssr_mco_before as f
   left join (
      select 
         p.BEN_IDT_ANO,
         1 as has_HAD,
         max(r.AGE_ANN) as AGE_HAD_before
      from (select distinct BEN_IDT_ANO, DT_FIRST_AD from work.prs_ald_orc_ssr_mco_before) as p
      inner join sasdata1.had as r
         on p.BEN_IDT_ANO = r.BEN_IDT_ANO
        /* Ensure admission start is before index and end overlaps within 365 days prior */
        and (r.EXE_SOI_DTD) < p.DT_FIRST_AD
        and (r.EXE_SOI_DTF) > p.DT_FIRST_AD - 365
      group by p.BEN_IDT_ANO
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO;
quit;



/* Same with RIP */
proc sql;
   create table work.prs_ald_orc_hosp_before as
   select 
      f.*,
      
      /* FOR_ACT starting with '0' */
      case when coalesce(r.has_RIP_0, 0) = 1 then 'Yes' else 'No' end as Prev_RIP_0,

      /* FOR_ACT starting with '2' */
      case when coalesce(r.has_RIP_2, 0) = 1 then 'Yes' else 'No' end as Prev_RIP_2,

      r.AGE_RIP_before

   from work.prs_ald_orc_ssr_mco_had_before as f
   left join (
      select 
         p.BEN_IDT_ANO,
         max(case when sub.FOR_ACT like '0%' then 1 else 0 end) as has_RIP_0,
         max(case when sub.FOR_ACT like '2%' then 1 else 0 end) as has_RIP_2,
         max(sub.AGE_ANN) as AGE_RIP_before
      from (select distinct BEN_IDT_ANO, DT_FIRST_AD from work.prs_ald_orc_ssr_mco_had_before) as p
      inner join sasdata1.rip as sub
         on p.BEN_IDT_ANO = sub.BEN_IDT_ANO
        and sub.rip_start < p.DT_FIRST_AD
        and sub.rip_end > p.DT_FIRST_AD - 365
      group by p.BEN_IDT_ANO
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO;
quit;


/* check CRTO databses and create column Prev_Psy_Dx_Rx (No, Latest Year) + Prev_Psy_Adm (No, Latest Year) */
/* 1. Extract unique patients and their first admission year */
proc sql noprint;
   create table work.patient_index as
   select distinct BEN_IDT_ANO, DT_FIRST_AD
   from work.prs_ald_orc_hosp_before;
quit;

/* 2. Pre-aggregate the max prior psychiatric year per patient */
proc sql;
   create table work.carto_filtered as
   select 
      p.BEN_IDT_ANO,
      put(max(c.year), 4.) as max_psy_year
   from work.patient_index as p
   inner join sasdata1.carto_dep as c
      on p.BEN_IDT_ANO = c.BEN_IDT_ANO
   where (c.DEP_DGF_PSY_BSE > 0 or c.DEP_OQN_PSY_BSE > 0)
     and c.year < year(p.DT_FIRST_AD)
   group by p.BEN_IDT_ANO;
quit;

/* 3. Left join the result back and assign 'No' as the default */
proc sql;
   create table work.prs_ald_orc_hosp_crto_DEP_before as
   select 
      f.*,
      coalesce(c.max_psy_year, 'No') as Prev_Psy_Adm
   from work.prs_ald_orc_hosp_before as f
   left join work.carto_filtered as c
      on f.BEN_IDT_ANO = c.BEN_IDT_ANO;
quit;

/* same for carto_ind */
data sasdata1.carto_ind;
   set sasdata1.carto_ind;
   
   /* Define arrays for all columns starting with PSY_ and TPS_ */
   array psy_vars[*] PSY_:;
   array tps_vars[*] TPS_:;
   
   has_psy_flag = 0;
   
   /* Check if any PSY_ column is > 0 */
   do i = 1 to dim(psy_vars);
      if psy_vars[i] > 0 then has_psy_flag = 1;
   end;
   
   /* Check if any TPS_ column is > 0 */
   do i = 1 to dim(tps_vars);
      if tps_vars[i] > 0 then has_psy_flag = 1;
   end;
   
   drop i;
run;


/* 1. Extract unique patients and their first admission year */
proc sql noprint;
   create table work.patient_index_ind as
   select distinct BEN_IDT_ANO, DT_FIRST_AD
   from work.prs_ald_orc_hosp_crto_DEP_before;
quit;

/* 2. Pre-aggregate the max prior year per patient from carto_ind */
proc sql;
   create table work.carto_ind_filtered as
   select 
      p.BEN_IDT_ANO,
      put(max(c.year), 4.) as max_ind_year
   from work.patient_index_ind as p
   inner join sasdata1.carto_ind as c
      on p.BEN_IDT_ANO = c.BEN_IDT_ANO
   where c.has_psy_flag = 1
     and c.year < year(p.DT_FIRST_AD)
   group by p.BEN_IDT_ANO;
quit;

/* 3. Left join the result back and assign 'No' as the default */
proc sql;
   create table work.prs_ald_orc_hosp_crto_before as
   select 
      f.*,
      coalesce(c.max_ind_year, 'No') as Prev_Psy_Dx_Rx
   from work.prs_ald_orc_hosp_crto_DEP_before as f
   left join work.carto_ind_filtered as c
      on f.BEN_IDT_ANO = c.BEN_IDT_ANO;
quit;



/* ==================
=== CHUNK 3 =========
== INCLUDE OTHER ====
==================== */
/* add refill_Nb column at each different PRE_PRE_DTD per BEN_IDT_ANO */
/* 1. Ensure data is sorted by patient and date */
proc sort data=work.PRS_ALD_ORC_HOSP_AFTER;
   by BEN_IDT_ANO PRE_PRE_DTD;
run;

/* 2. Generate the incrementing refill counter */
data work.PRS_ALD_ORC_HOSP_AFTER;
   set work.PRS_ALD_ORC_HOSP_AFTER;
   by BEN_IDT_ANO PRE_PRE_DTD;
   retain refill_Nb;
   
   if first.BEN_IDT_ANO then refill_Nb = 1;
   else if first.PRE_PRE_DTD then refill_Nb + 1;
run;


/* now add season-year column from PRE_PRE_DTD which is data 9. */
data work.PRS_ALD_ORC_HOSP_AFTER;
   set work.PRS_ALD_ORC_HOSP_AFTER;
   
   /* Extract date part and pull month/year components */
   local_date = PRE_PRE_DTD;
   m = month(local_date);
   y = year(local_date);
   
   length season_year $ 15;
   
   /* Map months to meteorological seasons */
   if m in (3, 4, 5) then season_year = cat('Spring ', y);
   else if m in (6, 7, 8) then season_year = cat('Summer ', y);
   else if m in (9, 10, 11) then season_year = cat('Autumn ', y);
   else if m in (12, 1, 2) then season_year = cat('Winter ', y);
   
   drop local_date m y;
run;

/* take PRS_ALD_ORC_HOSP_AFTER and build up depcom and dept variables (geographical variables) */
data work.PRS_ALD_ORC_HOSP_G_AFTER;
   set work.PRS_ALD_ORC_HOSP_AFTER;
   
   length depcom $ 10 dept $ 5 region $ 40;
   
   /* Cas général */
   if ben_res_dpt ne '209' and substr(ben_res_dpt, 1, 2) ne '97' then
      depcom = compress(substr(ben_res_dpt, 2, 2) || ben_res_com);
   
   /* Corse */
   else if ben_res_dpt = '209' then
      depcom = compress(substr(ben_res_dpt, 1, 2) || ben_res_com); 
   
   /* DOM */
   else if substr(ben_res_dpt, 1, 2) = '97' then 
      depcom = 'DOM';
      
   /* Department grouping */
   if substr(depcom, 1, 2) in ('97', '20') then
      dept = substr(depcom, 1, 3);
   else
      dept = substr(depcom, 1, 2);

   /* Region assignment based on dept */
   select(dept);
      when ('01', '03', '07', '15', '26', '38', '42', '43', '63', '69', '73', '74') region = "84-Auvergne-Rhône Alpes";
      when ('02', '59', '60', '62', '80')                                           region = "32- Hauts de France";
      when ('04', '05', '06', '13', '83', '84')                                     region = "93-Provence Alpes Cote d'Azur";
      when ('08', '10', '51', '52', '54', '55', '57', '67', '68', '88')               region = "44-Grand Est";
      when ('09', '11', '12', '30', '31', '32', '34', '46', '48', '65', '66', '81', '82') region = "76-Occitanie";
      when ('14', '27', '50', '61', '76')                                           region = "28- Normandie";
      when ('16', '17', '19', '23', '24', '33', '40', '47', '79', '86', '87')         region = "75-Nouvelle Aquitaine";
      when ('18', '28', '36', '37', '41', '45')                                     region = "24-Centre-Val de Loire";
      when ('2A', '2B', '201', '202', '20')                                         region = "94-Corse";
      when ('21', '25', '39', '58', '70', '71', '89', '90')                         region = "27- Bourgogne Franche Comté";
      when ('22', '29', '35', '56')                                                 region = "53-Bretagne";
      when ('44', '49', '53', '72', '85')                                           region = "52-Pays de Loire";
      when ('75', '77', '78', '91', '92', '93', '94', '95')                         region = "11-Ile de France";
      when ('9A', '971')                                                            region = "01-Guadeloupe";
      when ('9B', '972')                                                            region = "02-Martiniquee";
      when ('9C', '973')                                                            region = "03-Guyane";
      when ('9D', '974')                                                            region = "04-La Réunion";
      when ('9F', '976')                                                            region = "06-Mayotte";
      otherwise                                                                     region = "";
   end;
run;

/* go to rfcommun.defa_uu2020, where CODGEO is our depcom, and gather for each row FDEP20_quint and P20_POP */
proc sql;
   create table work.PRS_ALD_ORC_HOSP_GE_AFTER as
   select 
      f.*,
      r.FDEP20_quint,
      r.P20_POP
   from work.PRS_ALD_ORC_HOSP_G_AFTER as f
   left join rfcommun.defa_uu2020 as r
      on f.depcom = r.CODGEO;
quit;

/* go to rfcommun.denb_ps_commune_01jan2022, where DEP is our BEN_DEP and COM is our BEN_RES_COM, 
for each join in PRS_ALD_ORC_HOSP_GE_AFTER, calculate sum of NB_PS for SPE = "01" (GP) and SPE = "33" (Psych) -> I'll have 
2 additional columns in PRS_ALD_ORC_HOSP_GEO_AFTER called Nb_GP and Nb_Psych respectively*/

proc sql;
   /* 1. Calculate density sums per commune */
   create table work.density_agg as
   select 
      put(COM, $5.) as COM,
      sum(case when SPE = '01' or SPE='22' or SPE='23' then NB_PS else 0 end) as Nb_GP,
      sum(case when SPE = '33' or SPE='17' or SPE='75' then NB_PS else 0 end) as Nb_Psych
   from rfcommun.denb_ps_commune_01jan2022
   group by calculated COM;

   /* 2. Join the aggregated density to your main dataset */
   create table work.PRS_ALD_ORC_HOSP_GEO_AFTER as
   select 
      f.*,
      coalesce(r.Nb_GP, 0) as Nb_GP,
      coalesce(r.Nb_Psych, 0) as Nb_Psych
   from work.PRS_ALD_ORC_HOSP_GE_AFTER as f
   left join work.density_agg as r
      on f.depcom = r.COM;
quit;


/* create PRS_ALD_ORC_HOSP_GEO_PRESC_AFTER from PRS_ALD_ORC_HOSP_GEO_AFTER where you
create First_Prescriber for each BEN_IDT_ANO which equals the PSP_SPE_COD where 
PRE_PRE_DTD = DT_FIRST_AD.
Create Adm_Psy_Cur where for each BEN_IDT_ANO, if RIP_0_Length or RIP_2_Length is >=0,
then you put 1 in the column and it gets repeated till the end.
Create Adm_Oth_Cur where for each BEN_IDT_ANO, if MCO_Length or SSR_Length or HAD_Length is > 0,
then you put 1 in the column and it gets repeated till the end.
Apply the following cumsum principle: for each BEN_IDT_ANO and each PRE_PRE_DTD, if Value is Yes, 
the value of the created column is incremented by 1 (from 0) to
HasAnx = Yes (create CumulAnx)
HasOtherMeds=Yes (create CumulOtherMeds)
SeenPsych=Yes (CumulPsych) */
/* 1. Ensure data is properly sorted by patient and date */
proc sort data=work.PRS_ALD_ORC_HOSP_GEO_AFTER;
   by BEN_IDT_ANO PRE_PRE_DTD;
run;

/* 2. Build prs_ald_orc_hosp_presc_after with state flags and cumulative counters */
data work.PRS_ALD_ORC_HOSP_GEO_PRESC_AFTER;
   set work.PRS_ALD_ORC_HOSP_GEO_AFTER;
   by BEN_IDT_ANO PRE_PRE_DTD;
   
   retain First_Prescriber Adm_Psy_Cur Adm_Oth_Cur CumulAnx CumulOtherMeds CumulPsych Lead_Prescriber _prev_psp;
   
   /* Reset tracking variables at the start of each new patient */
   if first.BEN_IDT_ANO then do;
	call missing(First_Prescriber, Lead_Prescriber, _prev_psp);
	  Adm_Psy_Cur = 0;
      Adm_Oth_Cur = 0;
      CumulAnx = 0;
      CumulOtherMeds = 0;
      CumulPsych = 0;
   end;
   else do;
      Lead_Prescriber = _prev_psp;
   end;
   _prev_psp = PSP_SPE_COD;
   
   /* Capture the specialty code of the prescriber at the first admission date */
   if PRE_PRE_DTD = DT_FIRST_AD and missing(First_Prescriber) then 
      First_Prescriber = PSP_SPE_COD;
      
   /* Psychiatric admission flag (retained as 1 once triggered) */
   if (not missing(RIP_0_Length) and RIP_0_Length >= 0) or 
      (not missing(RIP_2_Length) and RIP_2_Length >= 0) then 
      Adm_Psy_Cur = 1;
      
   /* Other hospital admission flags (retained as 1 once triggered) */
   if (not missing(MCO_Length) and MCO_Length > 0) or 
      (not missing(SSR_Length) and SSR_Length > 0) or 
      (not missing(HAD_Length) and HAD_Length > 0) then 
      Adm_Oth_Cur = 1;
      
   /* Cumulative sum counters for Yes flags */
   if upcase(HasAnx) = 'YES' then CumulAnx + 1;
   if upcase(HasOtherMeds) = 'YES' then CumulOtherMeds + 1;
   if upcase(SeenPsych) = 'YES' then CumulPsych + 1;
run;



/* ==========================
=== CHUNK 4 =================
== MERGE BEFORE & AFTER ====
============================ */
/* Remove duplicate rows based on patient, date, and drug label */
proc sort data=work.prs_ald_orc_hosp_crto_before nodupkey out=work.cv_before;
   by BEN_IDT_ANO PRE_PRE_DTD PHA_ATC_LIB;
run;

data work.cv_before;
   set work.cv_before;
   BEN_DCD_DTE=datepart(BEN_DCD_DTE);
   MAX_TRT_DTD=datepart(MAX_TRT_DTD);
   format BEN_DCD_DTE MAX_TRT_DTD date9.;
run;


proc sort data=work.PRS_ALD_ORC_HOSP_GEO_PRESC_AFTER nodupkey out=work.cv_after;
   by BEN_IDT_ANO PRE_PRE_DTD PHA_ATC_LIB;
run;

/* give BEN_DCD_DTE and MAX_TRT_DTD to cv_after by BEN_IDT_ANO */
/* Create a unique patient-level reference table */
proc sql;
   create table work.unique_patient_dates as
   select distinct 
      BEN_IDT_ANO, 
      BEN_DCD_DTE, 
      MAX_TRT_DTD
   from work.cv_before
   group by BEN_IDT_ANO;
quit;

/* Safely left join without duplicating rows */
proc sql;
   create table work.cv_after as
   select 
      a.*,
      b.BEN_DCD_DTE,
      b.MAX_TRT_DTD
   from work.cv_after as a
   left join work.unique_patient_dates as b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO;
quit;
data work.cv_after;
   set work.cv_after;
   format BEN_DCD_DTE MAX_TRT_DTD date9.;
run;

/* Aggregate PHA_ATC_LIB into comma-separated psy_meds and transform dates */
/* also add an event column where for each BEN_IDT_ANO and PRE_PRE_DTD,
the value takes SSRI if the values of PHA_ATC_CLA all start with N06AB; 
ATD_OTH if the values start by N06A but do not include N06AB; 
SWI_CLA if any of the values of PHA_ATC_CLA does not start by N06A; 
DEATH  if  next_pre_date = BEN_DCD_DTE; 
CENS if next_pre_date=MAX_TRT_DTD*/
data work.cv_events_after;
   length psy_meds $ 500 event $ 15;
   
   /* First pass: Concatenate PHA_ATC_LIB and evaluate ATC classification flags per group */
   do while(1);
      set work.cv_after;
      by BEN_IDT_ANO PRE_PRE_DTD;
      
      if first.PRE_PRE_DTD then do;
         psy_meds = PHA_ATC_LIB;
         all_n06ab = 1;
         all_n06a = 1;
         has_n06ab = 0;
      end;
      else do;
         psy_meds = catx(', ', psy_meds, PHA_ATC_LIB);
      end;
      
      /* Check prefix criteria for each row in the group */
      if substr(strip(PHA_ATC_CLA), 1, 5) = 'N06AB' then do;
         has_n06ab = 1;
      end;
      else if substr(strip(PHA_ATC_CLA), 1, 4) = 'N06A' then do;
         all_n06ab = 0;
      end;
      else do;
         all_n06ab = 0;
         all_n06a = 0;
      end;
      
      if last.PRE_PRE_DTD then leave;
   end;
   
   /* Second pass: Output rows, compute relative times, and assign the event type */
   do while(1);
      set work.cv_after;
      by BEN_IDT_ANO PRE_PRE_DTD;
      
      /* Transform dates into relative time (in days) from dt_first_ad */
      start = intck('day', dt_first_ad, PRE_PRE_DTD);
      stop  = intck('day', dt_first_ad, next_pre_date);
      
      /* Event classification logic */
      if next_pre_date = BEN_DCD_DTE then event = 'DEATH';
      else if next_pre_date = MAX_TRT_DTD then event = 'CENS';
      if all_n06ab = 1 then event = 'SSRI';
      else if all_n06a = 1 and all_n06ab = 0 then event = 'ATD_OTH';
      else event = 'SWI_CLA';
      
      output;
      if last.PRE_PRE_DTD then leave;
   end;
run;

proc sort data=work.cv_events_after nodupkey out=work.cv_events_after;
   by BEN_IDT_ANO PRE_PRE_DTD psy_meds;
run;

/* now create from work.cv_events_after where for each BEN_IDT_ANO, 
each time it encounters event = "SWI_CLA", it removes all rows past that line. */
/* 1. Ensure data is ordered chronologically per patient */
proc sort data=work.cv_events_after;
   by BEN_IDT_ANO start;
run;

/* NOT DONE 2. Truncate follow-up after the SWI_CLA event 
data work.cv_events_rd_after;
   set work.cv_events_after;
   by BEN_IDT_ANO;
   
   retain stop_patient;
   
   Reset the stop flag for each new patient
   if first.BEN_IDT_ANO then stop_patient = 0;
   
   If a previous row triggered SWI_CLA, drop this and all subsequent rows
   if stop_patient then delete;
   
   output;
   
   If the current row is SWI_CLA, flag to stop processing further rows for this patient 
   if event = 'SWI_CLA' then stop_patient = 1;
run;*/


/* now merge cv_before and cv_events_rd_after */
/* 1. Dynamically find columns in cv_before that are NOT in cv_events_[rd]_after */
proc sql noprint;
   select distinct upcase(a.name) into :cols_to_pull separated by ', b.'
   from dictionary.columns as a
   where a.libname = 'WORK' and a.memname = 'CV_BEFORE'
     and upcase(a.name) not in (
        select upcase(b.name) 
        from dictionary.columns as b 
        where b.libname = 'WORK' and b.memname = 'CV_EVENTS_AFTER' /* RD_ */
     )
     and upcase(a.name) ne 'BEN_IDT_ANO'; /* Exclude the join key itself */
quit;

/* Verify what columns will be added */
%put Columns to bring over: &cols_to_pull.;

/* 2. Deduplicate cv_before to 1 unique row per patient */
proc sort data=work.cv_before nodupkey out=work.cv_before_unique;
   by BEN_IDT_ANO;
run;

/* 3. Left join cv_events_[rd]_after with only the missing columns */
proc sql;
   create table work.merged_ as
   select 
      a.*
      /* Conditionally append only the non-overlapping columns if any exist */
      %if &cols_to_pull ne %str() %then %do;
         , b.&cols_to_pull.
      %end;
   from work.cv_events_after as a /* RD_ */
   left join work.cv_before_unique as b
      on a.BEN_IDT_ANO = b.BEN_IDT_ANO;
quit;
proc sort data=work.merged_ out=work.merged_;
   by BEN_IDT_ANO PRE_PRE_DTD;
run;
proc copy in=work out=sasdata1;
   select merged_;
run;
