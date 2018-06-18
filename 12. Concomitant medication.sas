%LET _CLIENTTASKLABEL='Concomitant medication';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
/* This code identifies prescriptions that are truly overlapping
 according to SRVC_DT and DAYS_SUPLY_NUM. You can specify  minimum
 number of days of overlap if you want (variable min_days_list). */

%let debug_mode = 0;
%let debug_threshold = 50000;
%let drop_tables = 1;
%let min_days_list = /*456 21 14*/ 0;
%let year_list = 6 7 8 9 10 11 12 13 14 15;
%let drug_class_list = /*ATC4*/ ATC3;

%let wide_fp_precision = 0.001; /* Used to avoid comparison errors due to
 numerical imprecision in small numbers. */
%let short_fp_precision = 0.01; /* Used to avoid comparison errors due to
 numerical imprecision in large numbers. */
%let percent_beneficiaries_precision = 0.0001; /* Used for writing the numbers
 to the finalized tables. */

%let do_make_overlaps_table = 1;
%let do_aggregate_class_pairs = 1;
%let do_make_finalized_tables = 0;

%let userlib = FKU838SL;
%let sharedlib = SH026250;
%let pdelib = IN026250;
%let pdereq = R6491;
%let proj_cn = OPOD; /* Project codename */


%let elig_benefs = &userlib..&proj_cn._ELIG_BENEF;
%let ndc_to_atc_map = &sharedlib..NDC_ATC4_2015;

/* Call Fabricio if you want to understand the tables below. */
%let overlaps_table_pf = &userlib..&proj_cn._C_OL_;
%let merged_overlaps_table_pf = &userlib..&proj_cn._MG_OL_;
%let dc_overlaps_table_pf = &userlib..&proj_cn._DC_OL_; /* "Discontinuous Overlaps" table */
%let summary_table_pf = &userlib..&proj_cn._SUMMARY_;
%let aggregated_pairs_table_pf = &userlib..&proj_cn._AG_;
%let finalized_table_pf = &userlib..&proj_cn._F_;
%let freq_of_p_table_pf = &userlib..&proj_cn._PR_;
%let master_age_groups_tbl = &userlib..&proj_cn._AGE_GROUPS;
%let atc_names_tbl = SH026250.ATC_NAMES_2017;

%let len_ATC1 = 1;
%let len_ATC2 = 3;
%let len_ATC3 = 4;
%let len_ATC4 = 5;
%let len_ATC5 = 7;

/* Order of the strings below must match. */
%let clms_sources = OUD_NO ONL_NO OPI_NO NOC_NO CA_NO;
%let source_suffixes = OUD ONL OPI NOC CA;

%let min_beneficiaries = 11; /* CMS imposes that no cell can refer
 to less than 11 beneficiaries. */
%let all_age_groups_label = %str('All 65+');

%let target_atcs_a = N02A C03D N05B N07BC N01AH R05DA;
%let target_atcs_b = N06AB; /* Can only contain classes of the same ATC level. */
%let target_atc_b_level = ATC4;


%macro make_overlaps_table(y);
%let claim_vars = %str(PDE_ID, PROD_SRVC_ID, BENE_ID,
	SRVC_DT, DAYS_SUPLY_NUM, QTY_DSPNSD_NUM);
/* Do the initial identification of overlaps. */
proc sql;
create view CLMS_IN_YR as
select * from &userlib..&proj_cn._CLMS_&clms_source
where YR = &y + 2000 %if &debug_mode %then
	and BENE_ID < &debug_threshold;;

create view CLMS_IN_PREV_YR as
select * from &userlib..&proj_cn._CLMS_&clms_source
where YR = &y + 2000 - 1 %if &debug_mode %then
	and BENE_ID < &debug_threshold;;

create view MOT_A_VIEW as
select BENE_ID, PROD_SRVC_ID, SRVC_DT, ATC4, sum(DAYS_SUPLY_NUM) as DAYS_SUPLY_NUM,
	sum(QTY_DSPNSD_NUM) as QTY_DSPNSD_NUM, max(PDE_ID) as PDE_ID
