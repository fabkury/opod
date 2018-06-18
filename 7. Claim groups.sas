%LET _CLIENTTASKLABEL='Claim groups';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_limit = 5000;
%let drop_tables = 1;
%let userlib = FKU838SL;
/* %let sharedlib = SH026250; */
%let proj_cn = OPOD;

%let chrt_ca = &userlib..&proj_cn._CHRT_CA;
%let chrt_oud = &userlib..&proj_cn._CHRT_OUD;
%let clms_raw = &userlib..&proj_cn._CLMS;
%let clms_opi = &userlib..&proj_cn._CLMS_OPI; /* All opioid claims from eligible benefs. */
%let clms_onl = &userlib..&proj_cn._CLMS_ONL; /* Non-cancer, non-OUD. */
%let clms_oud = &userlib..&proj_cn._CLMS_OUD; /* OUD, regardless of cancer. */
%let clms_ca = &userlib..&proj_cn._CLMS_CA; /* Cancer, regardless of OUD. */
%let clms_noc = &userlib..&proj_cn._CLMS_NOC; /* Non-cancer, regardless of OUD. */
%let outlier_definitions = &userlib..&proj_cn._OUTLIER_LIMITS;

/* GNN+GCDF+STR+STRENGTH+INGREDIENT=GGSSI */
%let ggssi_tbl = &userlib..&proj_cn._GGSSI;
%let make_tranche = %str(case
	when 2006 <= year(SRVC_DT) <= 2009 then '2006-2009'
	when 2010 <= year(SRVC_DT) <= 2012 then '2010-2012'
	when 2013 <= year(SRVC_DT) <= 2015 then '2013-2015'
	else 'Unknown' end);


%macro create_clms_indexes
	(tbl);
proc sql;

create unique index PDE_ID on &tbl (PDE_ID);
/*create index ATC4 on &tbl (ATC4);
OBSERVATION: A unique index on PDE_ID is incompatible with the
 existance of the ATC4 column. */
create index GNN on &tbl (GNN);
create index BENE_ID on &tbl (BENE_ID);
quit;
%mend;

%macro add_extra_for_opod
	(clms_tbl, output);
proc sql;
create table &output as
select a.*, year(SRVC_DT) as YR, &make_tranche as TRANCHE,
	INGREDIENT, STRENGTH, STRENGTH*QTY_DSPNSD_NUM as MG,
	/* TO DO: Rethink my handling of DAYS_SUPLY_NUM=0. */
	case when DAYS_SUPLY_NUM is null or DAYS_SUPLY_NUM < 1
		then -1 else STRENGTH*QTY_DSPNSD_NUM/DAYS_SUPLY_NUM end as DOSE
from &clms_tbl a, &ggssi_tbl b
where a.GNN = b.GNN and a.STR = b.STR and a.GCDF = b.GCDF
%if &debug_mode %then and BENE_ID < &debug_limit;;
quit;
%create_clms_indexes(&output);
%mend;


%macro separate_claims_by_cohort
	(clms_tbl, chrt_tbl, output_in, output_out, min_claims);
/* output_in = claims lying inside the cohort.
   output_out = claims lying outside the cohort. */

proc sql;
create view CHRT_TBL_SUBSET as
/* Select people with > &min_claims claims (on
 different dates if &min_claims > 1). */
select * from &chrt_tbl
where CLAIMS >= &min_claims
	/* If more than one claim is required,
	they must be on different dates. */
	%if &min_claims > 1 %then and LST_CLM_DT <> FST_CLM_DT;;
quit;

proc sql;
create table &output_out as
select a.* from &clms_tbl a
left join CHRT_TBL_SUBSET b on a.BENE_ID = b.BENE_ID
where (/* Beneficiary must either have never had the condition,
	or it must have started after the Part D claim. */
	b.BENE_ID is null or FST_CLM_DT > SRVC_DT)
%if &debug_mode %then and a.BENE_ID < &debug_limit;;
quit;
%create_clms_indexes(&output_out);

