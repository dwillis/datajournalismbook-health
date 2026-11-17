# extract_kindergarten.R
#
# Turns MDH's annual kindergarten immunization survey tables (PDFs in pdfs/kindergarten/,
# archived from health.maryland.gov via the Wayback Machine because MDH removed them) into
# one CSV per school year: data/md_kindergarten_immunization_YYYY.csv
#
# Students do this extraction by hand with Tabula in the PDFs pre-lab; these CSVs are what the
# merging chapter and pre_lab_06 stack with bind_rows. A few quirks are deliberate, so that the
# lesson has something to fix:
#   - the 2018-19 file has a UTF-8 byte order mark, as Excel exports often do
#   - the 2021-22 file spells the total column "Enrolled" instead of "ENROLLED"

suppressPackageStartupMessages(library(tidyverse))

parse_year <- function(pdf) {
  year <- str_extract(pdf, "\\d{4}-\\d{4}")
  lines <- system2("pdftotext", c("-layout", shQuote(pdf), "-"), stdout = TRUE)
  rows <- lines |>
    str_subset("^\\s*[A-Z][A-Za-z.' ]+?\\s{2,}[\\d,]+\\s+[\\d,]+\\s+[\\d.]+") |>
    str_squish()
  tibble(raw = rows) |>
    mutate(
      COUNTY = str_extract(raw, "^[^\\d]+") |> str_trim(),
      nums = str_extract(raw, "[\\d,. ]+$") |> str_squish() |> str_split(" ")
    ) |>
    filter(COUNTY != "State of Maryland", lengths(nums) == 10) |>
    mutate(
      vals = map(nums, \(x) as.numeric(str_remove_all(x, ","))),
      SCHOOL_YEAR = year,
      ENROLLED = map_dbl(vals, 1), SURVEYED = map_dbl(vals, 2), PCT_SURVEYED = map_dbl(vals, 3),
      DTAP = map_dbl(vals, 4), POLIO = map_dbl(vals, 5), MMR = map_dbl(vals, 6),
      HEPB = map_dbl(vals, 7), VARICELLA = map_dbl(vals, 8),
      MEDICAL_EXEMPT = map_dbl(vals, 9), RELIGIOUS_EXEMPT = map_dbl(vals, 10)
    ) |>
    select(SCHOOL_YEAR, COUNTY, ENROLLED:RELIGIOUS_EXEMPT)
}

pdfs <- list.files("pdfs/kindergarten", pattern = "\\.pdf$", full.names = TRUE)
for (pdf in pdfs) {
  df <- parse_year(pdf)
  year <- unique(df$SCHOOL_YEAR)
  if (nrow(df) != 24) warning(pdf, " parsed to ", nrow(df), " rows (expected 24)")
  if (year == "2021-2022") df <- rename(df, Enrolled = ENROLLED)
  out <- glue::glue("data/md_kindergarten_immunization_{str_sub(year, 1, 4)}.csv")
  # write_excel_csv() adds a byte order mark
  if (year == "2018-2019") write_excel_csv(df, out) else write_csv(df, out)
  message(out, ": ", nrow(df), " rows")
}
