# Data Journalism with R and the Tidyverse: Health Edition

Textbook and class assignments for data journalism (JOUR472/JOUR772) at the University of Maryland's Philip Merrill College of Journalism. The textbook is a [Quarto](https://quarto.org) website. Students learn to find, clean, analyze, visualize and write about data in Google Sheets and in R.

Every example, pre-lab and lab uses **health data**: drug company payments to doctors, Medicare prescriptions, overdoses, vaccination rates, COVID-19, nursing homes, insurance coverage, food recalls, and disciplinary actions against physicians. Most of it is about Maryland.

## What's in the repository

| Path | Contents |
|---|---|
| `*.qmd` | Textbook chapters (see the outline below) |
| `_quarto.yml` | Site configuration: which pages are built, sidebar order, theme |
| `pre_labs/` | 14 guided notebooks (`.Rmd`) that walk through the chapters; see [`pre_labs/readme.md`](pre_labs/readme.md) |
| `labs/` | 12 assignments (`.rmd`/`.Rmd`) that test the skills from the pre-labs |
| `data/` | Datasets used by the chapters |
| `pdfs/` | PDFs used in the Tabula lessons, including MDH kindergarten immunization reports for five school years |
| `images/` | Screenshots and figures used by the chapters |
| `scripts/` | Code that downloads and builds every dataset (see [Data](#data)) |
| `_freeze/` | Saved results of the R code in each chapter (committed; see [Publishing](#publishing)) |

Each pre-lab and lab folder has its own `data/` (and sometimes `images/`) folder with copies of the files it needs, so students can work in that folder alone. The pre-lab and lab notebooks are not part of the website build.

## Textbook outline

| Section | Chapters | Main data |
|---|---|---|
| Getting started | Reading data stories, newsroom math, what counts as data | — |
| Spreadsheets | Sheets refresher, sorting and filtering, formulas, pivot tables, practice exercise | Open Payments; MDH overdose deaths by substance |
| Reporting foundations | Ethics (including health data and privacy), public records, GitHub | — |
| R fundamentals | R basics, replication, aggregates, filters, dates, mutate | Medicare Part D prescribers; Open Payments; CMS nursing homes |
| Cleaning and combining data | Data smells, janitor, OpenRefine, PDFs, joins, the Census API | Open Payments; state health grants; MDH kindergarten immunization surveys; ACS |
| Visualization and maps | ggplot, Datawrapper, sf/tigris maps | Baltimore County overdose calls; SHIP opioid death rates; MDH COVID-19 cases |
| Advanced topics | Text analysis, scraping, statistics, AI/LLMs, writing with data | Physician disciplinary alerts; Board of Physicians and FDA web pages; CDC kindergarten vaccination; FDA recalls |

## Pre-labs and labs

Each pre-lab goes with one lab, and the pre-lab teaches the skills that lab tests. The numbering is mostly parallel. The exceptions: pre_lab_11 (text analysis) goes with lab_12, and pre_lab_12 (scraping) goes with lab_11. Pre-labs 13 (statistics) and 14 (AI) have no matching lab. [`pre_labs/readme.md`](pre_labs/readme.md) lists each pre-lab's skills, datasets and matching lab.

Some assignments need outside tools: Tabula (pre-lab and lab 05), OpenRefine (pre-lab and lab 04), a Datawrapper account (pre-lab and lab 09) and Ollama (pre-lab 14).

## Data

The files in `data/` are snapshots, so students never have to download anything. These scripts rebuild them:

| Script | Builds |
|---|---|
| `scripts/fetch_data.R` | Downloads the source data. Run `Rscript scripts/fetch_data.R` for everything, or name sources, such as `Rscript scripts/fetch_data.R partd ship`. Sources: Medicare Part D prescribers and Open Payments (CMS); state health agency grants, State Health Improvement Plan metrics and COVID-19 data (Maryland open data portal); nursing homes (CMS); vaccination data (CDC); food recalls (openFDA); FDA warning letters |
| `scripts/filter_open_payments.py` | Streams CMS's national Open Payments file and keeps Maryland recipients. This is faster than the rate-limited API, and `fetch_data.R` uses its output automatically |
| `scripts/extract_kindergarten.R` | Turns the kindergarten immunization PDFs in `pdfs/kindergarten/` into one CSV per school year |
| `scripts/build_state_vax.R` | Builds the state-by-state vaccination file for the statistics chapter (needs a Census API key) |
| `scripts/build_viz_data.R` | Builds the smaller derived files used for Datawrapper, maps, labs 09 and 10 and the spreadsheet chapters |

To refresh Open Payments, filter the bulk file first, then run the fetch script:

```
curl -s https://download.cms.gov/openpayments/PGYR2025_P06302026_06032026/OP_DTL_GNRL_PGYR2025_P06302026_06032026.csv \
  | python3 -I scripts/filter_open_payments.py data-raw/open_payments_md_2025.csv
Rscript scripts/fetch_data.R open_payments
```

Raw downloads are cached in `data-raw/`, which is not committed. **Refreshing data changes the answers to lab questions**, so re-check the labs and the numbers quoted in the chapters after any refresh. The new files must also be copied into the pre-lab and lab `data/` folders that use them.

Some data is deliberately left messy because the cleaning lessons depend on it:
- The Open Payments raw file mixes 5- and 9-digit ZIP codes and has many spellings of "Baltimore."
- The grants file names the same agencies and recipients many ways.
- One kindergarten CSV has a byte-order mark, and another has a differently named column.

## Publishing

- The site is a Quarto **website**. Only the pages listed under `project: render:` in `_quarto.yml` are built. When you add or remove a chapter, update that list *and* the `website: sidebar:` list.
- `execute: freeze: auto` means R code runs only when you render locally, and only for pages whose source changed. The results are stored in `_freeze/`, which **must be committed**.
- Pushing to `main` runs `.github/workflows/publish.yml`, which renders from `_freeze/` (no R needed) and deploys to GitHub Pages.

## Editing a chapter

1. Edit the `.qmd` file.
2. Render locally, either with the RStudio **Render** button or with `quarto render chapter.qmd` (`quarto preview` for live reload).
3. Commit the `.qmd` **and** the updated files in `_freeze/`.

If you push a changed `.qmd` without its updated `_freeze/`, the CI build will fail, because it can't run R.

## API keys

The chapters and scripts that call the Census and Groq APIs read keys from environment variables. Put these in `~/.Renviron`, and never write keys into a chapter, notebook or zip file:

```
CENSUS_API_KEY=...
GROQ_API_KEY=...
```

The AI chapter and pre-lab 14 use the `openai/gpt-oss-120b` model on Groq. Groq changes its model list from time to time; if a call fails, pick a current model from <https://console.groq.com/docs/models>.

## License and credits

By Derek Willis and Sean Mussenden, based on earlier work by Matt Waite and Sarah Cohen. See `LICENSE` for the license terms.
