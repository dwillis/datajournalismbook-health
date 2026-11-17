# fetch_data.R
#
# Downloads every health dataset used in the textbook chapters, pre-labs and labs,
# trims it to Maryland and the columns the lessons need, and writes a snapshot to data/.
#
# Run from the project root:
#   Rscript scripts/fetch_data.R            # everything
#   Rscript scripts/fetch_data.R partd ship # only some sources
#
# Snapshots are committed, so students never need to run this. Re-run it to refresh the data,
# then re-check every lab question, because the answers will change.

suppressPackageStartupMessages({
  library(tidyverse)
  library(httr2)
  library(jsonlite)
  library(janitor)
})

dir.create("data", showWarnings = FALSE)
UA <- "datajournalismbook-health course data fetcher"

# ---- helpers --------------------------------------------------------------

get_json <- function(url, query = list()) {
  request(url) |>
    req_user_agent(UA) |>
    req_url_query(!!!query) |>
    req_retry(max_tries = 5) |>
    req_perform() |>
    resp_body_json(simplifyVector = TRUE)
}

# Socrata (opendata.maryland.gov, data.cdc.gov): full CSV export of a dataset
socrata_csv <- function(domain, id, where = NULL) {
  url <- if (is.null(where)) {
    glue::glue("https://{domain}/api/views/{id}/rows.csv?accessType=DOWNLOAD")
  } else {
    glue::glue("https://{domain}/resource/{id}.csv?$where={URLencode(where, reserved = TRUE)}&$limit=500000")
  }
  read_csv(url, col_types = cols(.default = col_character()), show_col_types = FALSE)
}

report <- function(df, path) {
  message(sprintf("  wrote %s: %s rows x %s cols (%.1f MB)", path, format(nrow(df), big.mark = ","),
                  ncol(df), file.size(path) / 1e6))
}

# ---- 1. Medicare Part D prescribers (replaces UMD courses) ---------------

fetch_partd <- function() {
  message("Medicare Part D prescribers, Maryland")
  ids <- c(`2022` = "adcdaca6-0c9c-485f-af21-1abc16104d6c",
           `2023` = "42888afe-3b85-4a61-a4ee-091f00bd62bc",
           `2024` = "14d8e8a9-7e9b-4370-a044-bf97c46b4b44")
  pull_year <- function(id) {
    base <- glue::glue("https://data.cms.gov/data-api/v1/dataset/{id}/data")
    out <- list(); offset <- 0
    repeat {
      page <- get_json(base, list(`filter[Prscrbr_State_Abrvtn]` = "MD", size = 5000, offset = offset))
      if (length(page) == 0 || nrow(page) == 0) break
      out[[length(out) + 1]] <- page
      offset <- offset + 5000
    }
    bind_rows(out)
  }
  partd <- imap(ids, \(id, yr) pull_year(id) |> mutate(year = as.integer(yr))) |> list_rbind()

  partd <- partd |>
    transmute(
      npi = Prscrbr_NPI,
      year,
      last_name = Prscrbr_Last_Org_Name,
      first_name = na_if(Prscrbr_First_Name, ""),
      credentials = na_if(Prscrbr_Crdntls, ""),
      city = Prscrbr_City,
      zip = Prscrbr_Zip5,
      specialty = Prscrbr_Type,
      total_claims = as.numeric(Tot_Clms),
      total_drug_cost = as.numeric(Tot_Drug_Cst),
      total_beneficiaries = as.numeric(na_if(Tot_Benes, "")),
      opioid_claims = as.numeric(na_if(Opioid_Tot_Clms, "")),
      opioid_rate = as.numeric(na_if(Opioid_Prscrbr_Rate, "")),
      antibiotic_claims = as.numeric(na_if(Antbtc_Tot_Clms, "")),
      avg_patient_age = as.numeric(na_if(Bene_Avg_Age, ""))
    ) |>
    arrange(year, last_name, first_name)

  write_rds(partd, "data/md_partd_prescribers.rds")
  report(partd, "data/md_partd_prescribers.rds")
}

# ---- 2. CMS Open Payments (replaces campaign expenses + state payments) ---

