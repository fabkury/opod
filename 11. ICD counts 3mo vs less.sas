%LET _CLIENTTASKLABEL='ICD counts 3mo vs less';
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
%let proc_n = 8; /* Number of BENE_ID chunks to process. */
%let group_list = OUD_NO ONL_NO NOC_NO CA_NO OPI_NO;
%let claims_file_list = INPATIENT OUTPATIENT BCARRIER SNF;
%let str_table_prefix = &userlib..&proj_cn._STR;
%let heavy_users = HU;
%let non_heavy_users = LU;
%let heavy_use_var_name = FOUND_WEEK;
%let do_full_icd = 1; /* Count by the full ICD codes. */
%let do_icd_3d = 1; /* Count by the first 3 digits of the ICD codes. */


%macro collect_icds(c, claims_file, cohort);
/* The macro below reads all ICD codes from all claims of the cohort.
 It is intended to be used solely by the %icd_counts macro, because it
 silently requires table IC_COHORT_&c to exist. IC_COHORT_&c is created
 by %icd_counts for the purpose of slightly better efficiency.

 TO DO: Revise the strategy above. */

%if &claims_file = BCARRIER
	%then %let max_codes = 12;
	%else %let max_codes = 25;

%global cfa; /* cfa = claims_file abbreviation */
%if &claims_file = BCARRIER		%then %let cfa = CRR;
%if &claims_file = SNF			%then %let cfa = SNF;
%if &claims_file = INPATIENT	%then %let cfa = INP;
%if &claims_file = OUTPATIENT	%then %let cfa = OUTP;

/* Abreviations:
IL = ICD list (each row contains one ICD).
IL_W = ICD wide list (each row contains up to 25 ICDs). */

%let op = &userlib..&proj_cn; %* Output prefix;
%let os = &cfa._&cohort._&c.&di; %* Output suffix;

proc sql;
create table &op._IL_W_&os as
/* TO DO: Break down the years into separate SQL queries. */
/* TO DO: Fix the problems with the E and V codes. */
%do year = &year_start %to &year_end;
	%if &year > &year_start %then union;
	%do month = 1 %to 12;
		%if &month > 1 %then union all;
		select a.BENE_ID %do v=1 %to &max_codes;, ICD_DGNS_CD&v %end;
		from RIF&year..&claims_file._CLAIMS_%sysfunc(putn(&month, z2.)) a
		inner join IC_COHORT_&c b on a.BENE_ID = b.BENE_ID
			%if &debug_mode %then where a.BENE_ID < &debug_limit;
	%end;
%end;;

create index BENE_ID
on &op._IL_W_&os (BENE_ID);
quit;

data &op._IL_&os;
	set &op._IL_W_&os;
	array icd(&max_codes) $ ICD_DGNS_CD1-ICD_DGNS_CD&max_codes;
	do c = 1 to &max_codes;
		if ^missing(icd(c)) then do;
			ICD_DGNS_CD = icd(c);
			output;
		end;
	end;
	drop ICD_DGNS_CD1-ICD_DGNS_CD&max_codes;
	drop c;
run;

proc sql;
create index BENE_ID
on &op._IL_&os (BENE_ID);

%global ci_out&c;
%let ci_out&c = &op._IL_&os;

drop table &op._IL_W_&os;
quit;
%mend;


%macro aggregate_icd_counts(c, cohort, claims_files, pick_heavy_users, td);
%if &td /* td = three-digit (only consider first 3 digits) */
	%then %let name_infix = I3;
	%else %let name_infix = I;

%if &pick_heavy_users
	%then %let output_tbl =
		&userlib..&proj_cn._&name_infix._&cohort.&di._&heavy_users._&c.&di;
	%else %let output_tbl =
		&userlib..&proj_cn._&name_infix._&cohort.&di._&non_heavy_users._&c.&di;

proc sql;
create table &output_tbl as
select %if &td
	%then substr(ICD_DGNS_CD, 1, 3);
	%else ICD_DGNS_CD; as ICD,
	count(unique(BENE_ID)) as Beneficiaries,
	count(*) as Claims
from (%do t=1 %to %sysfunc(countw(&claims_files));
		%let claims_file = %sysfunc(scan(&claims_files, &t));
		/*%define_cfa(&claims_file); For some reason this is not working. */
		%if &claims_file = BCARRIER		%then %let cfa = CRR;
		%if &claims_file = SNF			%then %let cfa = SNF;
		%if &claims_file = INPATIENT	%then %let cfa = INP;
		%if &claims_file = OUTPATIENT	%then %let cfa = OUTP;
		%if &t > 1 %then union all;
		select * from &userlib..&proj_cn._IL_&cfa._&cohort._&c.&di
		%if &debug_mode %then where BENE_ID < &debug_limit;
	%end;)
group by ICD
order by Beneficiaries desc;
quit;
%mend;


%macro del_if_exists(tbl);
%if %sysfunc(exist(&tbl)) %then
	%do;
		proc datasets nolist;
		delete &tbl;
		run;
	%end;
%mend;

%macro sum_chunks(n, cohort, pick_heavy_users, td);
%if &td /* td = three-digit (only consider first 3 digits) */
	%then %let name_infix = I3;
	%else %let name_infix = I;

%if &pick_heavy_users
	%then %let input_tbl_prefix =
		&userlib..&proj_cn._&name_infix._&cohort.&di._&heavy_users;/*._&c.&di;*/
	%else %let input_tbl_prefix =
		&userlib..&proj_cn._&name_infix._&cohort.&di._&non_heavy_users;/*._&c.&di;*/

