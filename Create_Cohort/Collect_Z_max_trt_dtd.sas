PROC SQL;
   CREATE TABLE WORK.ben_max_trt_dtd AS
   SELECT 
      flt.BEN_NIR_PSA,
      flt.BEN_RNG_GEM,
      ben.MAX_TRT_DTD
   FROM (
      /* Extract unique patient keys first to optimize join performance */
      SELECT DISTINCT BEN_NIR_PSA, BEN_RNG_GEM 
      FROM WORK.filtered_treatment_cohort
   ) AS flt
   INNER JOIN ORAVUE.IR_BEN_R AS ben
      ON  flt.BEN_NIR_PSA = ben.BEN_NIR_PSA
      AND flt.BEN_RNG_GEM = ben.BEN_RNG_GEM;
QUIT;