fetch_open_payments <- function(year = 2025, dataset = "fb0b1734-1410-429d-92f6-3f4b35218e5e") {
  message("Open Payments general payments, Maryland recipients, PY", year)
  # The API returns 500 rows per request, so a full year takes ~15 minutes. Cache the raw pull
  # in data-raw/ (not committed) so reshaping can be re-run without downloading again.
  dir.create("data-raw", showWarnings = FALSE)
  cache <- glue::glue("data-raw/open_payments_md_{year}.rds")
  bulk <- glue::glue("data-raw/open_payments_md_{year}.csv")
  if (file.exists(cache)) {
    op <- read_rds(cache)
  } else if (file.exists(bulk)) {
    # Faster route: CMS's national bulk CSV, streamed through scripts/filter_open_payments.py.
    # Its headers are the API's names in Title_Case; one long name is truncated differently.
    op <- read_csv(bulk, col_types = cols(.default = col_character())) |>
      rename_with(str_to_lower) |>
      rename(name_of_third_party_entity_receiving_payment_or_transfer_of_ccfc =
               name_of_third_party_entity_receiving_payment_or_transfer_of_value)
  } else {
  base <- glue::glue("https://openpaymentsdata.cms.gov/api/1/datastore/query/{dataset}/0")
  n <- get_json(base, list(`conditions[0][property]` = "recipient_state",
                           `conditions[0][value]` = "MD", limit = 1, count = "true", results = "false"))$count
  offsets <- seq(0, n - 1, by = 500)
  # download in batches, saving each one, so an interrupted run resumes where it stopped
  batches <- split(offsets, ceiling(seq_along(offsets) / 50))
  op <- imap(batches, \(offs, b) {
    part <- glue::glue("data-raw/open_payments_md_{year}_part{b}.rds")
    if (file.exists(part)) return(read_rds(part))
    # the API returns 403 when hit too fast, so keep concurrency low and treat 403 as retryable
    reqs <- map(offs, \(o) request(base) |> req_user_agent(UA) |>
                  req_retry(max_tries = 8, is_transient = \(r) resp_status(r) %in% c(403, 429, 500, 503),
                            backoff = \(i) 10 * i) |>
                  req_url_query(`conditions[0][property]` = "recipient_state", `conditions[0][value]` = "MD",
                                `sorts[0][property]` = "record_id", `sorts[0][order]` = "asc",
                                limit = 500, offset = o, count = "false", schema = "false"))
    resps <- req_perform_parallel(reqs, max_active = 2, progress = FALSE)
    df <- map(resps, \(r) resp_body_json(r, simplifyVector = TRUE)$results) |> list_rbind()
    write_rds(df, part)
    message("  batch ", b, " of ", length(batches))
    Sys.sleep(5)
    df
  }) |> list_rbind()
  stopifnot(nrow(op) == n, n_distinct(op$record_id) == n)
  write_rds(op, cache, compress = "gz")
  unlink(Sys.glob(glue::glue("data-raw/open_payments_md_{year}_part*.rds")))
  }

  # Raw-ish file for the data cleaning lessons: Title Case headers with spaces, sparse
  # columns kept so that guess_max matters, original ZIP codes (5 and 9 digit) and city spellings.
  raw_cols <- c(
    "record_id", "change_type", "covered_recipient_type", "teaching_hospital_name",
    "covered_recipient_first_name", "covered_recipient_last_name",
    "recipient_primary_business_street_address_line1", "recipient_city", "recipient_state",
    "recipient_zip_code", "covered_recipient_primary_type_1", "covered_recipient_specialty_1",
    "applicable_manufacturer_or_applicable_gpo_making_payment_name",
    "applicable_manufacturer_or_applicable_gpo_making_payment_state",
    "total_amount_of_payment_usdollars", "date_of_payment", "number_of_payments_included_in_total_amount",
    "form_of_payment_or_transfer_of_value", "nature_of_payment_or_transfer_of_value",
    "city_of_travel", "state_of_travel", "country_of_travel", "physician_ownership_indicator",
    "third_party_payment_recipient_indicator", "name_of_third_party_entity_receiving_payment_or_transfer_of_ccfc",
    "charity_indicator", "contextual_information",
    "indicate_drug_or_biological_or_device_or_medical_supply_1",
    "product_category_or_therapeutic_area_1", "name_of_drug_or_biological_or_device_or_medical_supply_1",
    "program_year"
  )
  # Leave out food and beverage payments (92% of rows, 11% of dollars) to keep the file small.
  raw <- op |>
    filter(nature_of_payment_or_transfer_of_value != "Food and Beverage") |>
    select(all_of(raw_cols)) |>
    mutate(across(everything(), \(x) na_if(x, ""))) |>
    # sort so the first rows all have 5-digit ZIP codes: read_csv() then guesses the ZIP column
    # is a number when guess_max is small, and the 9-digit "21201-1234" ZIPs later in the file
    # become parsing problems. That is the point of the guess_max lesson.
    arrange(str_length(recipient_zip_code) > 5, as.numeric(record_id)) |>
    rename_with(\(x) x |>
      str_replace("applicable_manufacturer_or_applicable_gpo_making_payment", "company") |>
      str_replace("name_of_drug_or_biological_or_device_or_medical_supply", "product_name") |>
      str_replace("indicate_drug_or_biological_or_device_or_medical_supply", "product_type") |>
      str_replace("name_of_third_party_entity_receiving_payment_or_transfer_of_ccfc", "third_party_name") |>
      str_replace("_or_transfer_of_value", "") |>
      str_replace("total_amount_of_payment_usdollars", "amount") |>
      str_replace("number_of_payments_included_in_total_amount", "number_of_payments") |>
      str_replace("recipient_primary_business_street_address_line1", "recipient_address") |>
      str_replace_all("_", " ") |>
      str_to_title())
  write_csv(raw, glue::glue("data/md_open_payments_{year}_raw.csv"), na = "")
  report(raw, glue::glue("data/md_open_payments_{year}_raw.csv"))

  # Tidy file for the aggregates, dates and mutate lessons: lower-snake headers, but
  # dates stay as m/d/yyyy text so students use lubridate::mdy().
  tidy <- op |>
    transmute(
      record_id,
      date_of_payment,
      recipient_type = str_remove(covered_recipient_type, "^Covered Recipient "),
      recipient_name = coalesce(na_if(teaching_hospital_name, ""),
                                str_squish(paste(covered_recipient_first_name, covered_recipient_last_name))),
      recipient_city,
      recipient_zip = str_sub(recipient_zip_code, 1, 5),
      specialty = na_if(covered_recipient_primary_type_1, ""),
      company = applicable_manufacturer_or_applicable_gpo_making_payment_name,
      company_state = na_if(applicable_manufacturer_or_applicable_gpo_making_payment_state, ""),
      company_country = applicable_manufacturer_or_applicable_gpo_making_payment_country,
      amount = as.numeric(total_amount_of_payment_usdollars),
      nature_of_payment = nature_of_payment_or_transfer_of_value,
      form_of_payment = form_of_payment_or_transfer_of_value,
      product_type = na_if(indicate_drug_or_biological_or_device_or_medical_supply_1, ""),
      product_name = na_if(name_of_drug_or_biological_or_device_or_medical_supply_1, "")
    )
  # every payment, compressed: read_csv() reads .csv.gz files directly
  write_csv(tidy, glue::glue("data/md_open_payments_{year}.csv.gz"), na = "")
  report(tidy, glue::glue("data/md_open_payments_{year}.csv.gz"))
}

