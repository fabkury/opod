%LET _CLIENTTASKLABEL='Extract Part D claims';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_limit = 5000;
%let drop_tables = 1;
%let year_list = 6 7 8 9 10 11 12 13 14 15;
%let pdelib = IN026250;
%let pdereq = R6491;
%let userlib = FKU838SL;
%let sharedlib = SH026250;
%let proj_cn = OPOD;
%let opioid_atcs = N02A N07BC N01AH R05DA;

%let elig_benefs = &userlib..&proj_cn._ELIG_BENEF;
%let clms_raw = &userlib..&proj_cn._CLMS;
%let ggs = &userlib..&proj_cn._GGS; /* GNN + GCDF + STR = GGS */


%macro pd_claims_by_atc(atcs, output);
/* Get all prescriptions from eligible beneficiaries.
 Adding the ATC generates duplicates -- don't forget this. */

/* For the sake of efficiency, we will also add beneficiary
 information to each claim here. TO DO: Stop doing that? */

proc sql;
create table &output as
%do YL=1 %to %sysfunc(countw(&year_list));
	%if &YL > 1 %then union all;
	%let y = %sysfunc(scan(&year_list, &YL));
	%let bene_age = (2000+&y) - year(BENE_BIRTH_DT);

	select
		/* Prescription variables. */
		PDE_ID, /*a.BENE_ID, this goes below */
		PROD_SRVC_ID, /*ATC4,*/ a.GNN, a.STR, a.GCDF,
		SRVC_DT, DAYS_SUPLY_NUM, QTY_DSPNSD_NUM, FILL_NUM,
		TOT_RX_CST_AMT, CVRD_D_PLAN_PD_AMT, NCVRD_PLAN_PD_AMT, PTNT_PAY_AMT,
		%if &y < 14 %then put(CCW_PHARMACY_ID, z16.) as PHARMACY_ID,
			put(CCW_PRSCRBR_ID, z16.) as PRSCRBR_ID;
		%else NCPDP_ID as PHARMACY_ID, PRSCRBR_ID;,
		PDE_PRSCRBR_ID_FRMT_CD, RX_ORGN_CD,
		/* Beneficiary variables. */
		b.*, case
			when  0 <= &bene_age <= 64 then '0 - 64'
			when 65 <= &bene_age <= 74 then '65 - 74'
			when 75 <= &bene_age <= 84 then '75 - 84'
			when 85 <= &bene_age <= 94 then '85 - 94'
			when &bene_age >= 95 then '95+'
			else 'Unknown' end as AGE_GROUP,
		&bene_age as AGE_AT_END_REF_YR
	from %if &y > 11 %then &pdelib..PDE&y._&pdereq;
		%else &pdelib..PDESAF%sysfunc(putn(&y, z2))_&pdereq; a
	inner join &elig_benefs b /* Grab only eligible beneficiaries. */
		on a.BENE_ID = b.BENE_ID
	inner join (/* Pick claims by the GNN. */
		select distinct GNN/*, ATC4*/
		from &sharedlib..NDC_ATC4_2015
		where (GNN is not null and ATC4 is not NULL and
			(%do AL=1 %to %sysfunc(countw(&atcs));
				%if &AL > 1 %then or;
				%let atc = %sysfunc(scan(&atcs, &AL));
				/* Select all ATCs downstream of the one picked. */
				ATC4 like "&atc.%"
			%end;))
			or GNN in ('HYDROCODONE BITARTRATE',
				  'HYDROCODONE/ACETAMINOPHEN')) c
		on a.GNN = c.GNN
	%if &debug_mode %then where a.BENE_ID < &debug_limit;
%end;;
quit;

proc sql;
create unique index PDE_ID
on &output (PDE_ID);

/*
create index ATC4
on &output (ATC4);
*/

create index GNN
on &output (GNN);

create index BENE_ID
on &output (BENE_ID);
quit;
%mend;


%macro distinct_gnn_str_gcdf(clms_tbl, output);
proc sql;
create table &output as
select GNN, GCDF, STR, count(*) as Claims,
	count(unique(BENE_ID)) as Beneficiaries
from &clms_tbl
%if &debug_mode %then where BENE_ID < &debug_limit;
group by GNN, GCDF, STR;
quit;
%mend;


%macro make_tables;
%if &debug_mode
	%then %let di = u;
	%else %let di =;

%pd_claims_by_atc(&opioid_atcs, &clms_raw.&di);

/* The macro %distinct_gnn_str_gcdf produces a table (&ggs) that needs
 to be exported, manually added with STRENGTH and INGREDIENT columns,
 then imported back as table &ggssi_tbl (GGSSI) to be used in
 the preprocessing of the claims.
 GGSSI = GNN + GCDF + STR + STRENGTH + INGREDIENT */
%distinct_gnn_str_gcdf(&clms_raw.&di, &ggs.&di);
%mend;

%make_tables;

GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

