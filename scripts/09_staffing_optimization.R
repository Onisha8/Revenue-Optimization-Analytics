# Project: Revenue Optimization & Customer Behavior Analytics
# File: 09_staffing_optimization.R
# Purpose: Integer linear program for minimum-cost warehouse pick/pack
#          staffing, driven by the hourly order-line profile in the data

source("00_setup.R")
library(lpSolve)

# 1. Load data
retail <- readr::read_csv(
  file.path(data_processed, "retail_features.csv")
) %>%
  dplyr::mutate(invoice_date = lubridate::as_datetime(invoice_date))

# 2. Planning assumptions (not in the data; change here to test scenarios)
open_hours     <- 8:19   # hourly periods covered: 08:00 - 20:00
lines_per_hour <- 60     # order lines one associate can pick and pack per hour
min_staff      <- 1      # at least one associate on duty every open hour
ft_length      <- 8      # full-time shift length (hours)
pt_length      <- 4      # part-time shift length (hours)
ft_wage        <- 18     # $ per hour
pt_wage        <- 14     # $ per hour

# 3. Hourly workload
# Plan to the 90th percentile of order lines per hour so the schedule
# covers busy days, not just the average day
hourly_workload <- function(data) {
  data %>%
    dplyr::mutate(
      day  = as.Date(invoice_date),
      hour = lubridate::hour(invoice_date)
    ) %>%
    dplyr::filter(hour %in% open_hours) %>%
    dplyr::count(day, hour) %>%
    tidyr::complete(day, hour = open_hours, fill = list(n = 0)) %>%
    dplyr::group_by(hour) %>%
    dplyr::summarise(p90_lines = quantile(n, 0.9), .groups = "drop")
}

workload <- dplyr::bind_rows(
  hourly_workload(retail) %>%
    dplyr::mutate(scenario = "Typical (all months)"),
  hourly_workload(dplyr::filter(retail, lubridate::month(invoice_date) == 11)) %>%
    dplyr::mutate(scenario = "Peak (November)")
)

# 4. Shift-covering model
# Decision variables: number of associates starting each shift.
# A shift starting at hour s covers hours s .. s + length - 1 and must end
# by closing time. Part-timers can be capped at the number of full-timers
# on duty each hour (supervision policy).
solve_schedule <- function(required, allow_part_time, productivity = lines_per_hour) {
  need <- pmax(ceiling(required / productivity), min_staff)
  n_hours <- length(open_hours)

  ft_starts <- open_hours[open_hours + ft_length - 1 <= max(open_hours)]
  pt_starts <- if (allow_part_time) {
    open_hours[open_hours + pt_length - 1 <= max(open_hours)]
  } else {
    integer(0)
  }

  covers <- function(starts, len) {
    sapply(starts, function(s) as.numeric(open_hours >= s & open_hours < s + len))
  }

  ft_cover <- matrix(covers(ft_starts, ft_length), nrow = n_hours)
  pt_cover <- matrix(covers(pt_starts, pt_length), nrow = n_hours)

  cost <- c(
    rep(ft_wage * ft_length, length(ft_starts)),
    rep(pt_wage * pt_length, length(pt_starts))
  )

  # Coverage: staff on duty >= staff needed in every hour
  A <- cbind(ft_cover, pt_cover)
  dir <- rep(">=", n_hours)
  rhs <- need

  # Policy: full-timers on duty >= part-timers on duty in every hour
  if (allow_part_time) {
    A <- rbind(A, cbind(ft_cover, -pt_cover))
    dir <- c(dir, rep(">=", n_hours))
    rhs <- c(rhs, rep(0, n_hours))
  }

  sol <- lpSolve::lp(
    direction = "min",
    objective.in = cost,
    const.mat = A,
    const.dir = dir,
    const.rhs = rhs,
    all.int = TRUE
  )

  x <- sol$solution
  n_ft <- length(ft_starts)

  list(
    status = sol$status,
    daily_cost = sol$objval,
    shifts = data.frame(
      type = c(rep("Full-time", n_ft), rep("Part-time", length(pt_starts))),
      start_hour = c(ft_starts, pt_starts),
      associates = x
    ) %>% dplyr::filter(associates > 0),
    coverage = data.frame(
      hour = open_hours,
      required = need,
      full_time_on_duty = as.vector(ft_cover %*% x[seq_len(n_ft)]),
      part_time_on_duty = if (allow_part_time) {
        as.vector(pt_cover %*% x[-seq_len(n_ft)])
      } else {
        0
      }
    )
  )
}