# ---- 3. State health grants (replaces the full state grants and loans file) ---
# The health-related slice of Maryland's grant and loan data: grants from the health
# department (and its predecessor, the Department of Health and Mental Hygiene), the Community
# Health Resources Commission, the Department of Aging and the Stem Cell Research Fund.
# The file is left exactly as published -- inconsistent capitalization, 5- and 9-digit ZIP codes
# and all -- because the data cleaning lessons depend on that mess.

fetch_health_grants <- function() {
  message("Maryland state grants from health agencies, FY2009 onward")
  grants <- socrata_csv("opendata.maryland.gov", "absk-avps") |>
    filter(str_detect(Grantor, "(?i)health|hygiene|aging|behavioral|stem cell") |
             str_detect(Description, "(?i)stem cell"))
  write_csv(grants, "data/md_health_grants.csv", na = "")
  report(grants, "data/md_health_grants.csv")
}

# ---- 4. Maryland open data portal (SHIP, COVID) ---------------------------

fetch_ship <- function() {
  message("State Health Improvement Plan metrics")
  ship <- socrata_csv("opendata.maryland.gov", "59sg-2ni4")
  write_csv(ship, "data/md_ship_metrics.csv", na = "")
  report(ship, "data/md_ship_metrics.csv")
}

fetch_covid <- function() {
  message("Maryland COVID-19: cases by county and ZIP (wide), hospitalizations")
  by_county <- socrata_csv("opendata.maryland.gov", "tm86-dujs")
  write_csv(by_county, "data/md_covid_cases_by_county.csv", na = "")
  report(by_county, "data/md_covid_cases_by_county.csv")

  by_zip <- socrata_csv("opendata.maryland.gov", "ntd2-dqpx")
  write_csv(by_zip, "data/md_covid_cases_by_zip.csv", na = "")
  report(by_zip, "data/md_covid_cases_by_zip.csv")

  hosp <- socrata_csv("opendata.maryland.gov", "hd2f-3amb")
  write_csv(hosp, "data/md_covid_hospitalizations.csv", na = "")
  report(hosp, "data/md_covid_hospitalizations.csv")
}