from (/* Grab all claims from the current year's PDE file. */
	select &claim_vars, /*ATC4*/'N02A' as ATC4 from CLMS_IN_YR a
	where a.DAYS_SUPLY_NUM > 0
	%if &y > 6 %then %do;
		/* If year > 2006, grab all claims from previous the year in which
		the days of supply extend into the current year. */
		union all
		select &claim_vars, /*ATC4*/'N02A' as ATC4 from CLMS_IN_PREV_YR b
		where b.SRVC_DT+b.DAYS_SUPLY_NUM-1 >= &date_truncation_begin
			/*and b.DAYS_SUPLY_NUM > 0 Not needed here. */
	%end;)
%if &debug_mode %then where BENE_ID < &debug_threshold;
group by BENE_ID, PROD_SRVC_ID, SRVC_DT, ATC4;

create view MOT_B_VIEW as /* MOT_B receives ATC4 later. */
select BENE_ID, PROD_SRVC_ID, SRVC_DT, sum(DAYS_SUPLY_NUM) as DAYS_SUPLY_NUM,
	sum(QTY_DSPNSD_NUM) as QTY_DSPNSD_NUM, max(PDE_ID) as PDE_ID
from (/* Grab all claims from the current year's PDE file. */
	select &claim_vars
	from %if &y > 11 %then &pdelib..PDE&y._&pdereq;
		%else &pdelib..PDESAF%sysfunc(putn(&y, z2))_&pdereq; a
	where a.DAYS_SUPLY_NUM > 0
		and a.BENE_ID in (select BENE_ID from CLMS_IN_YR)
		%if &debug_mode %then and a.BENE_ID < &debug_threshold;
	%if &y > 6 %then %do;
		/* If year > 2006, grab all claims from previous the year in which
		the days of supply extend into the current year. */
		union all
		select &claim_vars
		from %if &y-1 > 11 %then &pdelib..PDE%eval(&y-1)_&pdereq;
			%else &pdelib..PDESAF%sysfunc(putn(&y-1, z2))_&pdereq; b
		where b.SRVC_DT+b.DAYS_SUPLY_NUM-1 >= &date_truncation_begin
			/*and b.DAYS_SUPLY_NUM > 0 Not needed here because of the line above. */
			and b.BENE_ID in (select BENE_ID from CLMS_IN_PREV_YR)			
			%if &debug_mode %then and b.BENE_ID < &debug_threshold;
	%end;)
%if &debug_mode %then where BENE_ID < &debug_threshold;
group by BENE_ID, PROD_SRVC_ID, SRVC_DT;
quit;

proc sql;
/* Tables MOT_* are temporary. They will receive an
 index for identifying the overlaps. */
create table MOT_A as
select PDE_ID as MEID, BENE_ID,
	ATC4 as FullClassID, /* Full ID is needed for subsetting this table later. */
	substr(ATC4, 1, &&len_&class) as ClassID,
	MAX(SRVC_DT, &date_truncation_begin) as SRVC_DT,
	MIN(SRVC_DT+DAYS_SUPLY_NUM-1, &date_truncation_end) as SRVC_DT_END
	/* The -1 imposes that the day the prescription is filled is already
	counting as a day of medication use, i.e. patients are considered to
	begin taking their medications on the day the prescription is filled.
	The MIN(...,MDY()) truncates the durations to the last day of the year. */
from MOT_A_VIEW a
where SRVC_DT+DAYS_SUPLY_NUM-1 >= &date_truncation_begin
	and ATC4 is not null /* Not all NDCs are successfuly mapped to ATC4.
	Those NDCs represent less than 3% of all Medicare claims as per our own
	investigation. Therefore we will simply ignore them here. */
	and (%do mae_i=1 %to %sysfunc(countw(&target_atcs_a));
			%if &mae_i > 1 %then or;
			%let atc_code = %sysfunc(scan(&target_atcs_a, &mae_i));
			ATC4 like "&atc_code.%"
		%end;)
	%if &debug_mode %then and BENE_ID < &debug_threshold;;

create index OverlapIndex
on MOT_A (BENE_ID, SRVC_DT, SRVC_DT_END);
quit;

proc sql;
create table MOT_B as
select PDE_ID as MEID, BENE_ID,
	ATC4 as FullClassID, /* Full ID is needed for subsetting this table later. */
	substr(ATC4, 1, &&len_&target_atc_b_level) as ClassID,
	MAX(SRVC_DT, &date_truncation_begin) as SRVC_DT,
	MIN(SRVC_DT+DAYS_SUPLY_NUM-1, &date_truncation_end) as SRVC_DT_END
	/* The -1 imposes that the day the prescription is filled is already
	counting as a day of medication use, i.e. patients are considered to
	begin taking their medications on the day the prescription is filled.
	The MIN(...,MDY()) truncates the durations to the last day of the year. */