# 5. Solve: 2 demand scenarios x 2 staffing policies
results <- list()

for (sc in unique(workload$scenario)) {
  req <- workload %>%
    dplyr::filter(scenario == sc) %>%
    dplyr::arrange(hour) %>%
    dplyr::pull(p90_lines)

  for (pt in c(FALSE, TRUE)) {
    label <- paste(sc, if (pt) "- full + part-time" else "- full-time only")
    results[[label]] <- solve_schedule(req, allow_part_time = pt)
    results[[label]]$scenario <- sc
    results[[label]]$policy <- if (pt) "Full + part-time" else "Full-time only"
  }
}

staffing_summary <- purrr::map_dfr(results, function(r) {
  data.frame(
    scenario = r$scenario,
    policy = r$policy,
    status = ifelse(r$status == 0, "Optimal", "Not solved"),
    full_time_staff = sum(r$shifts$associates[r$shifts$type == "Full-time"]),
    part_time_staff = sum(r$shifts$associates[r$shifts$type == "Part-time"]),
    paid_hours = sum(r$coverage$full_time_on_duty + r$coverage$part_time_on_duty),
    required_hours = sum(r$coverage$required),
    daily_cost = round(r$daily_cost, 2)
  )
}) %>%
  dplyr::group_by(scenario) %>%
  dplyr::mutate(
    savings_vs_full_time_only = max(daily_cost) - daily_cost,
    idle_hours = paid_hours - required_hours
  ) %>%
  dplyr::ungroup()

print(staffing_summary)

readr::write_csv(
  staffing_summary,
  file.path(output_path, "tables", "staffing_optimization_summary.csv")
)

peak_best <- results[["Peak (November) - full + part-time"]]
print(peak_best$shifts)

readr::write_csv(
  peak_best$shifts,
  file.path(output_path, "tables", "staffing_peak_schedule.csv")
)

# 6. Sensitivity: how cost responds to associate productivity
peak_req <- workload %>%
  dplyr::filter(scenario == "Peak (November)") %>%
  dplyr::arrange(hour) %>%
  dplyr::pull(p90_lines)

sensitivity <- purrr::map_dfr(c(40, 50, 60, 70, 80), function(p) {
  data.frame(
    lines_per_hour = p,
    daily_cost = solve_schedule(peak_req, allow_part_time = TRUE, productivity = p)$daily_cost
  )
})

print(sensitivity)

readr::write_csv(
  sensitivity,
  file.path(output_path, "tables", "staffing_productivity_sensitivity.csv")
)

# 7. Plot peak schedule coverage vs requirement
coverage_long <- peak_best$coverage %>%
  tidyr::pivot_longer(
    c(full_time_on_duty, part_time_on_duty),
    names_to = "type", values_to = "associates"
  ) %>%
  dplyr::mutate(type = dplyr::recode(
    type,
    full_time_on_duty = "Full-time",
    part_time_on_duty = "Part-time"
  ))

p_staff <- ggplot2::ggplot(coverage_long, ggplot2::aes(x = hour)) +
  ggplot2::geom_col(ggplot2::aes(y = associates, fill = type)) +
  ggplot2::geom_step(
    data = peak_best$coverage,
    ggplot2::aes(x = hour - 0.5, y = required),
    direction = "hv", linewidth = 1
  ) +
  ggplot2::scale_x_continuous(breaks = open_hours, labels = sprintf("%02d:00", open_hours)) +
  ggplot2::scale_fill_manual(values = c("Full-time" = "steelblue", "Part-time" = "darkorange")) +
  ggplot2::labs(
    title = "Optimal Peak-Season Pick/Pack Schedule",
    subtitle = paste0(
      "November, 90th percentile workload | daily cost ",
      scales::dollar(peak_best$daily_cost),
      " | black line = associates required"
    ),
    x = "Hour", y = "Associates on duty", fill = NULL
  ) +
  ggplot2::theme(legend.position = "bottom")

ggplot2::ggsave(
  filename = file.path(output_path, "figures", "staffing_schedule_peak.png"),
  plot = p_staff,
  width = 10,
  height = 5
)

cat("Staffing optimization outputs saved\n")