proc sql;
create table &output_in as
/* Notice we can use an inner join here. */
select a.* from &clms_tbl a, CHRT_TBL_SUBSET b
where a.BENE_ID = b.BENE_ID and SRVC_DT >= FST_CLM_DT
%if &debug_mode %then and a.BENE_ID < &debug_limit;;
quit;
%create_clms_indexes(&output_in);

%if &drop_tables %then %do;
	proc sql;
	drop view CHRT_TBL_SUBSET;
	quit;
%end;
%mend;


%macro remove_outliers(input);
%let output = &input._NO; /* "No outliers" */
proc sql;
create table &output as
select a.* from &input a
left join &outlier_definitions b
	on a.INGREDIENT = b.INGREDIENT
where DOSE >= LOWER_LIMIT
	and DOSE <= UPPER_LIMIT;
quit;
%create_clms_indexes(&output);
%mend;
%macro del_if_exists(tbl);
%if %sysfunc(exist(&tbl)) %then
	%do;
		proc datasets nolist;
		delete &tbl;
		run;
	%end;
%mend;

%macro make_tables;
%if &debug_mode
	%then %let di = u;
	%else %let di =;

/* Add extra variables. Notice: The table &ggssi_tbl is prepared
 manually from the output of program "Extract claims." */
%add_extra_for_opod(&clms_raw, &clms_opi.&di)

/* Separate claims before/after a dignosis of opioid use disorder (OUD).
 1 claim required. */
%separate_claims_by_cohort(&clms_opi.&di, &chrt_oud,
	&clms_oud.&di, TEMP_OPI_NO_OUD&di, 1);

/* Separate claims before/after a cancer dignosis. 2 claims required. */
%separate_claims_by_cohort(&clms_opi.&di, &chrt_ca,
	&clms_ca.&di, TEMP_OPI_NO_CA&di, 2);

proc sql;
create table &clms_noc.&di as
select * from &clms_opi.&di
where PDE_ID not in (select PDE_ID from &clms_ca.&di);

create table &clms_onl.&di as
select * from &clms_noc.&di
where PDE_ID not in (select PDE_ID from &clms_oud.&di);
quit;

%if &drop_tables %then %do;
	%del_if_exists(TEMP_OPI_NO_OUD&di);
	%del_if_exists(TEMP_OPI_NO_CA&di);
%end;

%create_clms_indexes(&clms_noc.&di);
%create_clms_indexes(&clms_onl.&di);

/* Extract outliers separately so we keep the option of
 analyzing them later. */
%remove_outliers(&clms_oud);
%remove_outliers(&clms_onl);
%remove_outliers(&clms_opi);
%remove_outliers(&clms_ca);
%remove_outliers(&clms_noc);
%mend;

%make_tables;

/*
%macro make_tables;
%if &debug_mode
	%then %let di = u;
	%else %let di =;

%add_extra_for_opod(&clms_raw, &clms_opi.&di)

%separate_claims_by_cohort(&clms_opi.&di, &chrt_oud,
	&clms_oud.&di, TEMP_OPI_NO_OUD&di, 1);

%separate_claims_by_cohort(&clms_opi.&di, &chrt_ca,
	&clms_ca.&di, TEMP_OPI_NO_CA&di, 2);

proc sql;
create table &clms_noc.&di as
select * from &clms_opi.&di
where PDE_ID not in (select PDE_ID from &clms_ca.&di);

create table &clms_onl.&di as
select * from &clms_noc.&di
where PDE_ID not in (select PDE_ID from &clms_oud.&di);

%if &drop_tables %then
	drop table TEMP_OPI_NO_OUD&di, TEMP_OPI_NO_CA&di;;
quit;

%create_clms_indexes(&clms_noc.&di);
%create_clms_indexes(&clms_onl.&di);

%remove_outliers(&clms_oud);
%remove_outliers(&clms_onl);
%remove_outliers(&clms_opi);
%remove_outliers(&clms_ca);
%remove_outliers(&clms_noc);
%mend;
*/

GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

