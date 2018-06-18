%LET _CLIENTTASKLABEL='Three months vs less';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_limit = 100000;
%let userlib = FKU838SL;
%let sharedlib = SH026250;
%let pdelib = IN026250;
%let pdereq = R6491;
%let proj_cn = OPOD2;
%let year_start = 2006;
%let year_end = 2015;
%let days_limit = 90;

%let mortality_windows = 90 180 365;
%let elig_benefs = &userlib..&proj_cn._ELIG_BENEF;
%let str_opi_no_ca = ; /* Non-cancer, regardless of OUD. */

%let time_window_var = FOUND_WEEK;

%macro compare_mortality(chrt);
proc freq data=&chrt;
	tables THREE_MONTHS*DEATH_FLAG / out=&userlib..&proj_cn._MORT_FLAG;
	%do MW=1 %to %sysfunc(countw(&mortality_windows));
		%let d = %sysfunc(scan(&mortality_windows, &MW));
		tables THREE_MONTHS*D&d.DAY / list out=&userlib..&proj_cn._MORT_D&d.DAY;
	%end;
run;

proc phreg data=&chrt;
	class THREE_MONTHS (order=internal ref=first);
	model MONTHS_AB*DEATH_FLAG(0)=THREE_MONTHS / eventcode=1;
run;

proc reg data=&chrt;
	model DEATH_FLAG = MONTHS_AB THREE_MONTHS;
run;
%mend;

%macro make_stat_table(chrt_label);
%let stat_no_ca = &userlib..&proj_cn._STAT_&chrt_label;

proc sql;
create table &stat_no_ca.&di as
select a.*,
	/* Variables for assessing mortality. */
	&time_window_var,
	case when &time_window_var is null then 0 else 1 end as THREE_MONTHS,
	case when BENE_DEATH_DT is null then 0 else 1 end as DEATH_FLAG
	%do MW=1 %to %sysfunc(countw(&mortality_windows));
		%let d = %sysfunc(scan(&mortality_windows, &MW));
		, case when BENE_DEATH_DT is null or &time_window_var is null
			then 0 else BENE_DEATH_DT <= &time_window_var + &d end as D&d.DAY
	%end;
from &elig_benefs a, &userlib..&proj_cn._STR_OPI_&chrt_label._NO b
where a.BENE_ID = b.BENE_ID
%if &debug_mode %then and a.BENE_ID < &debug_limit;;

create unique index BENE_ID
on &stat_no_ca.&di (BENE_ID);
quit;
%mend;

%macro make_tables;
%if &debug_mode %then
	%let di = u;
%else
	%let di = ;
/*
%make_stat_table(NO_CA);
*/
%compare_mortality(&stat_no_ca.&di);
%mend;

%make_tables;



GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

