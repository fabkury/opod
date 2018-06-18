%LET _CLIENTTASKLABEL='Drug strings and time windows';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\opod\opod.egp';
%LET _CLIENTPROJECTNAME='opod.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_limit = 10000;
%let drop_tables = 1;
%let userlib = FKU838SL;
/* %let sharedlib = SH026250; */
%let proj_cn = OPOD;
%let table_list = ONL_NO NOC_NO OUD_NO CA_NO OPI_NO;
%let clms_table_prefix = CLMS;
%let clms_str_prefix = STR;
%let overlap_table_prefix = OVL_CLMS;
%let overlap_str_prefix = OVL_STR;
%let do_claims_tables = 0;
%let do_overlap_tables = 1;
%let study_start = MDY(1, 1, 2006);
%let study_end = MDY(12, 31, 2015);
%let intervals = MONTH; /* Arguments to intck() */
%let make_binary_string = 1;
%let make_continuous_string = 1;
%let minimum_days = 90; /* Minimum days of opioid use. */
%let maximum_window = 120; /* Maximum window to look for &minimum_days. */


%macro make_drug_string(input, output, interval_name);
%let interval = "&interval_name";
%let binary_val = BINARY_&interval_name;
%let cont_val = CONTINUOUS_&interval_name;
%let claim_end = MIN(intnx('day', SRVC_DT, DAYS_SUPLY_NUM-1), &study_end);

%if &interval_name=QUARTER %then %let max_val = 91;
%if &interval_name=MONTH %then %let max_val = 30;
%if &interval_name=SEMIMONTH %then %let max_val = 15;
%if &interval_name=WEEK %then %let max_val = 7;

/* TO DO: Assign the variable binary_intervals and continuous_intervals
 in some better way. */
proc sql noprint;
select distinct
	intck(&interval, &study_start, &study_end)+1
	into: binary_intervals
from SH026250.cisa2_tab1_pp; /* Can be any table... */

%if &make_continuous_string %then %do;
	select distinct
		(intck(&interval, &study_start, &study_end)+1)*3
		into: continuous_intervals
	from SH026250.cisa2_tab1_pp; /* Can be any table... */
%end;
quit;

/*
This should be unnecessary because the tables are supposed to have
an index on BENE_ID and therefore be sorted by this variable.

proc sort data=&input;
	by BENE_ID;
run;
*/

data &output;
	set &input (keep = BENE_ID SRVC_DT DAYS_SUPLY_NUM);
	by BENE_ID;
	retain %if &make_binary_string %then &binary_val;
		%if &make_continuous_string %then &cont_val; ;
	%if &make_binary_string %then %do;
	length &binary_val $ &binary_intervals;
	length TEMP_&binary_val $ &binary_intervals;
	%end;
	%if &make_continuous_string %then %do;
	length &cont_val $ &continuous_intervals;
	length TEMP_&cont_val $ &continuous_intervals;
	%end;

	/* TO DO: Discuss this with Seo Baik. */
	if DAYS_SUPLY_NUM = 0 then DAYS_SUPLY_NUM = 1;

	/* TO DO: Use inline ternary operator (or equivalent) instead of these repetitive nested ifs. */
	%if &make_binary_string %then %do;
		if intck(&interval, &study_start, SRVC_DT) > 0 then
		do;
			if intck(&interval, &claim_end, &study_end) > 0 then
				TEMP_&binary_val = repeat('0', intck(&interval, &study_start, SRVC_DT)-1)
					|| repeat('1', intck(&interval, SRVC_DT, &claim_end))
					|| repeat('0', intck(&interval, &claim_end, &study_end)-1);
			else
				TEMP_&binary_val = repeat('0', intck(&interval, &study_start, SRVC_DT)-1)
					|| repeat('1', intck(&interval, SRVC_DT, &claim_end));
		end;
		else do;
			if intck(&interval, &claim_end, &study_end) > 0 then
				TEMP_&binary_val = repeat('1', intck(&interval, SRVC_DT, &claim_end))
					|| repeat('0', intck(&interval, &claim_end, &study_end)-1);
			else
				TEMP_&binary_val = repeat('1', intck(&interval, SRVC_DT, &claim_end));
		end;
	%end;

	/* TO DO: The continuous string in this function is not working. */
	%if &make_continuous_string %then %do;
		if intck(&interval, SRVC_DT, &claim_end) > 0 then
			/* The prescription crosses the boundary of a week, therefore 2 or 3 numbers
			will represent it. The middle number -- the 7s -- will be automatically
			excluded if the length provided to repeat() is negative. */
			TEMP_&cont_val = repeat('00-', intck(&interval, &study_start, SRVC_DT)-1)
				|| put(intck('day', SRVC_DT, intnx(&interval, SRVC_DT, 0, 'end'))+1, z2.) || '-'
				|| repeat(put(&max_val, z2.)||'-', intck(&interval, SRVC_DT, &claim_end)-2)
				|| put(intck('day', intnx(&interval, &claim_end, 0, 'beg'), &claim_end)+1, z2.) || '-'
				|| repeat('00-', intck(&interval, &claim_end, &study_end)-1);
		else
			/* The prescription does not cross the boundary of an interval, therefore a single number
			will represent it. */
			TEMP_&cont_val = repeat('00-', intck(&interval, &study_start, SRVC_DT)-1)
				|| put(intck('day', SRVC_DT, &claim_end)+1, z2.) || '-'
				|| repeat('00-', intck(&interval, &claim_end, &study_end)-1);
	%end;

	if first.BENE_ID then do;
		/* Store the string of the first row. */
		%if &make_binary_string %then &binary_val = TEMP_&binary_val;;
		%if &make_continuous_string	%then &cont_val = TEMP_&cont_val;;
	end;
	else do i = 1 to &binary_intervals;
		/* Add the strings across rows. */
		%if &make_binary_string %then
			if substr(TEMP_&binary_val, i, 1) = '1'
				then substr(&binary_val, i, 1) = '1';;
		%if &make_continuous_string %then
			substr(&cont_val, (i*3)-2, 2) =
				put(min(input(substr(&cont_val, (i*3)-2, 2), 2.)
				+ input(substr(TEMP_&cont_val, (i*3)-2, 2), 2.),
				&max_val), z2.);;
	end;
	
	if last.BENE_ID then do;
		/* Remove temporary data and output a single row per beneficiary. */
		drop i SRVC_DT DAYS_SUPLY_NUM
			%if &make_binary_string %then TEMP_&binary_val;
			%if &make_continuous_string %then TEMP_&cont_val;;
		output;
	end;

	%if &debug_mode %then if BENE_ID >= &debug_limit then stop;;
