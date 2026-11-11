# Project: Revenue Optimization & Customer Behavior Analytics
# File: 10_network_optimization.R
# Purpose: Mixed-integer facility-location model - should the company open a
#          continental European fulfillment hub, and where?

source("00_setup.R")
library(lpSolve)

# 1. Load data
retail <- readr::read_csv(
  file.path(data_processed, "retail_features.csv")
)

n_years <- 2  # data covers Dec 2009 - Dec 2011

# 2. Demand points: European countries, located at their capital city
# Non-European and unspecified countries are left out; they are shipped from
# the UK regardless of network design
locations <- tibble::tribble(
  ~country,          ~city,        ~lat,   ~lon,
  "United Kingdom",  "London",     51.51,  -0.13,
  "EIRE",            "Dublin",     53.35,  -6.26,
  "Channel Islands", "St Helier",  49.19,  -2.11,
  "Germany",         "Berlin",     52.52,  13.40,
  "France",          "Paris",      48.86,   2.35,
  "Netherlands",     "Amsterdam",  52.37,   4.90,
  "Belgium",         "Brussels",   50.85,   4.35,
  "Spain",           "Madrid",     40.42,  -3.70,
  "Portugal",        "Lisbon",     38.72,  -9.14,
  "Italy",           "Rome",       41.90,  12.50,
  "Switzerland",     "Bern",       46.95,   7.45,
  "Austria",         "Vienna",     48.21,  16.37,
  "Sweden",          "Stockholm",  59.33,  18.07,
  "Norway",          "Oslo",       59.91,  10.75,
  "Denmark",         "Copenhagen", 55.68,  12.57,
  "Finland",         "Helsinki",   60.17,  24.94,
  "Iceland",         "Reykjavik",  64.15, -21.94,
  "Poland",          "Warsaw",     52.23,  21.01,
  "Czech Republic",  "Prague",     50.08,  14.44,
  "Lithuania",       "Vilnius",    54.69,  25.28,
  "Greece",          "Athens",     37.98,  23.73,
  "Cyprus",          "Nicosia",    35.19,  33.38,
  "Malta",           "Valletta",   35.90,  14.51
)

demand <- retail %>%
  dplyr::filter(country %in% locations$country) %>%
  dplyr::group_by(country) %>%
  dplyr::summarise(
    annual_units = sum(quantity) / n_years,
    annual_orders = dplyr::n_distinct(invoice) / n_years,
    .groups = "drop"
  ) %>%
  dplyr::inner_join(locations, by = "country")

# 3. Candidate hubs (London is the existing site and stays open)
hubs <- locations %>%
  dplyr::filter(city %in% c("London", "Amsterdam", "Brussels", "Paris", "Berlin"))

# 4. Cost assumptions (not in the data; change here to test scenarios)
cost_per_unit_km <- 0.0004  # $ to move one unit 1 km by road/sea freight
road_factor      <- 1.25    # road distance / straight-line distance
uk_export_charge <- 0.15    # $ per unit for cross-border handling out of the UK

# 5. Distance and per-unit shipping cost matrix
haversine_km <- function(lat1, lon1, lat2, lon2) {
  to_rad <- pi / 180
  dlat <- (lat2 - lat1) * to_rad
  dlon <- (lon2 - lon1) * to_rad
  a <- sin(dlat / 2)^2 + cos(lat1 * to_rad) * cos(lat2 * to_rad) * sin(dlon / 2)^2
  6371 * 2 * asin(sqrt(a))
}

n_d <- nrow(demand)
n_h <- nrow(hubs)

unit_cost <- matrix(0, n_d, n_h, dimnames = list(demand$country, hubs$city))
for (i in seq_len(n_d)) {
  for (j in seq_len(n_h)) {
    km <- road_factor * haversine_km(demand$lat[i], demand$lon[i], hubs$lat[j], hubs$lon[j])
    export <- if (hubs$city[j] == "London" && demand$country[i] != "United Kingdom") {
      uk_export_charge
    } else {
      0
    }
    unit_cost[i, j] <- km * cost_per_unit_km + export
  }
}

