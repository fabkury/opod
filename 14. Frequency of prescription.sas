%LET _CLIENTTASKLABEL='Frequency of prescription';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_threshold = 100000;
%let drop_tables = 1;

%let benefs_precision = 0.0001; /* For writing the numbers
 to the finalized tables. */

%let do_add_info = 1;
%let do_aggregate_by_class = 1;

%let year_list = 6 7 8 /*9 10 11 12 13 14 15*/;
%let min_discontinuous_days_list = /*456*/ 0;

%let pdelib = IN026250;
%let pdereq = R6491;
%let userlib = FKU838SL;
%let proj_cn = OPOD2;
%let total_benef_suffix = TB;
%let class_list = ATC3 ATC4;

%let freq_of_p_table_pf = &userlib..&proj_cn._PR;
%let master_age_groups_tbl = &userlib..&proj_cn._AGE_GROUPS;
%let atc_names_tbl = SH026250.ATC_NAMES_2017;

/* TO DO: Rename tables CLMS_*_NO (remove the _NO). */
%let clms_opi_only = &userlib..&proj_cn._CLMS_COPI_ONLY_NO; /* Non-cancer, non-OUD. */
%let clms_opi = &userlib..&proj_cn._CLMS_COPI_NO; /* All opioid claims from eligible benefs. */
%let clms_oud = &userlib..&proj_cn._CLMS_COPI_OUD_NO; /* OUD, regardless of cancer. */
%let clms_ca = &userlib..&proj_cn._CLMS_COPI_CA_NO; /* Cancer, regardless of OUD. */
%let clms_opi_no_ca = &userlib..&proj_cn._CLMS_COPI_NO_CA_NO; /* Non-cancer, regardless of OUD. */

/* Order of the strings below must match. */
%let clms_sources = /*COPI_OUD_NO COPI_ONLY_NO COPI_NO*/ COPI_NO_CA_NO /*COPI_CA_NO*/;
%let source_suffixes = /*COUD CONL COPI*/ CNOC /*CCA*/;

%let min_beneficiaries = 11; /* CMS imposes that no cell can refer
 to less than 11 beneficiaries. */
%let all_age_groups_label = %str('All 65+');
%let wide_precision = 0.001; /* Used to avoid comparison errors due to
 numerical imprecision in small numbers. */
%let target_atcs_ATC3 = C03D N02A N05B N06A;
%let target_atcs_ATC4 = N07BC N01AH N06AB R05DA;

%macro prepare_claims(output);
proc sql;
create view CLMS_IN_YR as
select * from &userlib..&proj_cn._CLMS_&clms_source
where YR = &y + 2000 %if &debug_mode %then
	and BENE_ID < &debug_threshold;;

create table &output as
select PDE_ID as MEID, BENE_ID, AGE_AT_END_REF_YR, AGE_GROUP,
	%if &class = ATC1 %then substr(ATC4, 1, 1);
		%else %if &class = ATC2 %then substr(ATC4, 1, 3);
			%else %if &class = ATC3 %then substr(ATC4, 1, 4);
				%else ATC4; as ClassID,
	MAX(SRVC_DT, &date_truncation_begin) as SRVC_DT,
	MIN(SRVC_DT+(DAYS_SUPLY_NUM-1), &date_truncation_end) as SRVC_DT_END,
	CATX('-', BENE_ID, ATC4) as merge_id
from CLMS_IN_YR
/* Question: if I change this line below to a HAVING clause using the SRVC_DT_END,
 therefore avoiding writing its formula twice (which is good), will the code lose
 efficiency? */
where SRVC_DT+(DAYS_SUPLY_NUM-1) >= &date_truncation_begin
	/*and (* Subset to classes of interest. *
		%do mae_i=1 %to %sysfunc(countw(&&target_atcs_&class));
			%if &mae_i > 1 %then or;
			%let atc_code = %sysfunc(scan(&&target_atcs_&class, &mae_i));
			substr(ATC4, 1, length("&atc_code")) = "&atc_code"
		%end;)*/
	%if &debug_mode %then and BENE_ID < &debug_threshold;
	/* and DAYS_SUPLY_NUM > 0 */