run;

proc sql;
select "&output" as Table,
	%if &make_binary_string %then
	min(length(&binary_val)) as min_binary,
	max(length(&binary_val)) as max_binary;
	%if &make_continuous_string %then %do;
		%if &make_binary_string %then ,;
		min(length(&cont_val)) as min_continuous,
		max(length(&cont_val)) as max_continuous
	%end;
from &output;
quit;
%mend;

/* The macro below reads the drug use strings and identifies
 whether the beneficiary had least &days of drug use inside
 a window of &window days.*/
%macro find_days_in_window(str_tbl, interval_name, days, window);
%if &interval_name=QUARTER %then %let max_val = 91;
%if &interval_name=MONTH %then %let max_val = 30;
%if &interval_name=SEMIMONTH %then %let max_val = 15;
%if &interval_name=WEEK %then %let max_val = 7;

%let max_intervals = %sysfunc(ceil(&window/&max_val));
%let str_column = CONTINUOUS_&interval_name;

proc sql;
select distinct
	(intck("&interval_name", &study_start, &study_end)+1)*3
	into: continuous_intervals
from SH026250.cisa2_tab1_pp; /* Can be any table... */
quit;

data &str_tbl;
	set &str_tbl;
	FOUND_&interval_name =.; /* TO DO: Find a better name for this variable. */
	do i=1 to &continuous_intervals - &max_intervals;
		if FOUND_&interval_name ^=. then leave;
		sum_days = 0;
		do j=i to i+&max_intervals;
			sum_days = sum_days + input(substr(&str_column, (j*3)-2, 2), 2.);
			if sum_days > &days then do;
				/* The "-1" in "fj-1" means we assign as the date the beneficiary completed
the minimum number of days to be the first day of the interval (week, month...) in which the
minimum number of days is attained. E.g. If the beneficiary attains 90 days in June 12th, the
assigned date is June 1st. */
				FOUND_&interval_name = intnx("&interval_name", &study_start, j-1);
				leave;
			end;
		end;
	end;	
	drop i j sum_days;
run;
%mend;

%macro wrapper(clms_tbl_pf, out_tbl_pf, make_strings, find_window);
%do t=1 %to %sysfunc(countw(&table_list));
	%let tbl = %sysfunc(scan(&table_list, &t));
	%do IL=1 %to %sysfunc(countw(&intervals));
		%let ri = %sysfunc(scan(&intervals, &IL));
		%if &make_strings %then
			%make_drug_string(&userlib..&proj_cn._&clms_tbl_pf._&tbl,
				&userlib..&proj_cn._&out_tbl_pf._&tbl._&ri.&di, &ri);
		%if &find_window %then
			%find_days_in_window(&userlib..&proj_cn._&out_tbl_pf._&tbl._&ri.&di,
				&ri, &minimum_days, &maximum_window);
	%end;

	%if &make_strings %then %do;
		data &userlib..&proj_cn._&out_tbl_pf._&tbl.&di;
			merge
				%do IL=1 %to %sysfunc(countw(&intervals));
					%let ri = %sysfunc(scan(&intervals, &IL));
					&userlib..&proj_cn._&out_tbl_pf._&tbl._&ri.&di
				%end;;
		run;

		%if &drop_tables %then %do;
			proc sql;
			%do IL=1 %to %sysfunc(countw(&intervals));
				%let ri = %sysfunc(scan(&intervals, &IL));
				drop table &userlib..&proj_cn._&out_tbl_pf._&tbl._&ri.&di;
			%end;
			quit;
		%end;
	%end;

	proc sql;
	select "&userlib..&proj_cn._&clms_tbl_pf._&tbl" as Table,
		count(unique(BENE_ID)) as Beneficiaries
	from &userlib..&proj_cn._&clms_tbl_pf._&tbl
	%if &debug_mode %then where BENE_ID < &debug_limit;;

	%if &make_strings %then %do;
		select "&userlib..&proj_cn._&out_tbl_pf._&tbl.&di" as Table,
			count(unique(BENE_ID)) as Beneficiaries
		from &userlib..&proj_cn._&out_tbl_pf._&tbl.&di
		%if &debug_mode %then where BENE_ID < &debug_limit;;
	%end;
	quit;
%end;
%mend;

%macro make_tables;
%if &debug_mode
	%then %let di = u;
	%else %let di =;

%if &do_claims_tables %then %wrapper(&clms_table_prefix, &clms_str_prefix, 1, 1);
%if &do_overlap_tables %then %wrapper(&overlap_table_prefix, &overlap_str_prefix, 1, 0);
%mend;

%make_tables;

GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

