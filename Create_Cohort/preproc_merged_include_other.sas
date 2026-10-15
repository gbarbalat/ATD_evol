/* add refill_Nb column at each different EXE_SOI_DTD per BEN_IDT_ANO */
/* 1. Ensure data is sorted by patient and date */
proc sort data=work.PRS_ALD_ORC_HOSP_CRTO_BEFORE;
   by BEN_IDT_ANO EXE_SOI_DTD;
run;

/* 2. Generate the incrementing refill counter */
data work.PRS_ALD_ORC_HOSP_CRTO_BEFORE;
   set work.PRS_ALD_ORC_HOSP_CRTO_BEFORE;
   by BEN_IDT_ANO EXE_SOI_DTD;
   retain refill_Nb;
   
   if first.BEN_IDT_ANO then refill_Nb = 1;
   else if first.EXE_SOI_DTD then refill_Nb + 1;
run;


/* now add season-year column from EXE_SOI_DTD which is data 9. */
data work.PRS_ALD_ORC_HOSP_CRTO_BEFORE;
   set work.PRS_ALD_ORC_HOSP_CRTO_BEFORE;
   
   /* Extract date part and pull month/year components */
   local_date = EXE_SOI_DTD;
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

/* take PRS_AFTER_HAD_RIP and build up depcom and dept variables (local variables) */
data work.prs_after_had_rip;
   set work.prs_after_had_rip;
   
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
   create table work.prs_after_had_rip as
   select 
      f.*,
      r.FDEP20_quint,
      r.P20_POP
   from work.prs_after_had_rip as f
   left join rfcommun.defa_uu2020 as r
      on f.depcom = r.CODGEO;
quit;

/* go to rfcommun.denb_ps_commune_01jan2022, where DEP is our BEN_DEP and COM is our BEN_RES_COM, 
for each join in prs_after_had_rip, calculate sum of NB_PS for SPE = "01" (GP) and SPE = "33" (Psych) -> I'll have 
2 additional columns in prs_after_had_rip called Nb_GP and Nb_Psych respectively*/