order by merge_id, SRVC_DT, SRVC_DT_END;

%if &drop_tables %then drop view CLMS_IN_YR;;
quit;
%mend;


%macro aggregate_by_class(input, output);
/* Aggregate at patient-class level */

/* First, merge the intervals of the same beneficiary and class that
 cover the same days of the year. */
data AC_SUB_A&sfx2;
	set &input;
	by merge_id SRVC_DT SRVC_DT_END;
	retain curstart curend curmeid;
	if first.merge_id then
		do;
			curend=.;
			curstart=.;
			curmeid=.;
		end;
	if SRVC_DT > curend then
		do;
			if not (first.merge_id) then output;
			curstart = SRVC_DT;
			curend = SRVC_DT_END;
			curmeid = MEID;
		end;
	else if SRVC_DT_END >= curend then /* The use of ">=" rather than
	 only ">" is to force curmeid to include all MEIDs. */
		do;
			curend = SRVC_DT_END;
			curmeid = mean(curmeid, MEID);
		end;
	if last.merge_id then output;
run;

data AC_A&sfx2;
	set AC_SUB_A&sfx2;
	DURATION = (curend-curstart)+1;
run;

%if &drop_tables %then %do;
	proc sql;
	drop table AC_SUB_A&sfx2;
	quit;
%end;

proc sql;
alter table AC_A&sfx2
drop column merge_id, SRVC_DT, SRVC_DT_END, MEID;

create index GroupByIndex
on AC_A&sfx2 (AGE_GROUP, ClassID);
quit;

proc datasets lib=WORK nodetails nolist;
modify AC_A&sfx2;
rename curmeid=MEID curstart=SRVC_DT curend=SRVC_DT_END;
run;

/* Aggregate by age group and class ID */
ods select none;
proc tabulate
	data = AC_A&sfx2
	out = AC_C&sfx2;
class AGE_GROUP ClassID;
var DURATION;
table DURATION*(SUM MEAN STD MEDIAN MODE MIN MAX)*ClassID*AGE_GROUP;
run;

/* Aggregate by class ID only */
proc tabulate
	data = AC_A&sfx2
	out = AC_D&sfx2;
class ClassID;
var DURATION;
table DURATION*(SUM MEAN STD MEDIAN MODE MIN MAX)*ClassID;
run;
ods select all;

/* Calculate the total number of beneficiaries for the purpose of calculating the
 concomitant medication index. */
%let e = %str(count(unique(BENE_ID)) as Beneficiaries,
	sum(DURATION) as 'Sum duration'n,
	max(DURATION) as 'Max duration'n, min(DURATION) as 'Min duration'n,
	round(mean(DURATION), &wide_precision) as 'Avg. duration'n,
	round(std(DURATION), &wide_precision) as 'Std. duration'n,
	round(mean(AGE_AT_END_REF_YR), &wide_precision) as 'Avg. age'n,
	round(std(AGE_AT_END_REF_YR), &wide_precision) as 'Std. age'n);

proc sql;
create table &output._&total_benef_suffix as
select &y+2000 as Year, a.'Age group'n, a.Beneficiaries,
	round(a.Beneficiaries*100/b.Beneficiaries,
		&benefs_precision) as '% age group'n,
	'Sum duration'n, 'Max duration'n, 'Min duration'n,
	'Avg. duration'n, 'Std. duration'n, 'Avg. age'n, 'Std. age'n
from (select AGE_GROUP as 'Age group'n, &e
	from AC_A&sfx2
	/*where ClassID in (select ClassID from AC_B&sfx2)*/
	group by 'Age group'n
	having Beneficiaries >= &min_beneficiaries
	union all
	select &all_age_groups_label as 'Age group'n, &e
	from AC_A&sfx2
	/*where ClassID in (select ClassID from AC_B&sfx2)*/
	having Beneficiaries >= &min_beneficiaries) a,
	(select * from &master_age_groups_tbl where Year = &y+2000) b
where a.'Age group'n = b.'Age group'n
order by 'Age group'n desc;
quit;