from MOT_B_VIEW a, &ndc_to_atc_map b
where (year(SRVC_DT) = YEAR and month(SRVC_DT) = MONTH and PROD_SRVC_ID = NDC
		and (%do mae_i=1 %to %sysfunc(countw(&target_atcs_b));
			%if &mae_i > 1 %then or;
			%let atc_code = %sysfunc(scan(&target_atcs_b, &mae_i));
			ATC4 like "&atc_code.%"
		%end;))
	and SRVC_DT+DAYS_SUPLY_NUM-1 >= &date_truncation_begin
	and ATC4 is not null /* Not all NDCs are successfuly mapped to ATC4.
	Those NDCs represent less than 3% of all Medicare claims as per our own
	investigation. Therefore we will simply ignore them here. */
	%if &debug_mode %then and BENE_ID < &debug_threshold;;

create index OverlapIndex
on MOT_B (BENE_ID, SRVC_DT, SRVC_DT_END);
quit;


/* The query belows does the actual identification of overlaps.
 We need to reorder the columns so that the DISTINCT clause works to prevent
 each overlap from appearing in two rows (A-B and B-A) instead of just one. */
%let e = %str(a.ClassID > b.ClassID); /* Clause to reorder the columns. */
proc sql;
create table &overlaps_table as
select distinct
	a.BENE_ID as Beneficiary,
	round(mean(a.MEID, b.MEID), &short_fp_precision) as MEID,
	max(a.SRVC_DT, b.SRVC_DT) as OVERLAP_BEGIN,
	min(a.SRVC_DT_END, b.SRVC_DT_END) as OVERLAP_END,
	case when &e then a.ClassID else b.ClassID end as aClass_ID,
	case when &e then b.ClassID else a.ClassID end as bClass_ID,
	case when &e then CATX('-', a.BENE_ID, a.ClassID, b.ClassID)
		else CATX('-', a.BENE_ID, b.ClassID, a.ClassID) end as merge_id
from MOT_A a, MOT_B b
where a.BENE_ID = b.BENE_ID
	/* The line below identifies the overlaps. */
	and max(a.SRVC_DT, b.SRVC_DT) <= min(a.SRVC_DT_END, b.SRVC_DT_END)
	and a.ClassID <> b.ClassID /* We decided we do not want this. */
	%if &debug_mode %then and a.BENE_ID < &debug_threshold;
order by merge_id, OVERLAP_BEGIN, OVERLAP_END;

%if &drop_tables %then %do;
	drop view CLMS_IN_YR, CLMS_IN_PREV_YR,
		MOT_A_VIEW, MOT_B_VIEW;
	drop table MOT_A, MOT_B;
%end;
quit;

/* Merge overlaps of the same merge_id (i.e. same beneficiary and same
 normalized pair or class ID) that cover the same days. */
data &merged_overlaps_table;
	set &overlaps_table;
	by merge_id OVERLAP_BEGIN OVERLAP_END;
	retain curstart curend curmeid;
	if first.merge_id then
		do;
			curend=.;
			curstart=.;
			curmeid=.;
		end;
	if OVERLAP_BEGIN > curend then
		do;
			if not (first.merge_id) then output;
			curstart=OVERLAP_BEGIN;
			curend=OVERLAP_END;
			curmeid=MEID;
		end;
	else if OVERLAP_END >= curend then /* The use of ">=" rather than only ">" is
		to force curmeid to include all MEIDs. */
		do;
			curend=OVERLAP_END;
			curmeid=mean(curmeid,MEID);
		end;
	if last.merge_id then output;
run;

/* Use this for debugging/inspecting. */
%if &debug_mode %then
	%do;
	proc sort
		data=&merged_overlaps_table;
		by Beneficiary curstart curend;
	run;

	proc sort
		data=&overlaps_table;
		by Beneficiary OVERLAP_BEGIN OVERLAP_END;
	run;	
	%end;

proc sql;
%if &drop_tables %then drop table &overlaps_table; ;

alter table &merged_overlaps_table
drop column merge_id, OVERLAP_BEGIN, OVERLAP_END, MEID;

