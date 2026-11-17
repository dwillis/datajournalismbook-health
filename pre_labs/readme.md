# Pre-labs

Each pre-lab walks through a chapter of the textbook with tasks to run and questions to answer, and prepares you for the lab with the matching skills. Every dataset is about health.

| Pre-lab | Skills | Data | Matching lab |
|---|---|---|---|
| 01 | R basics, `group_by`, `summarise`, `arrange` | Medicare Part D prescribers in Maryland, 2022-2024 (CMS) | lab_01 |
| 02 | `filter`, `select`, lubridate, `mutate`, `case_when` | Part D prescribers; industry payments to Maryland doctors (CMS Open Payments) | lab_02 |
| 03 | Data cleaning: `guess_max`, janitor, `get_dupes`, ZIP codes | Open Payments raw file; Maryland state health grants | lab_03 |
| 04 | refinr and OpenRefine clustering | Maryland state health grants | lab_04 |
| 05 | Tabula and PDFs, `rename`, `col_names`, string cleanup | MDH drug intoxication deaths report; MDH kindergarten immunization survey | lab_05 |
| 06 | `bind_rows`, joins | MDH kindergarten immunization surveys, five school years; county population and demographics | lab_06 |
| 07 | tidycensus, margins of error | Census ACS; CMS nursing homes | lab_07 |
| 08 | ggplot bar and line charts | Baltimore County 911 overdose calls | lab_08 |
| 09 | Datawrapper charts and maps | CMS nursing homes by owner; opioid overdose death rates by county (MDH SHIP) | lab_09 |
| 10 | sf, tigris, choropleth maps | Maryland COVID-19 cases by ZIP code and county (MDH) | lab_10 |
| 11 | tidytext | Maryland Board of Physicians disciplinary alerts | lab_12 |
| 12 | rvest scraping | Maryland Board of Physicians and FDA press announcement web pages | lab_11 |
| 13 | Correlation and t-tests | Kindergarten MMR coverage and exemptions by state (CDC), uninsured rates (ACS) | — |
| 14 | LLMs for extraction, debugging and brainstorming | FDA food recalls; MDH measles exposure notice | — |

Note that pre_lab_11 (text analysis) goes with lab_12 and pre_lab_12 (scraping) goes with lab_11.

The data files are snapshots made by the scripts in `scripts/` at the root of the repository; see the main README.
