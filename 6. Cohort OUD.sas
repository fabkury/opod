%LET _CLIENTTASKLABEL='Cohort OUD';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_limit = 10000;
%let drop_tables = 1;
%let userlib = FKU838SL;
%let sharedlib = SH026250;
%let pdelib = IN026250;
%let pdereq = R6491;
%let proj_cn = OPOD;
%let year_start = 2006;
%let year_end = 2015;

/* Codes hardcoded into algorithm:
ICD-9
	304.0 Opioid type dependence
 	304.7 Combinations of opioid type drug with any other drug dependence

ICD-10
	F11X
*/

%let chrt_oud = &userlib..&proj_cn._CHRT_OPI_OUD;
%let chrt_opi = &userlib..&proj_cn._CHRT_OPI;
%let clms_files_abbrv = INP CRR SNF OUTP;
%let clms_files = INPATIENT BCARRIER SNF OUTPATIENT;


%macro del_if_exists(tbl);
%if %sysfunc(exist(&tbl)) %then
	%do;
		proc datasets;
		delete &tbl;
		run;
	%end;
%mend;


%macro subcohort_by_oud
	(clms_file, clms_file_abbrv, prefix, cohort);
%if &clms_file = BCARRIER %then %let max_codes = 12;
%else %let max_codes = 25;
%let output = &prefix._&clms_file_abbrv;

%del_if_exists(SBI_A);

%do year = &year_start %to &year_end;
	proc sql;
	create table SBI_A_&year as
	%do month = 1 %to 12;
		%if &month > 1 %then union all;
		select a.BENE_ID, CLM_THRU_DT as CLM_DT
		from RIF&year..&clms_file._CLAIMS_%sysfunc(putn(&month, z2.)) a
		inner join &cohort b on a.BENE_ID = b.BENE_ID
		where (%do v=1 %to &max_codes;
				%if &v > 1 %then or; ICD_DGNS_CD&v like '3040%'
				or ICD_DGNS_CD&v like '3047%'
				or ICD_DGNS_CD&v like 'F11%'
			%end;)
			%if &debug_mode %then and a.BENE_ID < &debug_limit;
	%end;;
	quit;

	proc append
 		base=SBI_A data=SBI_A_&year;
	run;

	%if &drop_tables %then %do;
		proc sql;
		drop table SBI_A_&year;
		quit;
	%end;
%end;

proc sql;
create index BENE_ID
on SBI_A (BENE_ID);

create table &output as
select BENE_ID, count(*) as CLAIMS,
	min(CLM_DT) as FST_CLM_DT, max(CLM_DT) as LST_CLM_DT
from SBI_A
group by BENE_ID;

%if &drop_tables %then drop table SBI_A; ;

create unique index BENE_ID
on &output (BENE_ID);
quit;
%mend;


%macro combine_by_claims
	(base, subcohorts);
proc sql;
create table &base as
select BENE_ID, sum(CLAIMS) as CLAIMS,
	min(FST_CLM_DT) as FST_CLM_DT, max(LST_CLM_DT) as LST_CLM_DT
from (%do sc=1 %to %sysfunc(countw(&subcohorts));
		%if &sc > 1 %then union all;
		select * from &base._%sysfunc(scan(&subcohorts, &sc))
	%end;)
group by BENE_ID;

create unique index BENE_ID
on &base (BENE_ID);
quit;

proc sql;
select "&base" as Table, 'All beneficiaries' as Criteria, count(*) as Beneficiaries
from &base
union all
select "&base" as Table, '>1 CA claim' as Criteria, count(*) as Beneficiaries
from &base where CLAIMS > 1
union all
select "&base" as Table, '>1 CA claim on diff. dates' as Criteria, count(*) as Beneficiaries
from &base where CLAIMS > 1 and FST_CLM_DT <> LST_CLM_DT;
quit;
%mend;

%macro make_tables;
%if &debug_mode %then %do;
	%let di = u;
	%let chrt_oud = &chrt_oud.&di;
	%let year_end = 2008;
%end;
%else %let di =;

%local i;
%do i=1 %to %sysfunc(countw(&clms_files));
	%subcohort_by_oud(
		%sysfunc(scan(&clms_files, &i)),
		%sysfunc(scan(&clms_files_abbrv, &i)),
		&chrt_oud,
		&chrt_opi);
%end;
%combine_by_claims(&chrt_oud, &clms_files_abbrv);
%mend;

%make_tables;



GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