/* Add the SAS results to the table created by SQL */
%let e1 = %str(count(unique(BENE_ID)) as Beneficiaries,
	round(mean(AGE_AT_END_REF_YR), &wide_precision) as AVG_AGE,
	round(std(AGE_AT_END_REF_YR), &wide_precision) as STD_AGE);

%let e2 = %str(DURATION_Max as MAX_DURATION, DURATION_Min as MIN_DURATION,
	DURATION_Median as MEDIAN_DURATION, DURATION_Mode as MODE_DURATION,
	DURATION_Sum as SUM_DURATION,
	round(DURATION_Mean, &wide_precision) as AVG_DURATION,
	round(DURATION_Std, &wide_precision) as STD_DURATION);

proc sql;
create table AC_B&sfx2 as
select a.*, &e2
from (select AGE_GROUP, ClassID, &e1
	from AC_A&sfx2
	group by AGE_GROUP, ClassID
	having Beneficiaries >= &min_beneficiaries) a, AC_C&sfx2 b
where a.AGE_GROUP = b.AGE_GROUP and a.ClassID = b.ClassID
union all
select a.*, &e2
from (select &all_age_groups_label as AGE_GROUP, ClassID, &e1
	from AC_A&sfx2
	group by ClassID
	having Beneficiaries >= &min_beneficiaries) a, AC_D&sfx2 b
where a.ClassID = b.ClassID;

%if &drop_tables %then drop table AC_A&sfx2, AC_C&sfx2, AC_D&sfx2;;
quit;

/* Add class names */
proc sql;
create table &output as
select "&clms_source" as 'Source'n, &y+2000 as Year, a.AGE_GROUP as 'Age group'n,
	a.ClassID as "&class code"n, b.NAME as "&class name"n,
	a.Beneficiaries, round(a.Beneficiaries*100/c.Beneficiaries,
		&benefs_precision) as '% age group'n,
	SUM_DURATION as 'Sum duration'n, MAX_DURATION as 'Max duration'n,
	MIN_DURATION as 'Min duration'n, AVG_DURATION as 'Avg. duration'n, STD_DURATION as 'Std. duration'n,
	MEDIAN_DURATION as 'Median duration'n, MODE_DURATION as 'Mode duration'n,
	AVG_AGE as 'Avg. age'n, STD_AGE as 'Std. age'n
from AC_B&sfx2 a
inner join &master_age_groups_tbl c
	on c.'Age group'n = a.AGE_GROUP and c.Year = &y+2000
left join &atc_names_tbl b
	on a.ClassID = b.ATC
order by 'Age group'n desc, Beneficiaries desc, 'Sum duration'n desc;

%if &drop_tables %then drop table AC_B&sfx2;;
quit;
%mend;


%macro make_tables;
%if &debug_mode
	%then %let di = u; /* debug identifier */
	%else %let di =;

%do CS=1 %to %sysfunc(countw(&clms_sources));
	%let clms_source = %sysfunc(scan(&clms_sources, &CS));
	%let source_suffix = %sysfunc(scan(&source_suffixes, &CS));
	%do YL=1 %to %sysfunc(countw(&year_list));
		%let y = %scan(&year_list, &YL);
		%let date_truncation_begin = MDY(1, 1, &y);
		%let date_truncation_end = MDY(12, 31, &y);
		%do I=1 %to %sysfunc(countw(&class_list));
			%let class = %scan(&class_list, &I);
			%let sfx1 = _&source_suffix._&class._&y.&di; /* Suffix */

			%if &do_add_info %then %prepare_claims(ACAG_RET&sfx1);

			%do MDDL=1 %to %sysfunc(countw(&min_discontinuous_days_list));
				%let min_discontinuous_days = %scan(&min_discontinuous_days_list, &MDDL);
				%let sfx2 = _&source_suffix._&class._&y._&min_discontinuous_days.&di; /* Suffix */

				%if &do_aggregate_by_class %then
					%aggregate_by_class(ACAG_RET&sfx1, &freq_of_p_table_pf.&sfx2);
			%end;

			/* Clean mess left behind. */
			%if &drop_tables %then %do;
				proc sql;
				drop table ACAG_RET&sfx1;
				quit;
			%end;
		%end;
	%end;
%end;
%mend;

%make_tables;


GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

