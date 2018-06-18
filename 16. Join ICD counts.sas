%LET _CLIENTTASKLABEL='Join ICD counts';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let proj_cn = OPOD2;
%let userlib = FKU838SL;
%let year_list = 6 7 8 9 10 11 12 13 14 15;
%let group_list = OPI_CA_NO;


%macro make_xlsx_file_name(cohort, td);
%global xlsx_outfile;
%if &td
	%then %let filename_infix = %str(ICD 3-digit);
	%else %let filename_infix = ICD;
%let xlsx_outfile = "&myfiles_root./&proj_cn &filename_infix Light vs Heavy %eval(%sysfunc(scan(&year_list, 1))+2000)-%sysfunc(scan(&year_list, %sysfunc(countw(&year_list)))).xlsx";
%mend;


%macro join_icd_counts(cohort, td);
%if &td
	%then %let infix = ICD_3D;
	%else %let infix = ICD;

proc sort
	data=&userlib..&proj_cn._&infix._&cohort._LU;
	by ICD;
run;

proc sort
	data=&userlib..&proj_cn._&infix._&cohort._HU;
	by ICD;
run;

data &userlib..&proj_cn._&infix._&cohort._LVH;
merge
	&userlib..&proj_cn._&infix._&cohort._LU
	(drop=LONG_DESCRIPTION
	rename=(
		Beneficiaries='LU beneficiaries'n
		Claims='LU claims'n
		'% benefs'n='LU % benefs'n))
	&userlib..&proj_cn._&infix._&cohort._HU
	(rename=(
		Beneficiaries='HU beneficiaries'n
		Claims='HU claims'n
		'% benefs'n='HU % benefs'n));
by ICD;
run;

data &userlib..&proj_cn._&infix._&cohort._LVH;
	set &userlib..&proj_cn._&infix._&cohort._LVH;
	'% difference'n = 'HU % benefs'n-'LU % benefs'n;
	'% quotient'n = 'HU % benefs'n/'LU % benefs'n;
run;

proc sort
	data=&userlib..&proj_cn._&infix._&cohort._LVH;
	by descending '% difference'n;
run;
%mend;


%macro export_icd_counts(cohort, td);
%if &td
	%then %let infix = ICD_3D;
	%else %let infix = ICD;
%make_xlsx_file_name(&cohort, &td);
%put %sysfunc(fdelete(&xlsx_outfile));
proc export
data=&userlib..&proj_cn._&infix._&cohort._LVH
dbms=xlsx replace
outfile=&xlsx_outfile;
sheet="&cohort";
run;
%mend;


%macro make_tables;
%do a=1 %to %sysfunc(countw(&group_list));
	%let c = %sysfunc(scan(&group_list, &a));
	%do t=0 %to 1;
		%join_icd_counts(OPI_CA_NO, &t);
		%export_icd_counts(OPI_CA_NO, &t);
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

