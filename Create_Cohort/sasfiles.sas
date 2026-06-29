proc sql;
    create table treatment_cohort as
    select 
        /* Variables from ER_PRS_F */
        prs.EXE_SOI_DTD,
		prs.FLX_DIS_DTD,
        prs.BEN_SEX_COD,
        prs.BEN_AMA_COD,
        prs.BEN_DCD_DTE,
        prs.BEN_NIR_PSA,
        prs.BEN_RNG_GEM,
		prs.BEN_RES_DPT,
        prs.BEN_RES_COM,
        prs.PRE_PRE_DTD,
        prs.PRS_GRS_DTD,
        
            
        /* Variables from ER_PHA_F */
        pha.PHA_PRS_C13,
        pha.PHA_ACT_QSN,
        
        /* Variables from IR_PHA_R */
        ref.PHA_FRM_LIB,
        ref.PHA_ATC_L03,
        ref.PHA_ATC_LIB, 
		ref.PHA_SUB_DOS
        
    from oravue.ER_PRS_F as prs
    
    /* 1. Inner join with ER_PHA_F on the 9 linking keys */
    inner join oravue.ER_PHA_F as pha
        on  prs.FLX_DIS_DTD = pha.FLX_DIS_DTD
        and prs.FLX_TRT_DTD = pha.FLX_TRT_DTD
        and prs.FLX_EMT_TYP = pha.FLX_EMT_TYP
        and prs.FLX_EMT_NUM = pha.FLX_EMT_NUM
        and prs.FLX_EMT_ORD = pha.FLX_EMT_ORD
        and prs.ORG_CLE_NUM = pha.ORG_CLE_NUM
        and prs.DCT_ORD_NUM = pha.DCT_ORD_NUM
        and prs.PRS_ORD_NUM = pha.PRS_ORD_NUM
        and prs.REM_TYP_AFF = pha.REM_TYP_AFF
        
    /* 2. Inner join with IR_PHA_R on the CIP13 code */
    inner join oravue.IR_PHA_R as ref
        on pha.PHA_PRS_C13 = ref.PHA_RGE_C13
        
    /* 3. Population Filters & ATC Drug Class Restrictions */
    where prs.EXE_SOI_DTD between '01Jan2023'd and '31Jan2023'd
	   and prs.FLX_DIS_DTD = '01Feb2023'd
       and prs.BEN_SEX_COD = 2
      and prs.BEN_AMA_COD between 19 and 39
      and (
          /*   ref.PHA_ATC_CLA like 'N05A%' 
          or ref.PHA_ATC_CLA like 'N05B%' 
          or ref.PHA_ATC_CLA like 'N05C%' 
          or */ ref.PHA_ATC_CLA like 'N06A%' 
          /*or ref.PHA_ATC_CLA like 'N03A%'*/
      );
quit;