%let output_tbl = &input_tbl_prefix._&di;

proc sql;
create table &input_tbl_prefix.&di as
select a.ICD, %if &td %then Name as ;LONG_DESCRIPTION, Claims, Beneficiaries
from (select ICD, sum(Claims) as Claims, sum(Beneficiaries) as Beneficiaries
	from (%do sci=1 %to &n;
			%if &sci > 1 %then union all;
			select * from &input_tbl_prefix._&sci.&di
		%end;)
	group by ICD) a
left join %if &td %then &sharedlib..ICD9CM_3_DIGIT b on a.ICD = b.ICD;
	%else &sharedlib..CMS32_ICD9CM_DIAGNOSIS b on a.ICD = CODE;
group by a.ICD, LONG_DESCRIPTION
order by Beneficiaries desc;

%if &drop_tables %then
	%do sci=1 %to &n;
		drop table &input_tbl_prefix._&sci.&di;
	%end;
quit;
%mend;

%macro icd_counts(cohort, claims_files, pick_heavy_users);
/* td = three-digit flag. If on, only first 3 digits
 * of each ICD code are used. */
%if &debug_mode
	%then %let cap = 3;
	%else %let cap = &proc_n;

/* We are going to divide all BENE_IDs into &c chunks.
 First, calculate the cutoffs for those chunks. */
proc univariate noprint
	data=&str_table_prefix._&cohort %if &debug_mode
		%then (WHERE=(BENE_ID  < &debug_limit));;
	var BENE_ID;
	output out=IC_CHUNKS pctlpre=BENE_ID_P pctlpts=
		%do i=1 %to &proc_n-1;
			%if &i > 1 %then ,; %* Gotta hate all this syntax gymnastics.;
			%sysevalf(&i*(100/&proc_n), floor)
		%end;;
run;

%do c=1 %to &cap;
	%let prev_pct = %sysevalf((&c-1)*(100/&proc_n), floor);
	%let pct = %sysevalf(&c*(100/&proc_n), floor);
	proc sql noprint;
	%if &c < &proc_n %then
		select floor(BENE_ID_P&pct) into: bene_pct
		from IC_CHUNKS;;
	%if &c > 1 %then
		select floor(BENE_ID_P&prev_pct) into: bene_prev_pct
		from IC_CHUNKS;;
	quit;

	proc sql;
	create table IC_COHORT_&c as
	select distinct BENE_ID /* This distinct should be unnecessary, but why not. */
	from &userlib..&proj_cn._STR_&cohort
	where &heavy_use_var_name is
		%if &pick_heavy_users %then not; null
		%if &c < &proc_n %then and BENE_ID <= &bene_pct;
		%if &c > 1 %then and BENE_ID > &bene_prev_pct;
		%if &debug_mode %then and BENE_ID < &debug_limit;;

	create unique index BENE_ID
	on IC_COHORT_&c (BENE_ID);
	quit;

	%do CF=1 %to %sysfunc(countw(&claims_files));
		%collect_icds(&c, %sysfunc(scan(&claims_files, &CF)), &cohort);
		/*
		proc sql;
		select "&cohort %sysfunc(scan(&claims_files, &CF)) &c" as File,
			case when &pick_heavy_users then 'Heavy users'
				else 'Non-heavy users' end as 'Benef. group'n,
			count(unique(BENE_ID)) as Beneficiaries
		from &&ci_out&c;
		quit;
		*/
	%end;

	%if &drop_tables %then %do;
		proc sql;
		drop table IC_COHORT_&c;
		quit;
	%end;

	/* Now, count the claims and beneficiaries by ICD. */
	%if &do_full_icd %then
		%aggregate_icd_counts(&c, &cohort, &claims_files, &pick_heavy_users, 0);
	%if &do_icd_3d %then
		%aggregate_icd_counts(&c, &cohort, &claims_files, &pick_heavy_users, 1);

	%if &drop_tables %then %do;
		proc sql;
		%do t=1 %to %sysfunc(countw(&claims_files));
			%let claims_file = %sysfunc(scan(&claims_files, &t));
			/*%define_cfa(&claims_file); For some reason this is not working. */
			%if &claims_file = BCARRIER		%then %let cfa = CRR;
			%if &claims_file = SNF			%then %let cfa = SNF;
			%if &claims_file = INPATIENT	%then %let cfa = INP;
			%if &claims_file = OUTPATIENT	%then %let cfa = OUTP;
			drop table &userlib..&proj_cn._IL_&cfa._&cohort._&c.&di;
		%end;
	quit;
	%end;
%end;

/* Sum the chunks. They don't share beneficiaries, so both counts
 of claims and beneficiaries can be summed. */
%if &do_full_icd %then
	%sum_chunks(&cap, &cohort, &pick_heavy_users, 0);
%if &do_icd_3d %then
	%sum_chunks(&cap, &cohort, &pick_heavy_users, 1);

%if &drop_tables %then %do;
	proc sql;
	drop table IC_CHUNKS;
	quit;
%end;
%mend;


%macro make_tables;
%if &debug_mode
	%then %let di = u;
	%else %let di =;

%do MT_G=1 %to %sysfunc(countw(&group_list));
	%let claims_group = %sysfunc(scan(&group_list, &MT_G));
	%icd_counts(&claims_group, &claims_file_list, 0); /* Non-heavy users. */
	%icd_counts(&claims_group, &claims_file_list, 1); /* Heavy users. */
%end;
%mend;

%make_tables;

GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

