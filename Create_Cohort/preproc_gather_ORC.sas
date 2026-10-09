/* from 2021 to 2024, gather information on C2S */           
       
       /* ------------------------------------------------------------------ */
       /* EXECUTION                                                          */
       /* ------------------------------------------------------------------ */
       proc sql;
          create table work.orc_extract_all as 
          select 
             FC2.BEN_IDT_ANO,
             
             main.BEN_CTA_TYP, /* 89 means C2S */
             main.MLL_CTA_DSD,
             main.MLL_CTA_DSF
             
          from oravue.IR_ORC_R as main

          inner join orauser.FC2 as FC2
             on main.BEN_NIR_PSA = FC2.BEN_NIR_PSA
             and main.BEN_RNG_GEM = FC2.BEN_RNG_GEM ;
             
       quit;

/* to sasdata1 */
proc sql;
   create table sasdata1.ORC as
   select *
   from work.orc_extract_all;
quit;
