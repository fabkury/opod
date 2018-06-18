%LET _CLIENTTASKLABEL='Remove unwanted claims';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_limit = 1000;
%let userlib = FKU838SL;
%let proj_cn = OPOD;

%let clms_opi = &userlib..&proj_cn._CLMS;
%let outlier_limits = &userlib..&proj_cn._OUTLIER_LIMITS;
/* GNN+GCDF+STR+STRENGTH+INGREDIENT=GGSSI */
%let ggssi_tbl = &userlib..&proj_cn._GGSSI;

%macro make_tables;
%if &debug_mode
	%then %let di = u;
	%else %let di =;

proc sql;
create table &clms_opi._CLEAN&di as
select a.*
from &clms_opi a
inner join (select * from
	&ggssi_tbl a inner join	&outlier_limits b
	on a.INGREDIENT = b.INGREDIENT
	where Remove <> 'x') b
on a.GNN = b.GNN and a.GCDF = b.GCDF and a.STR = b.STR
%if &debug_mode %then where BENE_ID < &debug_limit;;

create unique index BENE_ID
on &chrt_opi.&di;
quit;

/* Notice that the lines below do not use the macro variable
 &clms_opi due to the syntax of PROC DATASETS. In addition, it
 does not use the debug indicator &di because we only want the
 operation to succeed if this is not debug mode. */
%if ^&debug_mode %then %do;
	proc datasets lib=&userlib nolist;
		CHANGE &proj_cn._CLMS=&proj_cn._CLMS_ALL_GNNS
			&proj_cn._CLMS_CLEAN=&proj_cn._CLMS;
	run;
%end;
%mend;

%make_tables;




GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