create index GroupByIndex
on &merged_overlaps_table (Beneficiary, aClass_ID, bClass_ID);
quit;

proc datasets lib=&userlib nodetails nolist;
modify %sysfunc(substr(&merged_overlaps_table, %length(&userlib)+2));
	rename curmeid=MEID curstart=OVERLAP_BEGIN curend=OVERLAP_END;
run;

/* Export the BENE_IDs */
proc sql;
create table &merged_overlaps_table._B as
select 2000+&y as YEAR, Beneficiary as BENE_ID,
	min(OVERLAP_BEGIN) as MIN_OVERLAP_DT,
	max(OVERLAP_END) as MAX_OVERLAP_DT
from &merged_overlaps_table
group by YEAR, BENE_ID;

create unique index BENE_ID
on &merged_overlaps_table._B (BENE_ID);
quit;
%mend;

%macro aggregate_class_pairs;
/* Sum the continuous overlaps (of each pair, for each beneficiary) to get discontinuous overlaps,
and enforce the minimum discontinuous overlap. */
proc sql;
create table MDO_A as
select Beneficiary, aClass_ID, bClass_ID, mean(MEID) as MEID,
	count(*) as Occurrences, sum((OVERLAP_END-OVERLAP_BEGIN)+1) as DC_OVERLAP
from &merged_overlaps_table
group by Beneficiary, aClass_ID, bClass_ID
having DC_OVERLAP >= &min_days;

/*
Keep the table for computing the overlap string later.

%if &drop_tables & &min_days =
	%scan(&min_days_list, %sysfunc(countw(&min_days_list)))
	%then drop table &merged_overlaps_table; ;
*/
create index Beneficiary
on MDO_A (Beneficiary);

/* Add age groups (we used to enforce the restriction of age here). */
%let bene_age = 2000 + &y - year(BENE_BIRTH_DT);
create table &dc_overlaps_table as
select a.*, &bene_age as AGE_AT_END_REF_YR,
	case
	when &bene_age < 65 then '0 - 64'
	when &bene_age < 75 then '65 - 74'
	when &bene_age < 85 then '75 - 84'
	when &bene_age < 95 then '85 - 94'
	else '95+' end as AGE_GROUP	
from MDO_A a, &elig_benefs b
where a.Beneficiary = b.BENE_ID;

/* TODO: Verify if tables MDO_A have the same number of rows. Check if the
 two SQL queries can become one and still hold that same number of rows. */
drop table MDO_A;
quit;

/* Produce the table of any concomitant medication  */
%let e = %str(count(unique(Beneficiary)) as Beneficiaries,
	sum(DC_OVERLAP) as 'Sum overlap'n, max(DC_OVERLAP) as 'Max overlap'n,
	min(DC_OVERLAP) as 'Min overlap'n,
	round(mean(DC_OVERLAP), &wide_fp_precision) as 'Avg. overlap'n,
	round(std(DC_OVERLAP), &wide_fp_precision) as 'Std. overlap'n,
	round(mean(AGE_AT_END_REF_YR), &wide_fp_precision) as 'Avg. age'n,
	round(std(AGE_AT_END_REF_YR), &wide_fp_precision) as 'Std. age'n);

proc sql;
create table &summary_table as
select a.'Age group'n, a.Beneficiaries,
	round(a.Beneficiaries*100/b.Beneficiaries,
		&percent_beneficiaries_precision) as '% age group'n,
	'Sum overlap'n, 'Max overlap'n, 'Min overlap'n,
	'Avg. overlap'n, 'Std. overlap'n,
	'Avg. age'n, 'Std. age'n
from (select AGE_GROUP as 'Age group'n, &e
		from &dc_overlaps_table a
		group by 'Age group'n
		union all
		select &all_age_groups_label as 'Age group'n, &e
		from &dc_overlaps_table) a,
	(select * from &master_age_groups_tbl
	where Year = &y+2000) b
where a.'Age group'n = b.'Age group'n
order by 'Age group'n desc;
quit;

/* Use TABULATE to aggregate by pair and age group, then by drug pair only. */
proc sql;
create table ACP_A as
select CATX('-', aClass_ID, bClass_ID) as PAIR, AGE_GROUP, DC_OVERLAP
from &dc_overlaps_table;
quit;

ods select none;
proc tabulate
	data=ACP_A
	out=ACP_B;
