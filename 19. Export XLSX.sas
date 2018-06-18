%LET _CLIENTTASKLABEL='Export XLSX';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let proj_cn = OPOD2;
%let userlib = FKU838SL;
%let class_list = ATC3 /*ATC4*/;
%let year_list = 6 7 8 9 10 11 12 13 14 15;

/* Order of the strings below must match. */
%let clms_sources = /*COPI_OUD_NO COPI_ONLY_NO COPI_NO*/ COPI_NO_CA_NO COPI_CA_NO;
%let source_suffixes = /*COUD CONL COPI*/ CNOC CCA;

%let ds_opi_only = &userlib..&proj_cn._DOS_OPI_ONLY_NO;
%let ds_opi = &userlib..&proj_cn._DOS_OPI_NO;
%let ds_oud = &userlib..&proj_cn._DOS_OPI_OUD_NO;
%let ds_ca = &userlib..&proj_cn._DOS_OPI_CA_NO;
%let ds_opi_no_ca = &userlib..&proj_cn._DOS_OPI_NO_CA_NO;

%let heavy_users = HU;
%let non_heavy_users = LU;

%let timevars = ALL YR TRANCHE;

%let do_concomitant_med = 0;
%let do_freq_of_prescription = 0;
%let do_dose_statistics = 0;
%let do_full_icd = 1; /* Count by the full ICD codes. */
%let do_icd_3d = 1; /* Count by the first 3 digits of the ICD codes. */

%let conc_med_xlsx = "&myfiles_root./&proj_cn 3 Concomitant medication %eval(%sysfunc(scan(&year_list, 1))+2000)-%sysfunc(scan(&year_list, %sysfunc(countw(&year_list)))).xlsx";
%let freq_of_presc_xlsx = "&myfiles_root./&proj_cn 3 Frequency of prescription %eval(%sysfunc(scan(&year_list, 1))+2000)-%sysfunc(scan(&year_list, %sysfunc(countw(&year_list)))).xlsx";

%macro del_if_exists(tbl);
%if %sysfunc(exist(&tbl)) %then
	%do;
		proc datasets;
		delete &tbl;
		run;
	%end;
%mend;

%macro xlsx_icd_counts(td, clms_sources, source_suffixes);
%if &td /* td = three-digit (only consider first 3 digits) */
	%then %let name_infix = I3;
	%else %let name_infix = I;
%if &td /* td = three-digit (only consider first 3 digits) */
	%then %let xlsx_name_infix = %str(ICD 3-digit);
	%else %let xlsx_name_infix = ICD;
%let output_xlsx = "&myfiles_root./&proj_cn &xlsx_name_infix heavy users vs light users %eval(%sysfunc(scan(&year_list, 1))+2000)-%sysfunc(scan(&year_list, %sysfunc(countw(&year_list)))).xlsx";

%let hu_table = &userlib..&proj_cn._&name_infix._&clms_source._&heavy_users._;
%let lu_table = &userlib..&proj_cn._&name_infix._&clms_source._&non_heavy_users._;

%put %sysfunc(fdelete(&output_xlsx));

%do CS=1 %to %sysfunc(countw(&clms_sources));
	%let clms_source = %sysfunc(scan(&clms_sources, &CS));
	%let source_suffix = %sysfunc(scan(&source_suffixes, &CS));

	/* Add beneficiary percentages. */
	proc sql noprint;
	select count(unique(BENE_ID)) into: beneficiaries_hu
	from &userlib..&proj_cn._STR_&clms_source
	where &heavy_use_var_name is not null;

	select count(unique(BENE_ID)) into: beneficiaries_lu
	from &userlib..&proj_cn._STR_&clms_source
	where &heavy_use_var_name is null;

	create table XIC_HU as
	select *, 100*Beneficiaries/&beneficiaries_hu as '% benefs'n
	from &hu_table
	order by ICD;

	create table XIC_LU as
	select *, 100*Beneficiaries/&beneficiaries_lu as '% benefs'n
	from &lu_table
	order by ICD;
	quit;

	data XIC_F;
	merge
		XIC_LU (drop=LONG_DESCRIPTION
			rename=(
				Beneficiaries='LU beneficiaries'n
				Claims='LU claims'n
				'% benefs'n='LU % benefs'n))
		XIC_HU (rename=(
			Beneficiaries='HU beneficiaries'n
			Claims='HU claims'n
			'% benefs'n='HU % benefs'n));
	by ICD;
	run;

	data XIC_F;
		set XIC_F;
		'% difference'n = 'HU % benefs'n-'LU % benefs'n;
		'% quotient'n = 'HU % benefs'n/'LU % benefs'n;
	run;

	proc sort
		data=XIC_F;
		by descending '% difference'n;
	run;

	proc export
	data=XIC_F
	dbms=xlsx replace
	outfile=&output_xlsx;
	sheet="&source_suffix";
	run;

	proc sql;
	drop table XIC_HU, XIC_LU, XIC_F;
	quit;
