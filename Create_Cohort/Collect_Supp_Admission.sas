/* ==============================================================================
   1. MACRO TO LOOP THROUGH YEARS 08 TO 19 FOR RIP TABLES
   ============================================================================== */
%macro extract_RIP_data;
    proc sql;
    %do year = 09 %to 19;

        %let yr = %sysfunc(putn(&year., z2.));
        
        create table work.rip_extract_20&yr. as 
        select 
            main.NIR_ANO_17, 
            main.EXE_SOI_DTD, 
            main.EXE_SOI_DTF, 
            for_dx.DGN_PAL,
            for_dx.AGE_ANN,

            /* --- FOR_ACT (Appears in 2012 / year >= 12) --- */
            %if %eval(&year < 12) %then %do;
                '' length=10 as FOR_ACT,
            %end;
            %else %do;
                for_dx.FOR_ACT,
            %end;

            /* --- COH_NAI_RET, COH_SEX_RET (Appear in 2014 / year >= 14) --- */
            %if %eval(&year < 14) %then %do;
                '0' as COH_NAI_RET,
                '0' as COH_SEX_RET,
            %end;
            %else %do;
                main.COH_NAI_RET,
                main.COH_SEX_RET,
            %end;

            /* --- TYP_GEN_RSA (Appears in 2015 / year >= 15) --- */
            %if %eval(&year < 15) %then %do;
                '0' as TYP_GEN_RSA,
            %end;
            %else %do;
                for_dx.TYP_GEN_RSA,
            %end;

            /* --- SEQ_IND (Appears in 2020 / year >= 20) --- */
            %if %eval(&year < 20) %then %do;
                '' as SEQ_IND,
            %end;
            %else %do;
                main.SEQ_IND,
            %end;

            for_dx.DEL_DAT,
            for_dx.PRE_JOU_NBJ,
            for_dx.PRE_DEM_JOU_NBJ,
            which_cim.CIM_LIL
        from 
            oravue.T_RIP&yr.C as main
        inner join 
            oravue.T_RIP&yr.RSA as for_dx
        on 
            main.ETA_NUM_EPMSI = for_dx.ETA_NUM_EPMSI AND main.RIP_NUM = for_dx.RIP_NUM
        left join 
            oraval.MS_CIM_V as which_cim
        on 
            for_dx.DGN_PAL = which_cim.CIM_COD
        where 
            main.NIR_ANO_17 in (select distinct BEN_NIR_PSA from work.filtered_treatment_cohort)
            and for_dx.ETA_NUM_EPMSI not in (
                '130780521', '130783236', '130783293', '130784234', '130804297', '600100101', '750041543',
                '750100018', '750100042', '750100075', '750100083', '750100091', '750100109', '750100125', 
                '750100166', '750100208', '750100216', '750100232', '750100273', '750100299', '750801441', 
                '750803447', '750803454', '910100015', '910100023', '920100013', '920100021', '920100039', 
                '920100047', '920100054', '920100062', '930100011', '930100037', '930100045', '940100027', 
                '940100035', '940100043', '940100050', '940100068', '950100016', '690783154', '690784137', 
                '690784152', '690784178', '690787478', '830100558'
            )

            /* Dynamic filters applied based on column existence */
            %if %eval(&year >= 14) %then %do;
                and main.COH_NAI_RET = '0'
                and main.COH_SEX_RET = '0'
            %end;

            %if %eval(&year >= 15) %then %do;
                and for_dx.TYP_GEN_RSA = '0'
            %end;

            %if %eval(&year >= 20) %then %do;
                and main.SEQ_IND <> 'E'
            %end;

            and for_dx.ENT_MOD <> '0' 
            and for_dx.SOR_MOD <> '0' 
            and main.NIR_ANO_17 not in ('xxxxxxxxxxxxxxxxx', 'BXXXXXXXXXXXXXXXX') 
            and main.NIR_RET = '0' 
            and main.NAI_RET = '0' 
            and main.SEX_RET = '0' 
            and main.SEJ_RET = '0' 
            and main.FHO_RET = '0'  
            and main.PMS_RET = '0' 
            and main.DAT_RET = '0';

    %end;
    quit;
%mend extract_RIP_data;

%extract_RIP_data;


/* ==============================================================================
   2. EXTRACT MCO, SSR AND HAD DATA
   ============================================================================== */