# ---- 5. CMS nursing homes -------------------------------------------------

fetch_nursing_homes <- function() {
  message("CMS nursing home provider information, Maryland")
  base <- "https://data.cms.gov/provider-data/api/1/datastore/query/4pq5-n9py/0"
  out <- list(); offset <- 0
  repeat {
    page <- get_json(base, list(`conditions[0][property]` = "state", `conditions[0][value]` = "MD",
                                limit = 500, offset = offset))$results
    if (length(page) == 0 || nrow(page) == 0) break
    out[[length(out) + 1]] <- page
    offset <- offset + 500
  }
  nh <- bind_rows(out) |>
    transmute(
      ccn = cms_certification_number_ccn,
      provider_name, provider_address, city = citytown, zip = zip_code, county = countyparish,
      ownership_type,
      certified_beds = as.numeric(number_of_certified_beds),
      avg_residents_per_day = as.numeric(average_number_of_residents_per_day),
      chain_name = na_if(chain_name, ""),
      overall_rating = as.numeric(na_if(overall_rating, "")),
      health_inspection_rating = as.numeric(na_if(health_inspection_rating, "")),
      staffing_rating = as.numeric(na_if(staffing_rating, "")),
      total_fines = as.numeric(na_if(total_amount_of_fines_in_dollars, "")),
      number_of_fines = as.numeric(na_if(number_of_fines, "")),
      special_focus_status = na_if(special_focus_status, ""),
      abuse_icon
    )
  write_csv(nh, "data/md_nursing_homes.csv", na = "")
  report(nh, "data/md_nursing_homes.csv")
}

# ---- 6. CDC vaccination data ----------------------------------------------

fetch_cdc_vax <- function() {
  message("CDC: county COVID vaccination (MD), flu vaccination (MD), kindergarten coverage (states)")
  county <- socrata_csv("data.cdc.gov", "8xkx-amqh", "recip_state='MD' AND date_extract_d(date)=1") |>
    select(date, fips, recip_county, series_complete_pop_pct, administered_dose1_pop_pct,
           series_complete_yes, series_complete_65pluspop_pct, completeness_pct) |>
    mutate(date = as.Date(str_sub(date, 1, 10))) |>
    arrange(date, fips)
  write_csv(county, "data/cdc_md_county_covid_vax.csv", na = "")
  report(county, "data/cdc_md_county_covid_vax.csv")

  flu <- socrata_csv("data.cdc.gov", "vh55-3he6", "geography='Maryland'")
  write_csv(flu, "data/cdc_md_flu_vax.csv", na = "")
  report(flu, "data/cdc_md_flu_vax.csv")

  kinder <- socrata_csv("data.cdc.gov", "ijqb-a7ye")
  write_csv(kinder, "data/cdc_kindergarten_vax_states.csv", na = "")
  report(kinder, "data/cdc_kindergarten_vax_states.csv")
}