class PAIR AGE_GROUP;
var DC_OVERLAP;
table DC_OVERLAP*(MEAN STD MEDIAN MODE)*PAIR*AGE_GROUP;
run;

proc tabulate
	data=ACP_A
	out=ACP_BA;
class PAIR;
var DC_OVERLAP;
table DC_OVERLAP*(MEAN STD MEDIAN MODE)*PAIR;
run;
ods select all;

proc sql;
drop table ACP_A;
quit;

/* Use SQL to aggregate by drug class and age group, then by class pairs only. */
%let e = %str(aClass_ID, bClass_ID,
	sum(Occurrences) as Sum_Occurrences,
	round(mean(Occurrences), &wide_fp_precision) as Mean_Occurrences,
	count(unique(Beneficiary)) as Beneficiaries,
	sum(DC_OVERLAP) as SUM_DC_OVERLAP,
	max(DC_OVERLAP) as MAX_DC_OVERLAP,
	min(DC_OVERLAP) as MIN_DC_OVERLAP,
	round(mean(DC_OVERLAP), &wide_fp_precision) as MEAN_DC_OVERLAP,
	round(std(DC_OVERLAP), &wide_fp_precision) as STD_DC_OVERLAP,
	round(mean(AGE_AT_END_REF_YR), &wide_fp_precision) as AVG_AGE,
	round(std(AGE_AT_END_REF_YR), &wide_fp_precision) as STD_AGE,
	round(mean(MEID), &short_fp_precision) as MEID);

proc sql;
create table ACP_C as
select AGE_GROUP, &e
from &dc_overlaps_table
group by AGE_GROUP, aClass_ID, bClass_ID;

create table ACP_CA as
select &e	
from &dc_overlaps_table
group by aClass_ID, bClass_ID;

%if &drop_tables %then drop table &dc_overlaps_table; ;

/* Add variables from PROC TABULATE to get the final table with age groups, 
 and unite tables with and without age groups. */
%let e = %str(aClass_ID, bClass_ID,
	Sum_Occurrences, Mean_Occurrences, Beneficiaries, SUM_DC_OVERLAP, MAX_DC_OVERLAP, MIN_DC_OVERLAP,
	MEAN_DC_OVERLAP, STD_DC_OVERLAP, DC_OVERLAP_Median as MEDIAN_DC_OVERLAP, DC_OVERLAP_Mode as MODE_DC_OVERLAP, 
	AVG_AGE, STD_AGE, MEID,
	CATX('-', Mean_Occurrences, Beneficiaries, STD_DC_OVERLAP, MEID, STD_AGE) as DI_ID);
create table ACP_D as
select a.AGE_GROUP, &e
from ACP_C a, ACP_B d
where CATX('-', aClass_ID, bClass_ID)=d.PAIR and a.AGE_GROUP=d.AGE_GROUP
	and Beneficiaries >= &min_beneficiaries /* Enforce CMS's cell size restriction. */
union all
select &all_age_groups_label as AGE_GROUP, &e
from ACP_CA a, ACP_BA d
where CATX('-', aClass_ID, bClass_ID)=d.PAIR
	and Beneficiaries >= &min_beneficiaries /* Enforce CMS's cell size restriction. */
order by DI_ID; 

drop table ACP_C, ACP_CA, ACP_B, ACP_BA;
quit;

data &aggregated_pairs_table;
	set ACP_D;
	by DI_ID;
	if _N_=1 then Duplicate_Identifier=1;
	else if first.DI_ID then Duplicate_Identifier+1;
run;

proc sql;
drop table ACP_D;

alter table &aggregated_pairs_table
drop column DI_ID;
quit;

proc sort
	data=&aggregated_pairs_table;
	by descending AGE_GROUP descending Beneficiaries descending SUM_DC_OVERLAP descending Mean_Occurrences;
run;
%mend;