# 6. Facility-location MILP
# Variables: x[i, j] = 1 if country i is served from hub j (single sourcing),
#            y[j]    = 1 if hub j is open
# Minimise   sum fixed[j] * y[j] + sum annual_units[i] * unit_cost[i, j] * x[i, j]
# Subject to each country served by exactly one hub, only from open hubs,
#            London open, and at most `max_new_hubs` new hubs
solve_network <- function(new_hub_fixed_cost, max_new_hubs = 1) {
  fixed <- ifelse(hubs$city == "London", 0, new_hub_fixed_cost)
  ship <- as.vector(unit_cost * demand$annual_units)  # column-major: i fastest
  obj <- c(ship, fixed)

  n_x <- n_d * n_h
  x_idx <- function(i, j) (j - 1) * n_d + i

  rows <- list(); dir <- c(); rhs <- c()

  # Each country assigned to exactly one hub
  for (i in seq_len(n_d)) {
    r <- numeric(n_x + n_h)
    r[x_idx(i, seq_len(n_h))] <- 1
    rows[[length(rows) + 1]] <- r; dir <- c(dir, "="); rhs <- c(rhs, 1)
  }

  # Only assign to open hubs: x[i, j] <= y[j]
  for (i in seq_len(n_d)) {
    for (j in seq_len(n_h)) {
      r <- numeric(n_x + n_h)
      r[x_idx(i, j)] <- 1
      r[n_x + j] <- -1
      rows[[length(rows) + 1]] <- r; dir <- c(dir, "<="); rhs <- c(rhs, 0)
    }
  }

  # London stays open
  r <- numeric(n_x + n_h); r[n_x + which(hubs$city == "London")] <- 1
  rows[[length(rows) + 1]] <- r; dir <- c(dir, "="); rhs <- c(rhs, 1)

  # Limit on new hubs
  r <- numeric(n_x + n_h); r[n_x + which(hubs$city != "London")] <- 1
  rows[[length(rows) + 1]] <- r; dir <- c(dir, "<="); rhs <- c(rhs, max_new_hubs)

  sol <- lpSolve::lp(
    direction = "min",
    objective.in = obj,
    const.mat = do.call(rbind, rows),
    const.dir = dir,
    const.rhs = rhs,
    all.bin = TRUE
  )

  x <- matrix(sol$solution[seq_len(n_x)], n_d, n_h)
  open <- hubs$city[sol$solution[n_x + seq_len(n_h)] > 0.5]

  list(
    status = sol$status,
    total_cost = sol$objval,
    shipping_cost = sum(ship * sol$solution[seq_len(n_x)]),
    open_hubs = open,
    assignment = data.frame(
      country = demand$country,
      annual_units = round(demand$annual_units),
      served_from = hubs$city[apply(x, 1, which.max)]
    )
  )
}

# 7. Baseline: UK only (new hubs not allowed)
uk_only <- solve_network(new_hub_fixed_cost = 0, max_new_hubs = 0)
cat("UK-only annual shipping cost:", scales::dollar(uk_only$total_cost), "\n")

# 8. Fixed-cost scan: at what annual cost does a European hub stop paying off?
fixed_costs <- seq(0, 300000, by = 10000)

scan <- purrr::map_dfr(fixed_costs, function(fc) {
  s <- solve_network(fc)
  data.frame(
    new_hub_fixed_cost = fc,
    total_cost = s$total_cost,
    shipping_cost = s$shipping_cost,
    new_hub = paste(setdiff(s$open_hubs, "London"), collapse = ", "),
    savings_vs_uk_only = uk_only$total_cost - s$total_cost
  )
}) %>%
  dplyr::mutate(
    new_hub = dplyr::if_else(new_hub == "", "None (UK only)", new_hub),
    dplyr::across(c(total_cost, shipping_cost, savings_vs_uk_only), ~ round(.x, 2))
  )

print(scan)

readr::write_csv(
  scan,
  file.path(output_path, "tables", "network_fixed_cost_scan.csv")
)

# Break-even: shipping saved by the best single EU hub when it is free
best_free <- solve_network(new_hub_fixed_cost = 0)
breakeven <- uk_only$total_cost - best_free$shipping_cost
cat(
  "Best EU hub:", setdiff(best_free$open_hubs, "London"),
  "| saves", scales::dollar(breakeven), "per year in shipping",
  "-> worth opening if its annual fixed cost is below this\n"
)

network_summary <- data.frame(
  uk_only_shipping_cost = uk_only$total_cost,
  best_eu_hub = setdiff(best_free$open_hubs, "London"),
  shipping_cost_with_hub = best_free$shipping_cost,
  breakeven_annual_fixed_cost = breakeven
)

readr::write_csv(
  network_summary,
  file.path(output_path, "tables", "network_summary.csv")
)

readr::write_csv(
  best_free$assignment,
  file.path(output_path, "tables", "network_assignment_with_eu_hub.csv")
)

print(best_free$assignment)

# 9. Plot
p_scan <- ggplot2::ggplot(scan, ggplot2::aes(x = new_hub_fixed_cost, y = total_cost)) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::geom_point(ggplot2::aes(colour = new_hub), size = 2.5) +
  ggplot2::geom_hline(yintercept = uk_only$total_cost, linetype = "dashed") +
  ggplot2::geom_vline(xintercept = breakeven, linetype = "dotted", colour = "grey40") +
  ggplot2::annotate(
    "text", x = breakeven, y = min(scan$total_cost),
    label = paste("Break-even", scales::dollar(round(breakeven, -3))),
    hjust = -0.05, vjust = 0, size = 3.5
  ) +
  ggplot2::scale_x_continuous(labels = scales::dollar) +
  ggplot2::scale_y_continuous(labels = scales::dollar) +
  ggplot2::labs(
    title = "European Fulfillment Hub: Optimal Network vs Annual Hub Cost",
    subtitle = "Dashed line = ship everything from London",
    x = "Annual fixed cost of a new hub",
    y = "Total annual network cost",
    colour = "New hub opened"
  ) +
  ggplot2::theme(legend.position = "bottom")

ggplot2::ggsave(
  filename = file.path(output_path, "figures", "network_hub_breakeven.png"),
  plot = p_scan,
  width = 10,
  height = 5.5
)

cat("Network optimization outputs saved\n")
