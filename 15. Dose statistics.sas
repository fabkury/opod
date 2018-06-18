%LET _CLIENTTASKLABEL='Dose statistics';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_limit = 50000;
%let drop_tables = 1;
%let userlib = FKU838SL;
%let proj_cn = OPOD2;

/* Call Fabricio if you want to understand the tables below. */
%let clms_opi_only = &userlib..&proj_cn._CLMS_OPI_ONLY_NO; /* Non-cancer, non-OUD. */
%let clms_opi = &userlib..&proj_cn._CLMS_OPI_NO; /* All opioid claims from eligible benefs. */
%let clms_oud = &userlib..&proj_cn._CLMS_OPI_OUD_NO; /* OUD, regardless of cancer. */
%let clms_ca = &userlib..&proj_cn._CLMS_OPI_CA_NO; /* Cancer, regardless of OUD. */
%let clms_opi_no_ca = &userlib..&proj_cn._CLMS_OPI_NO_CA_NO; /* Non-cancer, regardless of OUD. */

%let ds_opi_only = &userlib..&proj_cn._DOS_OPI_ONLY_NO;
%let ds_opi = &userlib..&proj_cn._DOS_OPI_NO;
%let ds_oud = &userlib..&proj_cn._DOS_OPI_OUD_NO;
%let ds_ca = &userlib..&proj_cn._DOS_OPI_CA_NO;
%let ds_opi_no_ca = &userlib..&proj_cn._DOS_OPI_NO_CA_NO;

%macro isBlank(param);
%sysevalf(%superq(param),boolean)
%mend isBlank;

%macro dose_statistics(clms_tbl, output, timevar);
/* Tabulate across the time variable. */
%local tabulate_opts;
%let tabulate_opts = MEAN STD MIN P1 P25 MEDIAN P75 P99 MAX MODE;
ods select none;
proc tabulate out=&output._&timevar
	data=&clms_tbl %if &debug_mode %then (obs=&debug_limit);;
	class INGREDIENT %if &timevar ^= ALL %then &timevar;;
	var DOSE DAYS_SUPLY_NUM QTY_DSPNSD_NUM STRENGTH;
	table (DOSE*(&tabulate_opts)
		DAYS_SUPLY_NUM*(&tabulate_opts)
		QTY_DSPNSD_NUM*(&tabulate_opts)
		STRENGTH*(&tabulate_opts)
		N) * INGREDIENT %if &timevar ^= ALL %then * &timevar;;
run;
ods select all;

data &output._&timevar;
	set &output._&timevar (RENAME=(N=CLAIMS)
		DROP=_TYPE_ _PAGE_ _TABLE_);
run;
%mend;
/*
%dose_statistics(&clms_opi, &ds_opi, ALL);

proc sql;
create table FKU838SL.OPOD2_OUTLIER_LIMITS as
select INGREDIENT, STRENGTH_Min/4 as LOWER_LIMIT,
	STRENGTH_Max*18 as UPPER_LIMIT
from FKU838SL.OPOD2_DS_OPI_ALL;
quit;
*/


%dose_statistics(&clms_oud, &ds_oud, ALL);
%dose_statistics(&clms_oud, &ds_oud, YR);
%dose_statistics(&clms_oud, &ds_oud, TRANCHE);
%dose_statistics(&clms_opi, &ds_opi, ALL);
%dose_statistics(&clms_opi, &ds_opi, YR);
%dose_statistics(&clms_opi, &ds_opi, TRANCHE);
%dose_statistics(&clms_opi_only, &ds_opi_only, ALL);
%dose_statistics(&clms_opi_only, &ds_opi_only, YR);
%dose_statistics(&clms_opi_only, &ds_opi_only, TRANCHE);
%dose_statistics(&clms_ca, &ds_ca, ALL);
%dose_statistics(&clms_ca, &ds_ca, YR);
%dose_statistics(&clms_ca, &ds_ca, TRANCHE);
%dose_statistics(&clms_opi_no_ca, &ds_opi_no_ca, ALL);
%dose_statistics(&clms_opi_no_ca, &ds_opi_no_ca, YR);
%dose_statistics(&clms_opi_no_ca, &ds_opi_no_ca, TRANCHE);


GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

