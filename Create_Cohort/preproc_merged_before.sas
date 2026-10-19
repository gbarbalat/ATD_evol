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
proc sql;
   create table work.prs_ald_orc_hosp_crto_DEP_before as
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
	  
   from work.prs_ald_orc_hosp_before as f;
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
   create table work.prs_ald_orc_hosp_crto_before as
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
	  
   from work.prs_ald_orc_hosp_crto_DEP_before as f;
quit;
