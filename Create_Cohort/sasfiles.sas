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
      and year(FLX_DIS_DTD) between 2011 and 2020;
quit;


/* STEP3 filter ER_PRS_F */
/************************************************************************************************************************/
/** The Magic Loop	:)																									*/
/* Programme de boucle automatique permettant de mettre ï¿½ jour et extraire les donnï¿½es Mois par Mois en Flux			*/
/* Application Extraction des actes  de Tï¿½lï¿½consultation en Ville des mï¿½decins (PS Libï¿½raux et Centres de santï¿½)		*/
/* On rï¿½cupï¿½re au final une Table COMPIL_CONSO dans la Work																*/ 
/* La requï¿½te fonctionne  sur tous les profils avec Date de soins														*/
/* Des questions ? Contact : Jï¿½rï¿½me BROCCA Ministï¿½re/DNUM/SCN/SI Mutualisï¿½s des ARS : jerome.brocca@ars.sante.fr 		*/
/************************************************************************************************************************/
options LOCALE=FRENCH ;
option mprint symbolgen;

/** Etape 1 : On fait sa requï¿½te  **/
/*Extraction des Donnï¿½es sur 1 Mois de Flux avec sa propre requï¿½te */

/**Etape 2 : MACRO MA_REQUETE***/
/** On remplace et modifie sa propre  requï¿½te selon les 3 consignes suivantes : */
/* 1- la Table ER_PRS_F Avec l'Alias T1 */
/* 2- LA TABLE gï¿½nï¿½rï¿½e par la requete est WORK.CONSO */ 
/* 3-  On conserve les 2 lignes indiquï¿½es pour les conditions sur les dates de soins et de Flux **/
%MACRO MA_REQUETE;

/**On intègre Ci-dessous SA REQUETE (PROC SQL) en tenant compte des consignes précédentes **/
proc sql;
    create table work.conso as
    select  
        t1.BEN_NIR_PSA,
        t1.BEN_RNG_GEM,
        t1.BEN_NAI_ANN,
        t1.FLX_DIS_DTD,
        t1.FLX_TRT_DTD,
        t1.FLX_EMT_TYP,
        t1.FLX_EMT_NUM,
        t1.FLX_EMT_ORD,
        t1.ORG_CLE_NUM,
        t1.DCT_ORD_NUM,
        t1.PRS_ORD_NUM,
        t1.REM_TYP_AFF
    from oravue.ER_PRS_F t1
    where t1.FLX_DIS_DTD = &DFLUX 
      and t1.EXE_SOI_DTD between &DEBSOIN and &FINSOIN 
	  and t1.FLX_EMT_TYP = 1 AND t1.FLX_EMT_NUM = 36;
quit;

%MEND MA_REQUETE;


/**Etape 3 : PARAMETRES EN ENTREE***/

%LET BORNE = 1; /* 1 : Oui 0 : Non.  Indique si on a une Date de fin soins en paramï¿½tre de la requete. Si 0 La date de fin de soins sera celle du derniï¿½r  mois dispo**/

%LET DEBUT = 20200101; /*Date de Dï¿½but de Soins sous la forme AAAAMMJJ **/

%LET FIN = 20201231; /*Date de Fin de Soins sous la forme AAAAMMJJ. Modification du Paramï¿½tre non nï¿½cï¿½ssaire si BORNE=0 **/

%LET NBFLUX = 6; /* Indique le Nombre de mois de Flux prix en compte aprï¿½s Date de Fin de Soins  Modification du Paramï¿½tre non nï¿½cï¿½ssaire si si BORNE=0 **/

/**FIN DES PARAMETRES **/

/** MACRO MAGIC_LOOP **/
/** ...Et On appelle  MAGIC_LOOP **/
%m_magic_loop ;


/* STEP4 join the created databases */