# ---- 7. openFDA food recalls ----------------------------------------------

fetch_fda_recalls <- function() {
  message("openFDA food enforcement reports distributed in Maryland")
  base <- "https://api.fda.gov/food/enforcement.json"
  q <- 'distribution_pattern:"Maryland" AND report_date:[20230101 TO 20261231]'
  first <- get_json(base, list(search = q, limit = 1))
  n <- first$meta$results$total
  out <- map(seq(0, min(n, 25000) - 1, by = 1000),
             \(s) get_json(base, list(search = q, limit = 1000, skip = s))$results)
  recalls <- bind_rows(out) |>
    select(recall_number, report_date, recall_initiation_date, recalling_firm, city, state,
           classification, status, product_description, reason_for_recall, product_quantity,
           distribution_pattern, voluntary_mandated) |>
    mutate(across(c(report_date, recall_initiation_date), ymd))
  write_csv(recalls, "data/fda_food_recalls_md.csv", na = "")
  report(recalls, "data/fda_food_recalls_md.csv")
}

# ---- 8. FDA warning letters (replaces attorney sanctions in lab_12) -------

fetch_fda_warning_letters <- function(start_year = 2021, per_year = 150) {
  message("FDA warning letters issued ", start_year, " onward (text scraped from fda.gov)")
  listing_url <- "https://www.fda.gov/datatables/views/ajax"
  page <- function(start) {
    get_json(listing_url, list(field_letter_issue_datetime = "All", field_change_date_2 = "All",
                               draw = 1, start = start, length = 500,
                               view_display_id = "warning_letter_solr_block",
                               view_name = "warning_letter_solr_index"))$data
  }
  set.seed(20261117)
  rows <- map(seq(0, 3500, by = 500), page) |> discard(\(x) length(x) == 0) |> map(as_tibble) |> list_rbind()
  strip <- \(x) str_squish(rvest::html_text2(rvest::read_html(paste0("<p>", x, "</p>"))))
  letters <- rows |>
    transmute(
      issue_date = mdy(map_chr(V2, strip)),
      firm = map_chr(V3, strip),
      url = paste0("https://www.fda.gov", str_match(V3, 'href="([^"]+)"')[, 2]),
      issuing_office = V4,
      subject = V5
    ) |>
    filter(year(issue_date) >= start_year) |>
    # a random sample of letters from each year keeps the file small but lets students compare years
    group_by(year = year(issue_date)) |>
    slice_sample(n = per_year) |>
    ungroup() |>
    select(-year) |>
    arrange(desc(issue_date))
  set.seed(NULL)

  get_text <- function(u) {
    Sys.sleep(1)
    txt <- tryCatch(
      request(u) |> req_user_agent(UA) |>
        req_retry(max_tries = 5, is_transient = \(r) resp_status(r) %in% c(403, 429, 500, 503),
                  backoff = \(i) 15 * i) |>
        req_perform() |>
        resp_body_html() |> rvest::html_element("article") |> rvest::html_text2(),
      error = \(e) NA_character_)
    # keep the body of the letter: from the salutation to the signature
    str_extract(txt, "(?s)Dear .*?(?=\\n\\s*Sincerely|$)") |> str_squish()
  }
  letters$text <- map_chr(letters$url, get_text, .progress = TRUE)
  letters <- letters |> mutate(year = year(issue_date), .before = 1) |> filter(!is.na(text))
  write_csv(letters, "data/fda_warning_letters.csv", na = "")
  report(letters, "data/fda_warning_letters.csv")
}

# ---- run ------------------------------------------------------------------

sources <- list(
  partd = fetch_partd,
  open_payments = fetch_open_payments,
  health_grants = fetch_health_grants,
  ship = fetch_ship,
  covid = fetch_covid,
  nursing_homes = fetch_nursing_homes,
  cdc_vax = fetch_cdc_vax,
  fda_recalls = fetch_fda_recalls,
  fda_warning_letters = fetch_fda_warning_letters
)

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  todo <- if (length(args)) args else names(sources)
  for (s in todo) sources[[s]]()
}
