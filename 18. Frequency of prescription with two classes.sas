%LET _CLIENTTASKLABEL='Frequency of prescription with two classes';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_threshold = 50000;

%let total_benef_table_suffix = TB;

%let drug_class1_list = SATC1 SATC2;
%let drug_class2_list = SVAL1 SVAL2;

%let minimum_discont_days_list = /*456*/ 0;

%let minimum_age = 65;
%let discont_days_outlier = /*50000*/ 455;

%let all_age_groups_label = %str('All 65+');

%let do_beers_list_list = 0;
%let year_list = 9;

%macro do_all;
/* Add drug class and calculate duration of prescription */
proc sql;
create table FKU838SL.W1_&y._&drug_class1._&drug_class2 as
select a.BENE_ID, PROD_SRVC_ID, BENE_AGE_AT_END_REF_YR,
	INTCK('day', SRVC_DT, intnx('day', SRVC_DT, DAYS_SUPLY_NUM)) as DURATION,
	case
		when BENE_AGE_AT_END_REF_YR < 65 then '0 - 64'
		when BENE_AGE_AT_END_REF_YR < 75 then '65 - 74'
		when BENE_AGE_AT_END_REF_YR < 85 then '75 - 84'
		when BENE_AGE_AT_END_REF_YR < 95 then '85 - 94'
		else '95+'
	end as AGE_GROUP,
	b.ClassID as ClassID&drug_class1, c.ClassID as ClassID&drug_class2
from (select BENE_ID, PROD_SRVC_ID, SRVC_DT, DAYS_SUPLY_NUM from
	%if &y < 10 %then IN026250.PDESAF0&y._R3632;
		%else %if &y < 12 %then IN026250.PDESAF&y._R3632;
			%else IN026250.PDE&y._R3632;
	%if &debug_mode %then where BENE_ID < &debug_threshold;) as a
left join (select distinct NDC, ClassID from SH026250.NDC_TO_&drug_class1) as b on PROD_SRVC_ID=b.NDC
left join (select distinct NDC, ClassID from SH026250.NDC_TO_&drug_class2) as c on PROD_SRVC_ID=c.NDC
inner join (select BENE_ID, BENE_AGE_AT_END_REF_YR from BENE_CC.MBSF_AB_%eval(2000+&y)
	%if &debug_mode %then where BENE_ID < &debug_threshold;) as d on a.BENE_ID=d.BENE_ID
where BENE_AGE_AT_END_REF_YR >= &minimum_age
%if &debug_mode %then and a.BENE_ID < &debug_threshold;;
quit;
%mend;


%macro do_the_rest;
/* Aggregate continuous medication into discontinuous medication */

proc sql;
create table FKU838SL.W2_&y._&drug_class1._&drug_class2 as
select AGE_GROUP, BENE_ID, PROD_SRVC_ID, BENE_AGE_AT_END_REF_YR,
	ClassID&drug_class1, ClassID&drug_class2, sum(DURATION) as SUM_DURATION
from FKU838SL.W1_&y._&drug_class1._&drug_class2
group by AGE_GROUP, BENE_ID, PROD_SRVC_ID, BENE_AGE_AT_END_REF_YR, ClassID&drug_class1, ClassID&drug_class2
/*having SUM_DURATION <= &discont_days_outlier 
%if &do_beers_list = 0 %then and SUM_DURATION >= &minimum_discont_days;*/;

/* Don't drop FKU838SL.W1_&y._&drug_class1._&drug_class2 yet, we will still need it. */
quit;

/* Aggregate by age group and class ID using SAS */
/* First, create a table with the ordered pair in a single variable. */
proc sql;
create table FKU838SL.W3_&y._&drug_class1._&drug_class2.__PT as
select CATX('-', ClassID&drug_class1, ClassID&drug_class2) as PAIR,
	AGE_GROUP, SUM_DURATION
from FKU838SL.W2_&y._&drug_class1._&drug_class2;
quit;

ods select none;
proc tabulate
	data = FKU838SL.W3_&y._&drug_class1._&drug_class2.__PT
	out = FKU838SL.W3_&y._&drug_class1._&drug_class2.__T;
class AGE_GROUP PAIR;
var SUM_DURATION;
table SUM_DURATION*(MEAN STD MEDIAN MODE)*PAIR*AGE_GROUP;
run;
ods select all;

