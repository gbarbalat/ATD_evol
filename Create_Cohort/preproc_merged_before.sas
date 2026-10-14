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
        and datepart(r.EXE_SOI_DTD) < p.DT_FIRST_AD
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
data work.prs_meds_visits_ald_orc;
   set work.prs_meds_visits_ald_orc;
   /* Apply standard date formatting to all date columns */
   format DT_FIRST_AD EXE_SOI_DTD date9.;
run;

data sasdata1.ssr;
   set sasdata1.ssr;
   format EXE_SOI_DTD EXE_SOI_DTF date9.;
run;

proc sql;
   create table work.prs_meds_visits_ald_orc_ssr as
   select 
      f.*,
      
      /* Safely calculate SSR length, forcing 0 if missing interval or no match */
      case 
         when f.next_exe_date is null then 0
         else coalesce(sum(
            case 
               when r.ssr_start <= f.next_exe_date 
                and r.ssr_end >= f.EXE_SOI_DTD 
               then min(f.next_exe_date, r.ssr_end) - max(f.EXE_SOI_DTD, r.ssr_start) + 1
               else 0 
            end
         ), 0)
      end as SSR_Length, 
	  r.AGE_SSR

   from work.prs_meds_visits_ald_orc as f
   left join (
      select 
         BEN_IDT_ANO as BEN_IDT_ANO,
         EXE_SOI_DTD as ssr_start,   
         EXE_SOI_DTF as ssr_end,
		 AGE_ANN as AGE_SSR
      from sasdata1.ssr
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.ssr_start <= f.next_exe_date
     and r.ssr_end >= f.EXE_SOI_DTD
     
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
data sasdata1.mco;
   set sasdata1.mco; 
	EXE_SOI_DTD = datepart(EXE_SOI_DTD);
   EXE_SOI_DTF = datepart(EXE_SOI_DTF);
   format EXE_SOI_DTD EXE_SOI_DTF  date9.;
run;

proc sql;
   create table work.prs_meds_visits_ald_orc_ssr_mco as
   select 
      f.*,
      
      /* Safely calculate MCO length, forcing 0 if missing interval or no match */
      case 
         when f.next_exe_date is null then 0
         else coalesce(sum(
            case 
               when r.mco_start <= f.next_exe_date 
                and r.mco_end >= f.EXE_SOI_DTD 
               then min(f.next_exe_date, r.mco_end) - max(f.EXE_SOI_DTD, r.mco_start) + 1
               else 0 
            end
         ), 0)
      end as MCO_Length,
	  r.AGE_MCO


   from work.prs_meds_visits_ald_orc_ssr as f
   left join (
      select 
         BEN_IDT_ANO as BEN_IDT_ANO,
         EXE_SOI_DTD as mco_start,   
         EXE_SOI_DTF as mco_end    
		 AGE_ANN as AGE_MCO

      from sasdata1.mco
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.mco_start <= f.next_exe_date
     and r.mco_end >= f.EXE_SOI_DTD
     
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
data sasdata1.had;
   set sasdata1.had; 
	EXE_SOI_DTD = datepart(EXE_SOI_DTD);
   EXE_SOI_DTF = datepart(EXE_SOI_DTF);
   format EXE_SOI_DTD EXE_SOI_DTF  date9.;
run;

proc sql;
   create table work.prs_after_had as
   select 
      f.*,
      
      /* Safely calculate HAD length, forcing 0 if missing interval or no match */
      case 
         when f.next_exe_date is null then 0
         else coalesce(sum(
            case 
               when r.had_start <= f.next_exe_date 
                and r.had_end >= f.EXE_SOI_DTD 
               then min(f.next_exe_date, r.had_end) - max(f.EXE_SOI_DTD, r.had_start) + 1
               else 0 
            end
         ), 0)
      end as HAD_Length,
	  r.AGE_HAD


   from work.prs_meds_visits_ald_orc_ssr_mco as f
   left join (
      select 
         BEN_IDT_ANO as BEN_IDT_ANO,
         EXE_SOI_DTD as had_start,   
         EXE_SOI_DTF as had_end,
		 AGE_ANN as AGE_HAD
      from sasdata1.had
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.had_start <= f.next_exe_date
     and r.had_end >= f.EXE_SOI_DTD
     
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
data sasdata1.rip;
   set sasdata1.rip; 
   
   /* Standardize existing date components */
   EXE_SOI_DTD = datepart(EXE_SOI_DTD);
   EXE_SOI_DTF = datepart(EXE_SOI_DTF);
   
   /* Calculate new milestone dates */
   rip_start = EXE_SOI_DTD + ENT_DEL_DAT;
   rip_end = rip_start + sum(PRE_JOU_NBJ, PRE_DEM_JOU_NBJ/2);
   
   /* Apply date9. format to all date columns */
   format EXE_SOI_DTD EXE_SOI_DTF rip_start rip_end date9.;
run;

proc sql;
   create table work.prs_after_had_rip as
   select 
      f.*,
      
 /* RIP Length for FOR_ACT starting with '0' */
      case 
         when f.next_exe_date is null then 0
         else coalesce(sum(
            case 
               when r.rip_start <= f.next_exe_date 
                and r.rip_end >= f.EXE_SOI_DTD 
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
               when r.rip_start <= f.next_exe_date 
                and r.rip_end >= f.EXE_SOI_DTD 
                and r.FOR_ACT like '2%' 
               then min(f.next_exe_date, r.rip_end) - max(f.EXE_SOI_DTD, r.rip_start) /*+ 1 */
               else -1 
            end
         ), 0)
      end as RIP_2_Length,
 	  r.AGE_RIP


   from work.prs_after_had as f
   left join (
      select 
         BEN_IDT_ANO as BEN_IDT_ANO,
         rip_start,   
         rip_end, 
		 FOR_ACT, 
		 AGE_ANN as AGE_RIP
      from sasdata1.rip
   ) as r
      on f.BEN_IDT_ANO = r.BEN_IDT_ANO
     and r.rip_start <= f.next_exe_date
     and r.rip_end >= f.EXE_SOI_DTD
     
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

/* check CRTO databses and create column Prev_Psy_Dx_Rx (No, Latest Year) + Prev_Psy_Adm (No, Latest Year) */
proc sql;
   create table work.prs_after_had_rip_crto_DEP as
   select 
      f.*,
      
      /* Find latest prior psychiatric year, or default to 'No' */
      coalesce(
         (select put(max(c.year), 4.) 
          from sasdata1.carto_dep as c 
          where c.BEN_IDT_ANO = f.BEN_IDT_ANO 
            and (c.DEP_DGF_PSY_BSE > 0 or c.DEP_OQN_PSY_BSE > 0)
            and c.year < year(f.DT_FIRST_AD)),
         'No'
      ) as Prev_Psy_Adm
	  
   from work.prs_after_had_rip as f;
quit;

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


proc sql;
   create table work.prs_after_had_rip_crto_DEP_IND as
   select 
      f.*,
      
	 /* Same with the other crto db */
      coalesce(
         (select put(max(c.year), 4.)  
          from sasdata1.carto_ind as c 
          where c.BEN_IDT_ANO = f.BEN_IDT_ANO 
            and c.has_psy_flag = 1
            and c.year < year(f.DT_FIRST_AD)),
         'No'
      ) as Prev_Psy_Dx_Rx
	  
   from work.prs_after_had_rip_crto_DEP as f;
quit;