%end;
%mend;

%macro make_tables;
%if &do_concomitant_med %then
	%put %sysfunc(fdelete(&conc_med_xlsx));

%if &do_freq_of_prescription %then
	%put %sysfunc(fdelete(&freq_of_presc_xlsx));

%if &do_full_icd %then
	%xlsx_icd_counts(0, &clms_sources, &source_suffixes);
%if &do_icd_3d %then
	%xlsx_icd_counts(1, &clms_sources, &source_suffixes);

%do CS=1 %to %sysfunc(countw(&clms_sources));
	%let clms_source = %sysfunc(scan(&clms_sources, &CS));
	%let source_suffix = %sysfunc(scan(&source_suffixes, &CS));

	%if &do_concomitant_med %then %do;
		%del_if_exists(BIG_CONC_TBL);
		%del_if_exists(BIG_CONC_TBL_TB);
	%end;

	%if &do_freq_of_prescription %then %do;
		%del_if_exists(BIG_FREQ_TBL);
		%del_if_exists(BIG_FREQ_TBL_TB);
	%end;

	%do CL=1 %to %sysfunc(countw(&class_list));
		%let class = %sysfunc(scan(&class_list, &CL));
		%do YL=1 %to %sysfunc(countw(&year_list));
			%let y = %sysfunc(scan(&year_list, &YL));

			%if &do_concomitant_med %then %do;
				proc append
					base=BIG_CONC_TBL
					data=&userlib..&proj_cn._F_&y._&class._&source_suffix._0;
				run;

				proc append
					base=BIG_CONC_TBL_TB
					data=&userlib..&proj_cn._SUMMARY_&y._&class._&source_suffix._0;
				run;
			%end;

			%if &do_freq_of_prescription %then %do;
				proc append
					base=BIG_FREQ_TBL
					data=&userlib..&proj_cn._PR_&source_suffix._&class._&y._0;
				run;

				proc append
					base=BIG_FREQ_TBL_TB
					data=&userlib..&proj_cn._PR_&source_suffix._&class._&y._0_TB;
				run;
			%end;
		%end;

		%if &do_concomitant_med %then %do;
			proc export
			data=BIG_CONC_TBL
			dbms=xlsx replace
			outfile=&conc_med_xlsx;
			sheet="&class &source_suffix";
			run;

			proc export
			data=BIG_CONC_TBL_TB
			dbms=xlsx replace
			outfile=&conc_med_xlsx;
			sheet="&class &source_suffix (altogether)";
			run;
			
			proc datasets;
			delete BIG_CONC_TBL BIG_CONC_TBL_TB;
			run;
		%end;

		%if &do_freq_of_prescription %then %do;
			proc export
			data=BIG_FREQ_TBL
			dbms=xlsx replace
			outfile=&freq_of_presc_xlsx;
			sheet="&class &source_suffix";
			run;

			proc export
			data=BIG_FREQ_TBL_TB
			dbms=xlsx replace
			outfile=&freq_of_presc_xlsx;
			sheet="&class &source_suffix (summary)";
			run;
			
			proc datasets;
				delete BIG_FREQ_TBL BIG_FREQ_TBL_TB;
			run;
		%end;
	%end;
%end;

%if &do_dose_statistics %then %do;
	%do TV=1 %to %sysfunc(countw(&timevars));
		%let timevar = %sysfunc(scan(&timevars, &TV));
		%let dose_stats_xlsx = "&myfiles_root./&proj_cn Dose statistics (&timevar) %eval(%sysfunc(scan(&year_list, 1))+2000)-%sysfunc(scan(&year_list, %sysfunc(countw(&year_list)))).xlsx";
		%sysfunc(fdelete(&dose_stats_xlsx));

		%do CS=1 %to %sysfunc(countw(&clms_sources));
			%let clms_source = %sysfunc(scan(&clms_sources, &CS));
			%let source_suffix = %sysfunc(scan(&source_suffixes, &CS));
		
			proc export
			data=&userlib..&proj_cn._DOS_&clms_source._&timevar
			dbms=xlsx replace
			outfile=&dose_stats_xlsx;
			sheet="&source_suffix";
			run;
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