/* Aggregate by age group and class ID using SQL */
proc sql;
create table FKU838SL.W3_&y._&drug_class1._&drug_class2.__ as
select AGE_GROUP, ClassID&drug_class1, ClassID&drug_class2,
	count(unique(BENE_ID)) as Beneficiaries,
	sum(SUM_DURATION) as SSUM_DURATION,
	max(SUM_DURATION) as MAX_SUM_DURATION,
	min(SUM_DURATION) as MIN_SUM_DURATION,
	round(mean(SUM_DURATION), 0.001) as AVG_DURATION,
	round(std(SUM_DURATION), 0.001) as STD_DURATION,
	round(mean(BENE_AGE_AT_END_REF_YR), 0.001) as AVG_AGE,
	round(std(BENE_AGE_AT_END_REF_YR), 0.001) as STD_AGE
from FKU838SL.W2_&y._&drug_class1._&drug_class2
group by AGE_GROUP, ClassID&drug_class1, ClassID&drug_class2
/*having Beneficiaries > 10*/;
quit;

/* Add the SAS results to the table created by SQL */
proc sql;
create table FKU838SL.W3_&y._&drug_class1._&drug_class2._ as
select a.AGE_GROUP, a.ClassID&drug_class1, a.ClassID&drug_class2, Beneficiaries,
	SSUM_DURATION, MAX_SUM_DURATION, MIN_SUM_DURATION,
	AVG_DURATION as AVG_DURATION_sql, round(SUM_DURATION_Mean, 0.001) as AVG_DURATION_sas,
	STD_DURATION as STD_DURATION_sql, round(SUM_DURATION_Std, 0.001) as STD_DURATION_sas,
	SUM_DURATION_Median as MEDIAN_DURATION, SUM_DURATION_Mode as MODE_DURATION,
	AVG_AGE, STD_AGE
from FKU838SL.W3_&y._&drug_class1._&drug_class2.__ a, FKU838SL.W3_&y._&drug_class1._&drug_class2.__T b
where CATX('-', a.ClassID&drug_class1, a.ClassID&drug_class2)=b.PAIR and a.AGE_GROUP=b.AGE_GROUP;

drop table FKU838SL.W3_&y._&drug_class1._&drug_class2.__;
drop table FKU838SL.W3_&y._&drug_class1._&drug_class2.__T;
quit;


/* Also aggregate the table without separation of age group, then add that to the 
 table with separation of age groups. */

/* Aggregate by class ID using SAS */
ods select none;
proc tabulate
	data = FKU838SL.W3_&y._&drug_class1._&drug_class2.__PT
	out = FKU838SL.W3_&y._&drug_class1._&drug_class2.___T;
class PAIR;
var SUM_DURATION;
table SUM_DURATION*(MEAN STD MEDIAN MODE)*PAIR;
run;
ods select all;

proc sql;
create table FKU838SL.W3_&y._&drug_class1._&drug_class2.___ as
select ClassID&drug_class1, ClassID&drug_class2,
	count(unique(BENE_ID)) as Beneficiaries,
	sum(SUM_DURATION) as SSUM_DURATION,
	max(SUM_DURATION) as MAX_SUM_DURATION,
	min(SUM_DURATION) as MIN_SUM_DURATION,
	round(mean(SUM_DURATION), 0.001) as AVG_DURATION,
	round(std(SUM_DURATION), 0.001) as STD_DURATION,
	round(mean(BENE_AGE_AT_END_REF_YR), 0.001) as AVG_AGE,
	round(std(BENE_AGE_AT_END_REF_YR), 0.001) as STD_AGE
from FKU838SL.W2_&y._&drug_class1._&drug_class2
group by ClassID&drug_class1, ClassID&drug_class2
/*having Beneficiaries > 10*/;
quit;

/* Add the SAS results to the table created by SQL */
proc sql;
create table FKU838SL.W3_&y._&drug_class1._&drug_class2.__ as
select &all_age_groups_label as AGE_GROUP, a.ClassID&drug_class1, a.ClassID&drug_class2,
	Beneficiaries, SSUM_DURATION, MAX_SUM_DURATION, MIN_SUM_DURATION,
	AVG_DURATION as AVG_DURATION_sql, round(SUM_DURATION_Mean, 0.001) as AVG_DURATION_sas,
	STD_DURATION as STD_DURATION_sql, round(SUM_DURATION_Std, 0.001) as STD_DURATION_sas,
	SUM_DURATION_Median as MEDIAN_DURATION, SUM_DURATION_Mode as MODE_DURATION,
	AVG_AGE, STD_AGE
