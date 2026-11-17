/* gather information on pregnancy */           
       
       /* ------------------------------------------------------------------ */
       /* EXECUTION                                                          */
       /* ------------------------------------------------------------------ */
       proc sql;
          create table work.mat_extract_all as 
          select 
             FC2.BEN_IDT_ANO,
             
             main.BEN_GRS_DTE,
             main.BEN_DRA_AME
             
          from oravue.IR_MAT_R as main

          inner join orauser.FC2 as FC2
             on main.BEN_NIR_PSA = FC2.BEN_NIR_PSA
             and main.BEN_RNG_GEM = FC2.BEN_RNG_GEM ;
             
       quit;

/* to sasdata1 */
proc sql;
   create table sasdata1.MAT as
   select *
   from work.mat_extract_all;
quit;
