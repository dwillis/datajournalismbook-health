# build_state_vax.R
#
# Builds data/state_vaccination.csv for the basic statistics chapter and pre_lab_13:
# one row per state with kindergarten MMR coverage and exemption rates (CDC SchoolVaxView),
# the share of residents without health insurance (ACS 1-year, table S2701) and the 2024
# presidential winner. Needs data/cdc_kindergarten_vax_states.csv (fetch_data.R cdc_vax)
# and a CENSUS_API_KEY.

suppressPackageStartupMessages({
  library(tidyverse)
  library(tidycensus)
})

latest <- "2025-26"
earlier <- "2019-20"

kinder <- read_csv("data/cdc_kindergarten_vax_states.csv", show_col_types = FALSE) |>
  janitor::clean_names() |>
  filter(geography_type == "States")

mmr <- kinder |>
  filter(vaccine_exemption == "MMR", school_year %in% c(earlier, latest)) |>
  mutate(estimate = parse_number(estimate_percent)) |>
  select(state = geography, school_year, estimate) |>
  pivot_wider(names_from = school_year, values_from = estimate) |>
  rename(mmr_2019 = all_of(earlier), mmr_2025 = all_of(latest))

exempt <- kinder |>
  filter(vaccine_exemption == "Exemption", school_year == latest, dose == "Any Exemption") |>
  transmute(state = geography, exemption_rate_2025 = parse_number(estimate_percent))

uninsured <- get_acs(geography = "state", variables = c(pct_uninsured = "S2701_C05_001"),
                     year = 2023, survey = "acs1") |>
  transmute(state = NAME, pct_uninsured = estimate)

harris_states <- c("California", "Colorado", "Connecticut", "Delaware", "District of Columbia",
                   "Hawaii", "Illinois", "Maine", "Maryland", "Massachusetts", "Minnesota",
                   "New Hampshire", "New Jersey", "New Mexico", "New York", "Oregon",
                   "Rhode Island", "Vermont", "Virginia", "Washington")

state_vax <- mmr |>
  inner_join(exempt, join_by(state)) |>
  inner_join(uninsured, join_by(state)) |>
  mutate(vote_2024 = if_else(state %in% harris_states, "Harris", "Trump")) |>
  drop_na() |>
  arrange(state)

write_csv(state_vax, "data/state_vaccination.csv")
message("data/state_vaccination.csv: ", nrow(state_vax), " states")
print(state_vax |> summarise(across(where(is.numeric), list(min = min, max = max))))
