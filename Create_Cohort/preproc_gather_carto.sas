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
             main., 
             main., 
             main.,
             
          from orameps.CARTO_CT_DEP_G13_&yr as main

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
   create table sasdata1.CARTO as
   select *
   from work.carto_extract_all;
quit;
