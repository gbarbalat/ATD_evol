First Inspection:  
- In **IR_IMB_R**, take IMB_ALD_NUM=21 and IMB_ALD_NUM=20, IMB_ALD_DTD should contain 2011, also take BEN_NIR_PSA BEN_RNG_GEM
- Inner Join with **IR_BEN_R** by BEN_NIR_PSA BEN_RNG_GEM, take BEN_NAI_ANN
- Calculate Age=Year(IMB_ALD_DTD)-BEN_NAI_ANN, only take if Age>50
- Inner Join with **ER_PRS_F** by BEN_NIR_PSA BEN_RNG_GEM, take FLX_DIS_DTD FLX_TRT_DTD FLX_EMT_TYP FLX_EMT_NUM FLX_EMT_ORD ORG_CLE_NUM DCT_ORD_NUM PRS_ORD_NUM REM_TYP_AFF
- Inner Join with **ER_CAM_F** by FLX_DIS_DTD FLX_TRT_DTD FLX_EMT_TYP FLX_EMT_NUM FLX_EMT_ORD ORG_CLE_NUM DCT_ORD_NUM PRS_ORD_NUM REM_TYP_AFF, take CAM_PRS_IDE


proc sql;
    create table work.snds_extracted_data as
    select 
        /* Identifiers */
        imb.BEN_NIR_PSA,
        imb.BEN_RNG_GEM,
        
        /* IR_IMB_R Columns */
        imb.IMB_ALD_NUM,
        imb.IMB_ALD_DTD,
        
        /* IR_BEN_R Columns */
        ben.BEN_NAI_ANN,
        
        /* ER_PRS_F Columns */
        prs.FLX_DIS_DTD,
        prs.FLX_TRT_DTD,
        prs.FLX_EMT_TYP,
        prs.FLX_EMT_NUM,
        prs.FLX_EMT_ORD,
        prs.ORG_CLE_NUM,
        prs.DCT_ORD_NUM,
        prs.PRS_ORD_NUM,
        prs.REM_TYP_AFF,
        
        /* ER_CAM_F Columns */
        cam.CAM_PRS_IDE

    from oravue.IR_IMB_R as imb
    
    /* 1. Join with Beneficiary table */
    inner join oravue.IR_BEN_R as ben
        on  imb.BEN_NIR_PSA = ben.BEN_NIR_PSA
        and imb.BEN_RNG_GEM = ben.BEN_RNG_GEM
        
    /* 2. Join with Prescription table */
    inner join oravue.ER_PRS_F as prs
        on  imb.BEN_NIR_PSA = prs.BEN_NIR_PSA
        and imb.BEN_RNG_GEM = prs.BEN_RNG_GEM
        
    /* 3. Join with CCAM table */
    inner join oravue.ER_CAM_F as cam
        on  prs.FLX_DIS_DTD = cam.FLX_DIS_DTD
        and prs.FLX_TRT_DTD = cam.FLX_TRT_DTD
        and prs.FLX_EMT_TYP = cam.FLX_EMT_TYP
        and prs.FLX_EMT_NUM = cam.FLX_EMT_NUM
        and prs.FLX_EMT_ORD = cam.FLX_EMT_ORD
        and prs.ORG_CLE_NUM = cam.ORG_CLE_NUM
        and prs.DCT_ORD_NUM = cam.DCT_ORD_NUM
        and prs.PRS_ORD_NUM = cam.PRS_ORD_NUM
        and prs.REM_TYP_AFF = cam.REM_TYP_AFF

    where 
        /* Filter ALD diagnoses (20 or 21) */
        imb.IMB_ALD_NUM in (20, 21)
        
    ;
quit;
