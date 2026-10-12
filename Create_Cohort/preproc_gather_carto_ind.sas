/* from 2015 to 2024, gather information on the severest cases */

%macro extract_CARTO(start=2015, stop=2023);

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
          create table work.carto_extract_base as 
          select 
             FC2.BEN_IDT_ANO,
             'CARTO' as source_db length=5,
             main.*

          from orameps.CRTO_CT_IND_G13_&yr. as main

          inner join orauser.FC2 as FC2
             on main.BEN_IDT_ANO = FC2.BEN_IDT_ANO;
             
       quit;

      data work.carto_extract_tmp;
         set work.carto_extract_base;
         keep BEN_IDT_ANO source_db 
           psy_:     /* Equivalent to starts_with("PSY_") */
           tps_:     /* Equivalent to starts_with("TPS_") */
           ASS_AAH_TOP BEN_ACS_TOP BEN_ALD_TOP CMU TOP_C2S_GRA TOP_C2S_PAR TOP_IND TOP_MT;
      run;

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
%extract_CARTO(start=2015, stop=2023);

/* to sasdata1 */
proc sql;
   create table sasdata1.CARTO_IND as
   select *
   from work.carto_extract_all;
quit;
