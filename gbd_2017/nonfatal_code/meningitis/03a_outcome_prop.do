// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Author:		
// Last updated:	12/18/2015
// Description:	Setup draws for each outcome fraction for each etiology	
// To do: Adjust master code settings and file paths
// Number of output files: 16	
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

	// base directory on J
	local root_j_dir `1'
	// base directory on clustertmp
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2014_01_17)
	local date `3'
	// step number of this step (i.e. 01a)
	local step_num `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
	// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
	local hold_steps `6'
	// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
	local last_steps `7'
	// directory where the code lives
	local code_dir `8'
	// directory for external inputs
	local in_dir `9'
	// directory for output on the J drive
	local out_dir "`root_j_dir'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/`step_num'_`step_name'"
	// functional
	local functional "meningitis"
	//  etiologies
	local etiologies "meningitis_pneumo meningitis_hib meningitis_meningo meningitis_other"

	// grouping
	local grouping "long_mild _vision _hearing long_modsev epilepsy"
	// outcomes
	local outcomes "minor major_mort0 major_mort1 seizure"

	// directory for standard code files
	adopath + "FILEPATH"

	// get demographics and locations
	get_location_metadata, location_set_id(9) clear
	keep if most_detailed == 1 & is_estimate == 1
	levelsof location_id, local(locations)
	clear
	
	//test locations
	//local locations 34 527

	// get demographics
	get_demographics, gbd_team(epi) clear
	local years = r(year_id)
	local sexes = r(sex_id)
	
	//local meids
	local meningitis_pneumo_meid 1298
	local meningitis_hib_meid 1328
	local meningitis_meningo_meid 1358
	local meningitis_other_meid 1388
	
	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'.smcl", replace
	if !_rc local close_log 1
	else local close_log 0
	
	// check for finished.txt produced by previous step
	cap erase "`out_dir'/finished.txt"
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "`root_j_dir'" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "`root_j_dir'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}		

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// WRITE CODE HERE
** Calculating proportions of >1 major for each etiology  (from Theo's file)
	import excel "FILEPATH" clear // importing Edmond proportions for sequelae with estimated means
	drop B-F I-L Q-R W-X 
	drop in 1/3 // Cleaning table
	rename A sequelae
	rename G meningitis_all_median
	rename H meningitis_all_mean
	rename M meningitis_hib_median
	rename N meningitis_hib_mean
	rename S meningitis_pneumo_median
	rename T meningitis_pneumo_mean
	rename Y meningitis_meningo_median
	rename Z meningitis_meningo_mean
	rename O meningitis_hib_sd
	rename U meningitis_pneumo_sd
	rename AA meningitis_meningo_sd
	rename P meningitis_hib_se
	rename V meningitis_pneumo_se
	rename AB meningitis_meningo_se

	gen exclude = regexm(sequelae,"Minor") // generates new variable that is 1 if column sequelae has "Minor"
	drop if exclude == 1 // Drop rows with "minor"
	drop if sequelae == "" // Drop if sequelae is empty
	drop exclude
	destring *median *se *sd *mean, replace	

// generate meningitis_other variables
	gen meningitis_other_median = (meningitis_hib_median + meningitis_meningo_median) / 2
	gen meningitis_other_mean = (meningitis_hib_mean + meningitis_meningo_mean) / 2
	gen meningitis_other_se = (meningitis_hib_se + meningitis_meningo_se) / 2 
	gen meningitis_other_sd = (meningitis_hib_sd + meningitis_meningo_sd) / 2

// create normalized proportions: risk of outcome / all outcomes (not including clinical or minor impairments)
	foreach etiology of local etiologies {
		gen `etiology'_major_temp = `etiology'_mean if sequelae == "At least one major sequela" 
		gen `etiology'_clinical_temp = `etiology'_mean if sequelae == "Major clinical impairments"
		egen `etiology'_major = sum(`etiology'_major_temp) // Have to sum here because they're in different rows
		egen `etiology'_clinical = sum(`etiology'_clinical_temp) // Same thing here
		replace `etiology'_major = `etiology'_major - `etiology'_clinical 
		replace `etiology'_mean = `etiology'_mean / `etiology'_major if (sequelae != "At least one major sequela" & sequelae != "At least one minor sequela")
		drop `etiology'_major `etiology'_major_temp `etiology'_clinical `etiology'_clinical_temp
	}

// rename outcomes
	drop if sequelae == "IQR" | sequelae == "Major clinical impairments"
	replace sequelae = "minor" if sequelae == "At least one minor sequela"
	replace sequelae = "major_mort0" if sequelae == "Major visual disturbance"
	replace sequelae = "major_mort_" if sequelae == "Major hearing loss"	
	replace sequelae = "major_mort1" if sequelae == "Major cognitive difficulties" | sequelae == "Major motor deficit" | sequelae == "Major multiple impairments"
	replace sequelae = "seizure" if sequelae == "Major seizure disorder"
	replace sequelae = "major" if sequelae == "At least one major sequela"
	local severity = "minor major"
	rename sequelae outcome
	
** proportions for major_mort0, major_mort1, major_mort_, and seizure
// major_mort0 = major visual disturbance, major_mort1 = major cognitive difficulties, major motor deficit, or major multiple impairments, seizure is self explanatory
	preserve
	drop in 1 // drops multiple major impairments row
	levelsof outcome, local(variab)
	drop in 7 // drops minor impairments
	drop *se *sd *median 
	collapse (sum) meningitis_hib_mean meningitis_pneumo_mean meningitis_meningo_mean meningitis_other_mean, by(outcome) // Summed across outcomes
	// file of risk of outcomes given an outcome (so a ratio) of the listed outcomes above, for each etiology
	tempfile major_prop
	save `major_prop', replace
	restore
	
** creating draws for major_all and minor_all
	drop in 2/7 // leaves just major and minor medians (still likelihood of a major or minor sequela given an individual is sick with a specific etiology)
	preserve
	foreach etiology of local etiologies {
		foreach sev of local severity {
			keep outcome `etiology'_mean `etiology'_se // pretty sure this should be standard deviation, not standard error...
			keep if outcome == "`sev'" // For "At least one minor sequela" or "At least one major sequela"
			levelsof `etiology'_mean, local(mean)
			levelsof `etiology'_se, local(se)
			local m = `mean'
			local s = `se'
			local alpha1 = (`m'*(`m'-`m'^2-`s'^2))/`s'^2 // setting beta distribution shape parameters (method of moments, for a non-traditional proportional distribution)
			// constrained to give a proportion, can be over or under dispersed relative to other distributions defined by alpha1 and alpha2
			local alpha2 = (`alpha1'*(1-`m'))/`m' // 
			set obs 1000 // number of draws
			gen `etiology'_major = rbeta(`alpha1',`alpha2')
			keep `etiology'_major
			xpose, clear
			forvalues i = 1/1000 {
				local j = `i' - 1
				qui rename v`i' v_`j'
			}
			gen modelable_entity_id = ``etiology'_meid'
			order modelable_entity_id v_*
			save "FILEPATH", replace 
			clear
			restore, preserve
		}
	}
	
** Calculate ratio draws of minor against major 
	foreach etiology of local etiologies {
		use "FILEPATH", clear
		rename v_* w_*
		merge 1:1 modelable_entity_id using "FILEPATH", nogen
		forvalues i = 0/999 {
			if w_`i' / v_`i' > 1 qui replace w_`i' = 1 // replace minor with 1 if greater than major
			else qui replace w_`i' = w_`i' / v_`i' // replace minor with minor/major if less than major, normalizing proportion of minor to major?
			qui drop v_`i' // drop major
		}
		rename w_* v_*
		save "FILEPATH", replace // ratio of minor/major proportion (never is greater than 1)
		clear
	}
	
** Calculate ratios between each etiology and all cause that will be applied to the country major envelop later (point estimates only, uncertainty explodes)
** Calculates the ratio of a specific etiology / all meningitis. The inverse is the likelihood of the etiology not happening (used later) 
	restore
	drop in 2 // drops minor proportions
	foreach etiology of local etiologies {
		if meningitis_all_mean < `etiology'_mean { // 
			local ratio_`etiology' = (1 - `etiology'_mean) / (1 - meningitis_all_mean)
			local inverse_`etiology' = 1
		}
		else {
			local ratio_`etiology' = `etiology'_mean / meningitis_all_mean
			local inverse_`etiology' = 0
		}
	}
	clear

** Open file and format (used to be Ersatz output, now the result of a regression: GDP and proportion of major outcomes))
	import delimited "FILEPATH", clear

** Quadruplicate data for splitting between 4 etiologies
	cap gen modelable_entity_id = .
	order modelable_entity_id, after(location_id)
	foreach etiology of local etiologies {
		count
		gen row = r(N)
		expand 2 if modelable_entity_id == . // Duplicates all empty observations underneath current number (duplicates original data set)
		gen seqnum = _n // _n is number of current observations
		replace modelable_entity_id = ``etiology'_meid' if row >= seqnum & modelable_entity_id == .
		drop row seqnum
	}	
	drop if modelable_entity_id == .

** Make proportion draws for each etiology/ outcome/ iso3/ year
// This makes etiology and outcome specific files that have proportional draws for every iso3/year
	preserve
	foreach etiology of local etiologies {
		foreach out of local variab { 
			gen outcome = "`out'"
			keep if modelable_entity_id == ``etiology'_meid'
			
			foreach num of numlist 0/999 {
				if `inverse_`etiology'' == 0 { 
					qui replace draw_`num' = draw_`num' * `ratio_`etiology'' 
				}
				else if `inverse_`etiology'' == 1 { // only for pneumo
					qui replace draw_`num' = 1 - ((1 - draw_`num') * `ratio_`etiology'') 
					// ends up calculating 1 - the likelihood of the event not happening
				} 
			}
			if "`out'" == "minor" {
				merge m:1 modelable_entity_id using "FILEPATH", keep(1 3) nogen
				foreach num of numlist 0/999 {
					qui replace draw_`num' = draw_`num' * v_`num'
				}
				drop v_*
			} 			
			else {
				merge m:1 outcome using `major_prop', keep(1 3) nogen
				foreach num of numlist 0/999 {
					qui replace draw_`num' = draw_`num' * `etiology'_mean
				}
				drop *_mean
			} 
			
			rename draw_* v_*
			gen measure_id = 6 // incidence
			rename outcome grouping
				replace grouping = "long_mild" if grouping == "minor"
				replace grouping = "_vision" if grouping == "major_mort0"
				replace grouping = "_hearing" if grouping == "major_mort_"
				replace grouping = "long_modsev" if grouping == "major_mort1"
				replace grouping = "epilepsy" if grouping == "seizure"
				if "`out'" == "minor" {
					local group = "long_mild"
				}
				else if "`out'" == "major_mort0" {
					local group = "_vision"
				}
				else if "`out'" == "major_mort_" {
					local group = "_hearing"
				}
				else if "`out'" == "major_mort1" {
					local group = "long_modsev"
				}
				else if "`out'" == "seizure" {
					local group = "epilepsy"
				}

			order measure_id modelable_entity_id grouping location_id year_id v_*		
			save "FILEPATH", replace
			
			clear
			restore, preserve
		}
	}
	restore, not
	clear
	
	di "03a_outcome_prop sequential runs completed"
	** di "`step_num' sequential runs completed"

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)

	// write check file to indicate step has finished
		file open finished using "`out_dir'/finished.txt", replace write
		file close finished
		
	// if step is last step, write finished.txt file
		local i_last_step 0
		foreach i of local last_steps {
			if "`i'" == "`this_step'" local i_last_step 1
		}
		
		// only write this file if this is one of the last steps
		if `i_last_step' {
		
			// account for the fact that last steps may be parallel and don't want to write file before all steps are done
			local num_last_steps = wordcount("`last_steps'")
			
			// if only one last step
			local write_file 1
			
			// if parallel last steps
			if `num_last_steps' > 1 {
				foreach i of local last_steps {
					local dir: dir "`root_j_dir'" dirs "`i'_*", respectcase
					local dir = subinstr(`"`dir'"',`"""',"",.)
					cap confirm file "`root_j_dir'/finished.txt"
					if _rc local write_file 0
				}
			}
			
			// write file if all steps finished
			if `write_file' {
				file open all_finished using "`root_j_dir'/finished.txt", replace write
				file close all_finished
			}
		}
		
	// close log if open
		if `close_log' log close
	
