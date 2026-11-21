/*============================================================================
  Parental Awareness and Adolescents' Future Health Insurance
  MPH Capstone (Epidemiology & Biostatistics), CUNY SPH, December 2024
  Author: Akib Rahman

  Data:   2022 National Survey of Children's Health (NSCH), topical file
          (nsch_2022e_topical.sas7bdat), free from the U.S. Census Bureau:
          https://www.census.gov/programs-surveys/nsch/data/datasets.html

  Software: SAS 9.4 (also runs in SAS OnDemand for Academics)

  Note: The original program was lost with my university virtual-desktop
  account. I rebuilt this script in 2026 from the paper's Methods section and
  checked it against the paper; it reproduces Table 1, Table 2, Table 3 and
  Figures 1-4.
============================================================================*/

/* ---- 1. Setup ----------------------------------------------------------- */
libname nsch "/path/to/your/nsch_2022_topical_SAS";   /* <-- edit this */

/* Reference-cell coding: each p-value tests the same comparison as its odds
   ratio (level vs. reference group). SAS's default, PARAM=EFFECT, would test
   each level against the average of all levels instead.                    */
%let param = ref;

/* ---- 2. Data cleaning ---------------------------------------------------- */

/* 2a. Sample flow: all children -> HEALTHKNOW asked -> complete exposure.
       Expected: 54,103 -> 18,762 -> 18,423 (339 missing insurance type).    */
proc sql;
    select count(*)                                              as all_children,
           sum(not missing(HEALTHKNOW))                          as asked_healthknow,
           sum(not missing(HEALTHKNOW) and not missing(INSTYPE)) as analytic_n
    from nsch.nsch_2022e_topical;
quit;

/* 2b. Raw values among adolescents asked the outcome question.
       NSCH stores non-response as special missing values (.M = no valid
       response, .L = logical skip, .N = not in universe, .D = suppressed);
       the MISSING option lists them so nothing is dropped silently.         */
proc freq data=nsch.nsch_2022e_topical;
    where not missing(HEALTHKNOW);
    tables HEALTHKNOW INSTYPE SC_CSHCN SC_RACE_R SC_HISPANIC_R / missing;
run;

proc means data=nsch.nsch_2022e_topical n nmiss min max;
    where not missing(HEALTHKNOW);
    var SC_AGE_YEARS FPL_I1;   /* expect ages 12-17; FPL_I1 is imputed, 50-400 */
run;

/* 2c. Build the analytic dataset ------------------------------------------ */
data analysis;
    set nsch.nsch_2022e_topical;

    /* HEALTHKNOW is asked only of parents of 12-17 year olds */
    where not missing(HEALTHKNOW) and not missing(INSTYPE);

    length ins_cat $9 age_cat $9 shcn_cat $8 race_cat $18 fpl_cat $8;

    /* Outcome: parent knows how child will be insured as an adult */
    aware = (HEALTHKNOW = 1);

    /* Exposure: insurance type (public only + public & private = any public) */
    if      INSTYPE in (1, 3) then ins_cat = 'Public';
    else if INSTYPE = 2       then ins_cat = 'Private';
    else if INSTYPE = 5       then ins_cat = 'Uninsured';

    /* Adolescent age group */
    if      SC_AGE_YEARS <= 13 then age_cat = '12-13 yrs';
    else if SC_AGE_YEARS <= 15 then age_cat = '14-15 yrs';
    else                            age_cat = '16-17 yrs';

    /* Special health care needs */
    if      SC_CSHCN = 1 then shcn_cat = 'SHCN';
    else if SC_CSHCN = 2 then shcn_cat = 'Non-SHCN';

    /* Race/ethnicity */
    if      SC_HISPANIC_R = 1 then race_cat = 'Hispanic';
    else if SC_RACE_R = 1     then race_cat = 'White non-Hispanic';
    else if SC_RACE_R = 2     then race_cat = 'Black non-Hispanic';
    else                           race_cat = 'Other non-Hispanic';

    /* Household Federal Poverty Level (imputed) */
    if      FPL_I1 < 100 then fpl_cat = '0-99%';
    else if FPL_I1 < 200 then fpl_cat = '100-199%';
    else if FPL_I1 < 400 then fpl_cat = '200-399%';
    else                      fpl_cat = '400%+';

    label aware    = 'Knows how child will be insured as adult'
          ins_cat  = 'Insurance Type'
          age_cat  = 'Age'
          shcn_cat = 'SHCN'
          race_cat = 'Race/Ethnicity'
          fpl_cat  = 'FPL';
