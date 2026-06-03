/* STEP 1 select population based on ALD and date of ALD in IR_IMB_R */
proc sql;
    create table work.temp_cohort as
    select BEN_NIR_PSA, BEN_RNG_GEM, IMB_ALD_NUM, IMB_ALD_DTD
    from oravue.IR_IMB_R
    where IMB_ALD_NUM in (20, 21)
      and IMB_ALD_DTD is not missing 
      and IMB_ALD_DTD > 0 
      and year(IMB_ALD_DTD) = 2011;
      
    /* Build an index to make the next lookup nearly instantaneous */
    create index patient_idx on work.temp_cohort(BEN_NIR_PSA, BEN_RNG_GEM);
quit;

/* STEP2 filter ER_CAM_F */
proc sql;
    create table work.temp_filtered_cam as
    select 
        CAM_PRS_IDE,
        FLX_DIS_DTD,
        FLX_TRT_DTD,
        FLX_EMT_TYP,
        FLX_EMT_NUM,
        FLX_EMT_ORD,
        ORG_CLE_NUM,
        DCT_ORD_NUM,
        PRS_ORD_NUM,
        REM_TYP_AFF
    from oravue.ER_CAM_F
    where CAM_PRS_IDE = 'QEQK004'
      and FLX_DIS_DTD is not missing
      and year(FLX_DIS_DTD) between 2011 and 2015;
quit;
