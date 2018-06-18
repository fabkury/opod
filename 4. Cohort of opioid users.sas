%LET _CLIENTTASKLABEL='Cohort of opioid users';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_limit = 10000;
%let userlib = FKU838SL;
%let proj_cn = OPOD;

%let clms_opi = &userlib..&proj_cn._CLMS;
%let chrt_opi = &userlib..&proj_cn._CHRT_OPI;

%macro make_tables;
%if &debug_mode
	%then %let di = u;
	%else %let di =;

proc sql;
create table &chrt_opi.&di as
select distinct BENE_ID
from &clms_opi
%if &debug_mode %then where BENE_ID < &debug_limit;;

create unique index BENE_ID
on &chrt_opi.&di;
quit;
%mend;

%make_tables;




GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