run;   /* n = 18,423 */

/* 2d. Check every recode against its source variable */
proc freq data=analysis;
    tables HEALTHKNOW*aware
           INSTYPE*ins_cat
           SC_AGE_YEARS*age_cat
           SC_CSHCN*shcn_cat
           SC_HISPANIC_R*SC_RACE_R*race_cat / list missing;
run;

proc means data=analysis n min max;
    class fpl_cat;
    var FPL_I1;                /* each category's range should sit inside its cut-points */
run;

/* Survey design statements used by every procedure below */
%macro design;
    strata  FIPSST STRATUM;
    cluster HHID;
    weight  FWC;
%mend design;

/* ---- 3. Table 1: weighted descriptives + Rao-Scott chi-square ----------- */
proc surveyfreq data=analysis;
    %design
    tables aware ins_cat age_cat shcn_cat race_cat fpl_cat;      /* Total column */
    tables (ins_cat age_cat shcn_cat race_cat fpl_cat) * aware
           / row chisq;                                           /* Aware / Not aware */
run;

/* ---- 4. Table 2: logistic regression ------------------------------------ */
%let refs = ins_cat(ref='Private') age_cat(ref='12-13 yrs') shcn_cat(ref='Non-SHCN')
            race_cat(ref='White non-Hispanic') fpl_cat(ref='400%+');

/* Crude: insurance type alone */
proc surveylogistic data=analysis;
    %design
    class ins_cat(ref='Private') / param=&param;
    model aware(event='1') = ins_cat;
run;

/* Crude: each covariate alone */
%macro crude(var, ref);
    proc surveylogistic data=analysis;
        %design
        class &var(ref="&ref") / param=&param;
        model aware(event='1') = &var;
    run;
%mend crude;

%crude(age_cat,  12-13 yrs)
%crude(shcn_cat, Non-SHCN)
%crude(race_cat, White non-Hispanic)
%crude(fpl_cat,  400%+)

/* Adjusted model */
proc surveylogistic data=analysis;
    %design
    class &refs / param=&param;
    model aware(event='1') = ins_cat age_cat shcn_cat race_cat fpl_cat;
run;

/* ---- 5. Table 3 + Figures 1-4: interaction models ------------------------
   Term-level p-values come from the parameter estimates; the overall test for
   each interaction is the ins_cat*covariate row of "Type 3 Analysis of Effects". */
%macro interact(var, ref, title, outname);
    proc surveylogistic data=analysis;
        %design
        class ins_cat(ref='Private') &var(ref="&ref") / param=&param;
        model aware(event='1') = ins_cat &var ins_cat*&var;
        output out=pred_&outname p=phat;
    run;

    /* Mean predicted probability for each insurance type x subgroup */
    proc means data=pred_&outname noprint nway;
        class ins_cat &var;
        var phat;
        output out=mean_&outname mean=phat;
    run;

    proc sgplot data=mean_&outname;
        title "Probability of Parental Awareness by Type of Insurance and &title";
        series x=ins_cat y=phat / group=&var markers datalabel=phat;
        format phat 6.4;
        xaxis label='Insurance Type';
        yaxis label='Predicted Probability of Health Knowledge';
    run;
    title;
%mend interact;

%interact(fpl_cat,  400%+,              FPL,  fpl)    /* Figure 1 */
%interact(age_cat,  12-13 yrs,          Age,  age)    /* Figure 2 */
%interact(race_cat, White non-Hispanic, Race, race)   /* Figure 3 */
%interact(shcn_cat, Non-SHCN,           SHCN, shcn)   /* Figure 4 */
