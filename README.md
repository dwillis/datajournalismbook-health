# Data Journalism with R and the Tidyverse

Course site for data journalism at the University of Maryland, built with [Quarto](https://quarto.org).

## How publishing works

- The site is a Quarto **website**. Only the pages listed under `project: render:` in `_quarto.yml` are built. When you add or remove a chapter, update that list *and* the `website: sidebar:` list.
- `execute: freeze: auto` means R code runs only when you render locally and only for pages whose source changed. The results are stored in `_freeze/`, which **must be committed**.
- Pushing to `main` runs `.github/workflows/publish.yml`, which renders from `_freeze/` (no R needed) and deploys to GitHub Pages.

## Editing a chapter

1. Edit the `.qmd` file.
2. Render locally, either with the RStudio **Render** button or with `quarto render chapter.qmd` (`quarto preview` for live reload).
3. Commit the `.qmd` **and** the updated files in `_freeze/`.

If you push a changed `.qmd` without its updated `_freeze/`, the CI build will fail, because it can't run R.

## API keys

Chapters that call the Census and Groq APIs read keys from environment variables. Put these in `~/.Renviron`; never write keys into a chapter:

```
CENSUS_API_KEY=...
GROQ_API_KEY=...
```

## Labs

`labs/` and `pre_labs/` hold class assignments. They are not part of the website build.

## Data

Every chapter, pre-lab and lab uses health data. The files in `data/` (and the copies in each pre-lab and lab `data/` folder) are snapshots made by the scripts in `scripts/`:

- `scripts/fetch_data.R` downloads the source datasets: Medicare Part D prescribers and Open Payments (CMS), health agency grants and the State Health Improvement Plan and COVID-19 data (Maryland open data portal), nursing homes (CMS), vaccination data (CDC), food recalls (openFDA) and FDA warning letters. Run `Rscript scripts/fetch_data.R` for everything, or name sources: `Rscript scripts/fetch_data.R partd ship`.
- Open Payments is large and its API is rate-limited. The faster route is to stream CMS's national file through a Maryland filter first, then run the fetch script, which uses the filtered file:
  `curl -s <bulk CSV URL> | python3 -I scripts/filter_open_payments.py data-raw/open_payments_md_2025.csv`
- `scripts/extract_kindergarten.R` turns the MDH kindergarten immunization PDFs in `pdfs/kindergarten/` (recovered from the Wayback Machine) into CSVs.
- `scripts/build_state_vax.R` and `scripts/build_viz_data.R` build the smaller derived files used for statistics, Datawrapper and mapping.

Refreshing the data changes the answers to lab questions, so re-check the labs after any refresh. Raw downloads are cached in `data-raw/`, which is not committed.
