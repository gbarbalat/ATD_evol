/* from 2022 to 2024, gather information on ALD */           
       
       /* ------------------------------------------------------------------ */
       /* EXECUTION                                                          */
       /* ------------------------------------------------------------------ */
       proc sql;
          create table work.ald_extract_all as 
          select 
             FC2.BEN_IDT_ANO,
             
             main.MED_MTF_COD,
             main.IMB_ALD_DTD,
             main.IMB_ALD_DTF,

             dico.ALD_030_LIB
             
          from oravue.IR_IMB_R as main

          inner join orauser.FC2 as FC2
             on main.BEN_NIR_ANO = FC2.BEN_NIR_ANO
             and main.BEN_RNG_GEM = FC2.BEN_RNG_GEM 
          
          inner join oraval.IR_ALD_V as dico
                on main.IMB_ALD_NUM = dico.ALD_030_COD ;
             
       quit;

/* to sasdata1 */
proc sql;
   create table sasdata1.ALD as
   select *
   from work.ald_extract_all;
quit;
