/* from 2015 to 2024, gather information on the severest cases */

%macro extract_CARTO(start=2015, stop=2024);

   /* 1. Reset master output table */
   proc datasets lib=work nolist;
      delete carto_extract_all carto_extract_tmp;
   quit;

   %do year = &start %to &stop;
       /* %let yr = %sysfunc(putn(&year., z4.)); */
       %let yr = &year.;                       
       
       /* ------------------------------------------------------------------ */
       /* EXECUTION                                                          */
       /* ------------------------------------------------------------------ */
       proc sql;
          create table work.carto_extract_tmp as 
          select 
             FC2.BEN_IDT_ANO,
             'CARTO' as source_db length=5,
             main.PSY_*,   /* Selects all variables starting with PSY_ */
             main.TPS_*,    /* Selects all variables starting with TPS_ */      
             
             main.ASS_AAH_TOP,  
             main.BEN_ACS_TOP,
             main.BEN_ALD_TOP,
             main.CMU,
             main.TOP_C2S_GRA,
             main.TOP_C2S_PAR,
             main.TOP_IND,
             main.TOP_MT

          from orameps.CRTO_CT_IND_G13_&yr. as main

          inner join orauser.FC2 as FC2
             on main.BEN_IDT_ANO = FC2.BEN_IDT_ANO;
             
       quit;

       proc append base=work.carto_extract_all data=work.carto_extract_tmp force;
       run;

       %next_year:

   %end;

   proc datasets lib=work nolist;
      delete carto_extract_tmp;
   quit;

%mend extract_CARTO;

/*example
%extract_HAD(start=18, stop=19);*/
%extract_CARTO(start=2015, stop=2024);

/* to sasdata1 */
proc sql;
   create table sasdata1.CARTO_IND as
   select *
   from work.carto_extract_all;
quit;
