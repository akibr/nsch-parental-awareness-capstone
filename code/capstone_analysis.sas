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
  checked it against the published tables; it reproduces Table 1, Table 2,
  Table 3 and Figures 1-4. See the README ("Looking back") for the
  parameterization note on the p-values.
============================================================================*/

/* ---- 1. Setup ----------------------------------------------------------- */
libname nsch "/path/to/your/nsch_2022_topical_SAS";   /* <-- edit this */

/* PARAM = effect reproduces the p-values printed in the paper (SAS default).
   PARAM = ref    gives p-values that test each level against its reference
                  group and agree with the odds-ratio confidence intervals.  */
%let param = effect;

/* ---- 2. Analytic dataset ------------------------------------------------- */
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

/* Crude rows for each covariate: insurance type + that covariate */
%macro crude(var, ref);
    proc surveylogistic data=analysis;
        %design
        class ins_cat(ref='Private') &var(ref="&ref") / param=&param;
        model aware(event='1') = ins_cat &var;
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

/* ---- 5. Table 3 + Figures 1-4: interaction models ------------------------ */
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