%macro make_finalized_tables;
proc sql;
/* Compute beneficiary percentages and the Concomitant Medication index. */
create table MFT_A as
select distinct /* TO DO: Do we need this DISTINCT clause? */
	&y+2000 as Year, a.AGE_GROUP as 'Age group'n,
	aClass_ID as "ATC A"n, e.NAME as "ATC A Name"n,
	bClass_ID as "ATC B"n, f.NAME as "ATC B Name"n,
	a.Beneficiaries,
	round(a.Beneficiaries*100/d.Beneficiaries,
		&percent_beneficiaries_precision) as '% age group'n,
	SUM_DC_OVERLAP as 'Sum overlap'n, MAX_DC_OVERLAP as 'Max overlap'n,
	MIN_DC_OVERLAP as 'Min overlap'n, MEAN_DC_OVERLAP as 'Avg. overlap'n,
	STD_DC_OVERLAP as 'Std. overlap'n, MEDIAN_DC_OVERLAP as 'Median overlap'n,
	MODE_DC_OVERLAP as 'Mode overlap'n,
	a.AVG_AGE as 'Avg. age'n, a.STD_AGE as 'Std. age'n,
	/*d.Beneficiaries*a.Beneficiaries/(b.Beneficiaries*c.Beneficiaries) as 'CM Index'n,*/
	Duplicate_Identifier as 'Dup. ident.'n
from &aggregated_pairs_table a/*
left join &freq_of_p_table_pf.&source_suffix._&class._&y._0&di b
	on b.'Age group'n = a.AGE_GROUP and b."&class code"n = a.bClass_ID
left join &freq_of_p_table_pf.&source_suffix._&target_atc_b_level._&y._0&di c
	on c.'Age group'n = a.AGE_GROUP and c."&target_atc_b_level code"n = a.aClass_ID*/
left join &master_age_groups_tbl d
	on d.'Age group'n = a.AGE_GROUP and d.Year = &y+2000
left join &atc_names_tbl e
	on a.aClass_ID = e.ATC
left join &atc_names_tbl f
	on a.bClass_ID = f.ATC;

/* Duplicate table with inverted A-B/B-A to facilitate browsing. */
create table &finalized_table as
select "&clms_source" as 'Source'n, Year, 'Age group'n,
	"ATC B"n as "ATC A"n, "ATC B Name"n as "ATC A Name"n,
	"ATC A"n as "ATC B"n, "ATC A Name"n as "ATC B Name"n,
	Beneficiaries, '% age group'n, 'Sum overlap'n, 'Max overlap'n, 'Min overlap'n,
	'Avg. overlap'n, 'Std. overlap'n, 'Median overlap'n, 'Mode overlap'n, 'Avg. age'n, 'Std. age'n,
	'CM Index'n, 'Dup. ident.'n
from MFT_A
union
select "&clms_source" as 'Source'n, *
from MFT_A
order by 'Age group'n desc, Beneficiaries desc, "ATC A"n, "ATC B"n;

drop table MFT_A;
quit;
%mend;


%macro make_tables;
%if &debug_mode
	%then %let di = u; /* di = debug identifier */
	%else %let di =;

%do CS=1 %to %sysfunc(countw(&clms_sources));
	%let clms_source = %sysfunc(scan(&clms_sources, &CS));
	%let source_suffix = %sysfunc(scan(&source_suffixes, &CS));
	%do YL=1 %to %sysfunc(countw(&year_list));
		%let y = %scan(&year_list, &YL);
		%let date_truncation_begin = MDY(1, 1, &y); /* We formerly used MDY(2,1,&y) */
		%let date_truncation_end = MDY(12, 31, &y);
		%do I=1 %to %sysfunc(countw(&drug_class_list));
			%let class = %scan(&drug_class_list, &I);
			%let suffix = &di.&y._&class._&source_suffix;
			%let overlaps_table = &overlaps_table_pf.&suffix;
			%let merged_overlaps_table = &merged_overlaps_table_pf.&suffix;

			%if &do_make_overlaps_table %then %make_overlaps_table(&y);

			%do O=1 %to %sysfunc(countw(&min_days_list));
				%let min_days = %scan(&min_days_list, &O);
				%let dc_overlaps_table =
					&dc_overlaps_table_pf.&suffix._&min_days;
				%let summary_table =
					&summary_table_pf.&suffix._&min_days;
				%let aggregated_pairs_table =
					&aggregated_pairs_table_pf.&suffix._&min_days;
				%let finalized_table =
					&finalized_table_pf.&suffix._&min_days;
				%let sfx2 = &source_suffix._&class._&y._&min_days.&di; /* Suffix */
				%let freq_of_p_table =
					&freq_of_p_table_pf.&sfx2;
				
				%if &do_aggregate_class_pairs %then %aggregate_class_pairs;
				%if &do_make_finalized_tables %then %make_finalized_tables;
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

