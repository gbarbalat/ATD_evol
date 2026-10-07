/* from FC2, go to ER_PRS_F, and gather a whole bunch of data */

      proc sql;
          create table work.PRS_extract_all as 
          select 
             FC2.BEN_IDT_ANO,
             main.IMB_ALD_DTD, 
             main.IMB_ALD_DTF, 
             main.MED_MTF_COD,
             main.IMB_ETM_NAT,
             which_cim.CAT_CIM_LIL
          from oravue.IR_IMB_R as main

          inner join orauser.FC2 as FC2
             on main.BEN_NIR_PSA = FC2.BEN_NIR_PSA
             and main.BEN_RNG_GEM = FC2.BEN_RNG_GEM

          left join oraval.IR_CCI_V as which_cim
             on main.MED_MTF_COD = which_cim.CAT_CIM_COD

          where main.IMB_ALD_DTD >= FC2.dt_first_ad
            and main.IMB_ALD_DTD <= FC2.dt_first_ad + %eval(366);
       quit;

/* to sasdata1 */
proc sql;
   create table sasdata1.ALD as
   select *
   from work.ald_extract_all;
quit;
