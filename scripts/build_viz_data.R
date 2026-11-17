# build_viz_data.R
#
# Small, clean CSVs for the Datawrapper chapter and pre_lab_09, plus the county
# FIPS lookup used to put SHIP county names on maps.

suppressPackageStartupMessages(library(tidyverse))

# County names in SHIP data -> names used elsewhere in the book, with FIPS codes
fips <- read_csv("data/maryland_demographics.csv", show_col_types = FALSE) |>
  transmute(fips_code = as.character(GEOCODE), county = NAME)
ship_names <- c("Baltimore" = "Baltimore County", "Prince Georges" = "Prince George's",
                "Saint Marys" = "St. Mary's", "Queen Annes" = "Queen Anne's")

ship <- read_csv("data/md_ship_metrics.csv", show_col_types = FALSE) |> janitor::clean_names()

# 1. Bar chart: Maryland nursing homes by type of owner
nh <- read_csv("data/md_nursing_homes.csv", show_col_types = FALSE)
owners <- nh |>
  mutate(Owner = case_when(
    str_detect(ownership_type, "^For profit") ~ "For-profit",
    str_detect(ownership_type, "^Non profit") ~ "Nonprofit",
    str_detect(ownership_type, "^Government") ~ "Government"
  )) |>
  group_by(Owner) |>
  summarise(
    `Nursing homes` = n(),
    Beds = sum(certified_beds, na.rm = TRUE),
    `Total fines` = sum(total_fines, na.rm = TRUE),
    `Average rating` = round(mean(overall_rating, na.rm = TRUE), 2)
  ) |>
  arrange(desc(`Nursing homes`))
write_csv(owners, "data/md_nursing_home_owners.csv")
print(owners)

# 2. Choropleth: opioid overdose death rate by county, 2018 and 2023 (SHIP).
# Small counties are suppressed by the state and coded as -999; we leave that in on purpose.
opioid <- ship |>
  filter(metric_name == "Opioid Fatality Rate", geography_type == "County",
         subpopulation_type == "Total", time_period %in% c(2018, 2023)) |>
  mutate(county = recode(geography, !!!ship_names)) |>
  select(county, time_period, value) |>
  pivot_wider(names_from = time_period, values_from = value, names_prefix = "rate_") |>
  left_join(fips, join_by(county)) |>
  select(fips_code, county, rate_2018, rate_2023)
stopifnot(!any(is.na(opioid$fips_code)), nrow(opioid) == 24)
write_csv(opioid, "data/md_opioid_deaths_county.csv")
print(opioid, n = 24)

# 3. lab_09 Q1: kindergarten exemption rates, 2018-19 and 2023-24, with GEOIDs.
# The older file keeps a trailing space after each county name (as exported), so students
# have to join on GEOID rather than county name.
for (yr in c(2018, 2023)) {
  k <- read_csv(glue::glue("data/md_kindergarten_immunization_{yr}.csv"), show_col_types = FALSE) |>
    left_join(fips, join_by(COUNTY == county)) |>
    select(GEOID = fips_code, County = COUNTY, Enrolled = ENROLLED, Surveyed = SURVEYED,
           MMR, Medical = MEDICAL_EXEMPT, Religious = RELIGIOUS_EXEMPT)
  stopifnot(!any(is.na(k$GEOID)))
  if (yr == 2018) k <- k |> mutate(County = paste0(County, " "))
  write_csv(k, glue::glue("data/md_kindergarten_county_{yr}.csv"))
}

# 4. lab_09 Q2: Maryland flu vaccination coverage by age group, three seasons, by month
flu <- read_csv("data/cdc_md_flu_vax.csv", show_col_types = FALSE) |>
  filter(dimension_type == "Age",
         dimension %in% c("6 Months - 4 Years", "5-12 Years", "13-17 Years", "18-49 Years", "50-64 Years", ">=65 Years"),
         year_season %in% c("2019-20", "2022-23", "2025-26")) |>
  transmute(age_group = dimension, month, season = year_season, coverage = parse_number(coverage_estimate)) |>
  pivot_wider(names_from = season, values_from = coverage) |>
  select(age_group, month, `2019-20`, `2022-23`, `2025-26`) |>
  arrange(month, age_group)
write_csv(flu, "data/md_flu_vax_by_age.csv")
print(flu |> filter(month == 5))