%macro extract_OTHER_data;
    proc sql;
    %do year = 15 %to 19;
    
        /* --- Extract MCO Data --- */
        create table work.mco_extract_20&year. as 
        select 
            main.NIR_ANO_17, 
            main.EXE_SOI_DTD, 
            main.EXE_SOI_DTF,
            for_dx.DGN_PAL,
            for_dx.AGE_ANN,
            which_cim.CIM_LIL
        from 
            oravue.T_MCO&year.C as main 
        inner join 
            oravue.T_MCO&year.B as for_dx
        on 
            main.ETA_NUM = for_dx.ETA_NUM AND main.RSA_NUM = for_dx.RSA_NUM
        left join 
                        oraval.MS_CIM_V as which_cim


        on 
            for_dx.DGN_PAL = which_cim.CIM_COD
        where 
            main.NIR_ANO_17 in (select distinct BEN_NIR_PSA from work.filtered_treatment_cohort)
            and for_dx.ETA_NUM not in ('130780521', '130783236', '130783293', '130784234', '130804297','600100101', '750041543',
'750100018', '750100042', '750100075', '750100083', '750100091', '750100109', '750100125', '750100166', '750100208', 
'750100216', '750100232', '750100273', '750100299' , '750801441', '750803447', '750803454', '910100015', '910100023', 
'920100013', '920100021', '920100039', '920100047', '920100054', '920100062', '930100011', '930100037', '930100045', 
'940100027', '940100035', '940100043', '940100050', '940100068', '950100016', '690783154', '690784137', '690784152', 
'690784178', '690787478', '830100558')
            and for_dx.GRG_GHM NOT LIKE '90%' 
            and for_dx.ENT_MOD <> '0' 
            and for_dx.SOR_MOD <> '0'
            and main.NIR_ANO_17 not in ('xxxxxxxxxxxxxxxxx', 'BXXXXXXXXXXXXXXXX') 
            and main.NIR_RET = '0' 
            and main.NAI_RET = '0' 
            and main.SEX_RET = '0' 
            and main.SEJ_RET = '0' 
            and main.FHO_RET = '0'  
            and main.PMS_RET = '0' 
            and main.DAT_RET = '0';


        /* --- Extract SSR Data --- */
        create table work.ssr_extract_20&year. as 
        select 
            main.NIR_ANO_17, 
            main.EXE_SOI_DTD
        from 
            oravue.T_SSR&year.C as main 
        inner join 
            oravue.T_SSR&year.B as for_dx
        on 
            main.ETA_NUM = for_dx.ETA_NUM AND main.RHA_NUM = for_dx.RHA_NUM
        where 
            main.NIR_ANO_17 in (select distinct BEN_NIR_PSA from work.filtered_treatment_cohort)
            and for_dx.ETA_NUM not in ('130780521', '130783236', '130783293', '130784234', '130804297','600100101', '750041543',
'750100018', '750100042', '750100075', '750100083', '750100091', '750100109', '750100125', '750100166', '750100208', 
'750100216', '750100232', '750100273', '750100299' , '750801441', '750803447', '750803454', '910100015', '910100023', 
'920100013', '920100021', '920100039', '920100047', '920100054', '920100062', '930100011', '930100037', '930100045', 
'940100027', '940100035', '940100043', '940100050', '940100068', '950100016', '690783154', '690784137', '690784152', 
'690784178', '690787478', '830100558')
            and for_dx.ENT_MOD <> '0' 
            and for_dx.SOR_MOD <> '0'
            and main.NIR_ANO_17 not in ('xxxxxxxxxxxxxxxxx', 'BXXXXXXXXXXXXXXXX') 
            and main.NIR_RET = '0' 
            and main.NAI_RET = '0' 
            and main.SEX_RET = '0' 
            and main.SEJ_RET = '0' 
            and main.FHO_RET = '0'  
            and main.PMS_RET = '0' 
            and main.DAT_RET = '0';


        /* --- Extract HAD Data --- */
        create table work.had_extract_20&year. as 
        select 
            main.NIR_ANO_17, 
            main.EXE_SOI_DTD
        from 
            oravue.T_HAD&year.C as main 
        inner join 
            oravue.T_HAD&year.B as for_dx
        on 
            main.ETA_NUM_EPMSI = for_dx.ETA_NUM_EPMSI AND main.RHAD_NUM = for_dx.RHAD_NUM
        where 
            main.NIR_ANO_17 in (select distinct BEN_NIR_PSA from work.filtered_treatment_cohort)
            and for_dx.ETA_NUM_EPMSI not in ('130780521', '130783236', '130783293', '130784234', '130804297','600100101', '750041543',
'750100018', '750100042', '750100075', '750100083', '750100091', '750100109', '750100125', '750100166', '750100208', 
'750100216', '750100232', '750100273', '750100299' , '750801441', '750803447', '750803454', '910100015', '910100023', 
'920100013', '920100021', '920100039', '920100047', '920100054', '920100062', '930100011', '930100037', '930100045', 
'940100027', '940100035', '940100043', '940100050', '940100068', '950100016', '690783154', '690784137', '690784152', 
'690784178', '690787478', '830100558')
            and for_dx.ENT_MOD <> '0' 
            and for_dx.SOR_MOD <> '0'
            and main.NIR_ANO_17 not in ('xxxxxxxxxxxxxxxxx', 'BXXXXXXXXXXXXXXXX') 
            and main.NIR_RET = '0' 
            and main.NAI_RET = '0' 
            and main.SEX_RET = '0' 
            and main.SEJ_RET = '0' 
            and main.FHO_RET = '0'  
            and main.PMS_RET = '0' 
            and main.DAT_RET = '0';

    %end;
    quit;
%mend extract_OTHER_data;


/* ==============================================================================
   3. RUN EXTRACTION MACROS AND COMBINE DATASETS
   ============================================================================== */
%extract_RIP_data;
%extract_OTHER_data;

/* Stack all annual PMSI extracts into one master table */
data work.master_hospital_extract;
    set work.rip_extract_: 
        work.mco_extract_:
        work.ssr_extract_:
        work.had_extract_:;
run;

/* Clean up temporary annual tables to free up WORK space */
proc datasets library=work nolist;
    delete rip_extract_: mco_extract_: ssr_extract_: had_extract_:;
quit;
