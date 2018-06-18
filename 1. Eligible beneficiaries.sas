%LET _CLIENTTASKLABEL='Eligible beneficiaries';
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
%let pdereq = 6491;
%let proj_cn = OPOD;
%let year_start = 2006;
%let year_end = 2015;

/* Eligible cohort: everyone in our 20% sample with full A/B/D and no HMO. */

/* Master Finder File (MFF): Contains our 20% Part D cohort. */
%let mff_file = IN026250.MFF_REQ6491;
%let elig_benefs = &userlib..&proj_cn._ELIG_BENEF;
%let master_age_groups_tbl = &userlib..&proj_cn._AGE_GROUPS;

%let all_age_groups_label = %str('All 65+');

%macro make_eligible_cohort(output);
%let mbsf_variables = %str(BENE_BIRTH_DT, BENE_DEATH_DT, VALID_DEATH_DT_SW,
	ZIP_CD, COUNTY_CD, STATE_CODE, RTI_RACE_CD, SEX_IDENT_CD, ENTLMT_RSN_ORIG);

proc sql;
create table C_A as
%do year = &year_start %to &year_end;
	%if &year > &year_start %then union all;
	select a.BENE_ID, &mbsf_variables, MAX(COVSTART, MDY(1,1,&year)) as START,
		case when BENE_DEATH_DT is null then MDY(12,31,&year)
			else BENE_DEATH_DT end as END,
		intck('MONTH', MAX(COVSTART, MDY(1,1,&year)),
			(case when BENE_DEATH_DT is null then MDY(12,31,&year)
				else BENE_DEATH_DT end))+1 as ENRLMT_IN_YEAR
	from &mff_file a inner join BENE_CC.MBSF_ABCD_&year b
		on a.BENE_ID = b.BENE_ID
	having BENE_HMO_CVRAGE_TOT_MONS = 0 /* No HMO enrollment ever. */
		and AGE_AT_END_REF_YR >= 64 /* Is this needed? */
		and ENTLMT_RSN_ORIG = '0' /* Originally enrolled due to old age. */
		and BENE_HI_CVRAGE_TOT_MONS >= ENRLMT_IN_YEAR /* Full A coverage. */
		and BENE_SMI_CVRAGE_TOT_MONS >= ENRLMT_IN_YEAR /* Full B coverage. */
		and PTD_PLAN_CVRG_MONS >= ENRLMT_IN_YEAR /* Full D coverage. */
	%if &debug_mode %then and a.BENE_ID < &debug_limit;
%end;;

create index BENE_ID
on C_A (BENE_ID);
quit;

data C_B;
	set C_A;
	by BENE_ID;
	if last.BENE_ID then output;
	%if &debug_mode %then if BENE_ID >= &debug_limit then stop;;
run;

proc sql;
create index BENE_ID
on C_B (BENE_ID);

create table &output as
select a.BENE_ID, AB_START, AB_END, MONTHS_AB, &mbsf_variables
from (select BENE_ID, min(START) as AB_START,
	max(END) as AB_END, sum(ENRLMT_IN_YEAR) as MONTHS_AB
	from C_A
	%if &debug_mode %then where BENE_ID < &debug_limit;
	group by BENE_ID
	having /* There must be no gap years in enrollment. */
		intck('MONTH', AB_START, AB_END)+1 = MONTHS_AB) a
inner join C_B b on a.BENE_ID = b.BENE_ID;

create unique index BENE_ID
on &output (BENE_ID);

%if &drop_tables %then drop table C_A, C_B;;
quit;
%mend;


%macro make_age_groups(cohort, output);
proc sql;
create table MAG_A as
%do y = &year_start %to &year_end;
	%if &y > &year_start %then union all;
	%let bene_age = &y - year(BENE_BIRTH_DT);
	select &y as Year,
		case when &bene_age < 65 then '0 - 64'
			when &bene_age < 75 then '65 - 74'
			when &bene_age < 85 then '75 - 84'
			when &bene_age < 95 then '85 - 94'
			else '95+' end as 'Age group'n,
		count(unique(BENE_ID)) as Beneficiaries
	from &cohort
	where year(AB_START) <= &y /* Beneficiary must exist in this year. */
		/* Beneficiary must not have died before this year. */
		and (BENE_DEATH_DT is null or year(BENE_DEATH_DT) >= &y)
		%if &debug_mode %then and BENE_ID < &debug_threshold;
	group by Year, 'Age group'n	
%end;;

/* Add "all age groups" together. */
create table &output as
select * from MAG_A
%do y = &year_start %to &year_end;
	union all
	select &y as Year, &all_age_groups_label as 'Age group'n,
		sum(Beneficiaries) as Beneficiaries
	from (select Beneficiaries from MAG_A
		where Year = &y and 'Age group'n <> '0 - 64')
%end;
order by Year, 'Age group'n;

%if &drop_tables %then drop table MAG_A;;
quit;
%mend;


%macro make_tables;
%if &debug_mode %then %let di = u;
%else %let di =;

%make_eligible_cohort(&elig_benefs.&di);
%make_age_groups(&elig_benefs.&di, &master_age_groups_tbl.&di);
%mend;

%make_tables;



GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

