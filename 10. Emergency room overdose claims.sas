%LET _CLIENTTASKLABEL='Emergency room overdose claims';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_limit = 100000;
%let drop_tables = 1;
%let userlib = FKU838SL;
%let sharedlib = SH026250;
%let pdelib = IN026250;
%let pdereq = R6491;
%let proj_cn = OPOD;
%let year_start = 2006;
%let year_end = 2015;

/* Emergency room (ER) claims are identified by the REV_CNTR variable. */

/* Codes hardcoded into algorithm:
ICD-9
	305.5X Nondependent sedative, hypnotic or anxiolytic abuse
 	965.0X Poisoning by opiates and related narcotics 

ICD-10
	F11X
	T40.0X-40.2X

The codes below we are no longer using:
	E850.0 Accidental poisoning by heroin
	E850.1 Accidental poisoning by methadone
	E850.2 Accidental poisoning by other opiates or related narcotics */

%let group_list = OUD_NO ONL_NO NOC_NO CA_NO OPI_NO;
%let chrt_erod = &userlib..&proj_cn._CLMS_EROD;
%let chrt_opi = &userlib..&proj_cn._CHRT_OPI;
%let clms_files_abbrv = INP OUTP;
%let clms_files = INPATIENT OUTPATIENT;

%macro del_if_exists(tbl);
%if %sysfunc(exist(&tbl)) %then
	%do;
		proc datasets;
		delete &tbl;
		run;
	%end;
%mend;

%macro subcohort_by_er_od
	(clms_file, clms_file_abbrv, prefix, cohort);
%if &clms_file = BCARRIER %then %let max_codes = 12;
%else %let max_codes = 25;
%let output = &prefix._&clms_file_abbrv;

%del_if_exists(&output);

%do year = &year_start %to &year_end;
	proc sql;
	create table SBI_A_&year as
	%do month = 1 %to 12;
		%if &month > 1 %then union all;
		select a.BENE_ID, a.CLM_ID, b.CLM_LINE_NUM, a.CLM_THRU_DT as CLM_DT,
			REV_CNTR %do v=1 %to &max_codes; , ICD_DGNS_CD&v %end;
		from RIF&year..&clms_file._CLAIMS_%sysfunc(putn(&month, z2.)) a,
			RIF&year..&clms_file._REVENUE_%sysfunc(putn(&month, z2.)) b,
			&cohort c
		where a.BENE_ID = b.BENE_ID = c.BENE_ID
			and a.CLM_ID = b.CLM_ID
			and ("0450" <= REV_CNTR <= "0459" or REV_CNTR = "0981") /* Claims must be for ER. */
			and (%do v=1 %to &max_codes;
				%if &v > 1 %then or; ICD_DGNS_CD&v like '3055%'
				or ICD_DGNS_CD&v like '9650%'
				or ICD_DGNS_CD&v like 'F11%'
				or ICD_DGNS_CD&v like 'T400%'
				or ICD_DGNS_CD&v like 'T401%'
				or ICD_DGNS_CD&v like 'T402%'
			%end;)
			%if &debug_mode %then and a.BENE_ID < &debug_limit;
	%end;;
	quit;

	proc append
 		base=&output data=SBI_A_&year;
	run;

	%if &drop_tables %then %do;
		proc sql;
		drop table SBI_A_&year;
		quit;
	%end;
%end;

proc sql;
create index CLM_ID
on &output (CLM_ID);

create index BENE_ID
on &output (BENE_ID);

select "&output" as Table, count(*) as Claims,
	count(unique(BENE_ID)) as Beneficiaries
from &output;
quit;
%mend;

%macro concatenate_claims
	(base, subcohorts);
proc sql;
create table &base as
%do sc=1 %to %sysfunc(countw(&subcohorts));
	%if &sc > 1 %then union all;
	select * from &base._%sysfunc(scan(&subcohorts, &sc))
%end;;

create index CLM_ID
on &base (CLM_ID);

create index BENE_ID
on &base (BENE_ID);
quit;
%mend;

%macro make_tables;
%if &debug_mode %then %do;
	%let di = u;
	%let chrt_erod = &chrt_erod.&di;
	%let year_end = 2008;
%end;
%else %let di =;

%local i;
%do i=1 %to %sysfunc(countw(&clms_files));
	%subcohort_by_er_od(
		%sysfunc(scan(&clms_files, &i)),
		%sysfunc(scan(&clms_files_abbrv, &i)),
		&chrt_erod,
		&chrt_opi);
%end;
%concatenate_claims(&chrt_erod, &clms_files_abbrv);
%mend;

%make_tables;



GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