# 5. lab_10 Q1: uninsured rate by county and statewide (SHIP), latest year
unins <- ship |>
  filter(metric_name == "Uninsurance Rate", subpopulation_type == "Total")
latest_unins <- max(unins$time_period)
state_rate <- unins |> filter(geography_type == "State", time_period == latest_unins) |> pull(value)
unins_county <- unins |>
  filter(geography_type == "County", time_period == latest_unins) |>
  mutate(county = recode(geography, !!!ship_names)) |>
  left_join(fips, join_by(county)) |>
  transmute(GEOID = fips_code, county, year = time_period, uninsured_rate = value, state_rate = state_rate)
stopifnot(nrow(unins_county) == 24, !any(is.na(unins_county$GEOID)))
write_csv(unins_county, "data/md_uninsured_county.csv")
print(unins_county)

# 6. lab_10 Q3: people fully vaccinated against COVID-19 by county, July 2021 and April 2023
vax_all <- read_csv("https://opendata.maryland.gov/resource/4ibg-xizv.csv?$limit=100000", show_col_types = FALSE) |>
  mutate(date = as.Date(vaccination_date)) |>
  filter(county != "Unknown", !is.na(fullyvaccinatedcumulative))
# some counties have no record on the final day, so take each county's latest record
vax <- vax_all |> filter(date == as.Date("2021-07-01")) |> select(county, july_2021 = fullyvaccinatedcumulative) |>
  left_join(vax_all |> group_by(county) |> slice_max(date, n = 1, with_ties = FALSE) |>
              select(county, april_2023 = fullyvaccinatedcumulative), join_by(county))
stopifnot(nrow(vax) == 24, !anyNA(vax))
write_csv(vax, "data/md_covid_vax_county.csv")
print(vax, n = 30)

# 7. Spreadsheet chapters: 2025 Open Payments to Maryland recipients other than food and beverage,
# with readable column names, small enough for Google Sheets
sheets <- read_csv("data/md_open_payments_2025.csv.gz", show_col_types = FALSE) |>
  filter(nature_of_payment != "Food and Beverage") |>
  transmute(`Date of Payment` = date_of_payment, `Recipient Type` = recipient_type,
            `Recipient Name` = recipient_name, `Recipient City` = recipient_city,
            `Recipient ZIP` = recipient_zip, Specialty = specialty, Company = company,
            `Company State` = company_state, Amount = amount, `Nature of Payment` = nature_of_payment,
            `Form of Payment` = form_of_payment, `Product Name` = product_name)
write_csv(sheets, "data/md_open_payments_2025_sheets.csv", na = "")
message("sheets file: ", nrow(sheets), " rows")

# 8. Spreadsheet formulas chapter: Maryland drug and alcohol intoxication deaths by substance,
# 2014-2016, with the state's total (MD open data f53i-bwcd and at7j-r3rc). One death can
# involve several substances, so the substance rows add up to more than the total.
subst <- read_csv("https://opendata.maryland.gov/resource/f53i-bwcd.csv", show_col_types = FALSE) |>
  filter(calendar_year %in% 2014:2016) |>
  pivot_longer(-calendar_year, names_to = "Substance", values_to = "deaths") |>
  mutate(Substance = recode(Substance, heroin_deaths = "Heroin", prescription_opiod_deaths = "Prescription opioids",
                            alcohol_deaths = "Alcohol", benzodiazepine_deaths = "Benzodiazepines",
                            cocaine_deaths = "Cocaine", fentanyl_deaths = "Fentanyl")) |>
  pivot_wider(names_from = calendar_year, values_from = deaths)
total <- read_csv("https://opendata.maryland.gov/resource/at7j-r3rc.csv", show_col_types = FALSE) |>
  mutate(year = parse_number(calendar_year)) |>
  filter(year %in% 2014:2016) |>
  select(year, accidental_or_undetermined_intoxication_deaths) |>
  pivot_wider(names_from = year, values_from = accidental_or_undetermined_intoxication_deaths) |>
  mutate(Substance = "Total intoxication deaths", .before = 1)
deaths <- bind_rows(subst |> arrange(desc(`2016`)), total) |> select(Substance, `2014`, `2015`, `2016`)
write_csv(deaths, "data/md_intoxication_deaths_2014_2016.csv")
print(deaths)