from FKU838SL.W3_&y._&drug_class1._&drug_class2.___ a, FKU838SL.W3_&y._&drug_class1._&drug_class2.___T b
where CATX('-', a.ClassID&drug_class1, a.ClassID&drug_class2) = b.PAIR;

drop table FKU838SL.W3_&y._&drug_class1._&drug_class2.___;
drop table FKU838SL.W3_&y._&drug_class1._&drug_class2.___T;
drop table FKU838SL.W3_&y._&drug_class1._&drug_class2.__PT;
quit;

proc sql;
create table FKU838SL.W3_&y._&drug_class1._&drug_class2 as
select * from FKU838SL.W3_&y._&drug_class1._&drug_class2._
union all select * from FKU838SL.W3_&y._&drug_class1._&drug_class2.__;

drop table FKU838SL.W3_&y._&drug_class1._&drug_class2._;
drop table FKU838SL.W3_&y._&drug_class1._&drug_class2.__;
quit;

%if &do_beers_list = 0 %then
	%do;
		/* Calculate the total number of beneficiaries for the purpose of calculating the
		 concomitant medication index. */
		proc sql;
		create table FKU838SL.PR_BY_&drug_class1._&drug_class2._&y._&minimum_discont_days.DAY_&total_benef_table_suffix.&di as
		select * from
		(select AGE_GROUP, count(unique(BENE_ID)) as TotalBeneficiaries
			from FKU838SL.W2_&y._&drug_class1._&drug_class2
			where ClassID&drug_class1 in (select ClassID&drug_class1 from FKU838SL.W3_&y._&drug_class1._&drug_class2)
				and ClassID&drug_class2 in (select ClassID&drug_class2 from FKU838SL.W3_&y._&drug_class1._&drug_class2)
			group by AGE_GROUP)
		union all
		(select &all_age_groups_label as AGE_GROUP, count(unique(BENE_ID)) as TotalBeneficiaries
			from FKU838SL.W2_&y._&drug_class1._&drug_class2
			where ClassID&drug_class1 in (select ClassID&drug_class1 from FKU838SL.W3_&y._&drug_class1._&drug_class2)
				and ClassID&drug_class2 in (select ClassID&drug_class2 from FKU838SL.W3_&y._&drug_class1._&drug_class2));
		quit;
	%end;

proc sql;
drop table FKU838SL.W2_&y._&drug_class1._&drug_class2;
quit;

/* Add class names */
proc sql;
create table FKU838SL.PR_BY_&drug_class1._&drug_class2._&y._&minimum_discont_days.DAY&di as
select b.ClassName as ClassName&drug_class1, c.ClassName as ClassName&drug_class2, a.*
from FKU838SL.W3_&y._&drug_class1._&drug_class2 as a
left join (select distinct ClassID, ClassName from SH026250.NDC_TO_&drug_class1) as b
	on a.ClassID&drug_class1=b.ClassID
left join (select distinct ClassID, ClassName from SH026250.NDC_TO_&drug_class2) as c
	on a.ClassID&drug_class2=c.ClassID
order by AGE_GROUP, Beneficiaries desc, SSUM_DURATION desc;

drop table FKU838SL.W3_&y._&drug_class1._&drug_class2;
quit;
%mend;

%macro make_tables;
/* di = debug identifier */
%if &debug_mode %then %let di = di;
%else %let di =;

%do BLL=1 %to %sysfunc(countw(&do_beers_list_list));
	%let do_beers_list = %scan(&do_beers_list_list, &BLL);
	%do YL=1 %to %sysfunc(countw(&year_list));
		%let y = %scan(&year_list, &YL);
		%do I=1 %to %sysfunc(countw(&drug_class1_list));
			%let drug_class1 = %scan(&drug_class1_list, &I);
			%do J=1 %to %sysfunc(countw(&drug_class2_list));
				%let drug_class2 = %scan(&drug_class2_list, &J);
				%do_all;
				%do MDDL=1 %to %sysfunc(countw(&minimum_discont_days_list));
					%let minimum_discont_days = %scan(&minimum_discont_days_list, &MDDL);
					%do_the_rest;
				%end;
				/* Clean mess left behind. */
				proc sql;
				drop table FKU838SL.W1_&y._&drug_class1._&drug_class2;
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

