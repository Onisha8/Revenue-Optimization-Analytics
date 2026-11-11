# Project: Revenue Optimization & Customer Behavior Analytics
# File: 08_time_series.R
# Purpose: Trend regression, autocorrelation check, seasonal indices and
#          a seasonally adjusted 2012 revenue forecast

source("00_setup.R")
library(lmtest)

# 1. Load data
retail <- readr::read_csv(
  file.path(data_processed, "retail_features.csv")
) %>%
  dplyr::mutate(invoice_date = lubridate::as_datetime(invoice_date))

# 2. Monthly revenue series
# December 2011 only runs to the 9th, so it is dropped to keep complete months
monthly <- retail %>%
  dplyr::mutate(month = lubridate::floor_date(invoice_date, "month")) %>%
  dplyr::filter(month < as.POSIXct("2011-12-01", tz = "UTC")) %>%
  dplyr::group_by(month) %>%
  dplyr::summarise(revenue = sum(revenue), .groups = "drop") %>%
  dplyr::arrange(month) %>%
  dplyr::mutate(
    index = dplyr::row_number(),
    month_num = lubridate::month(month)
  )

cat("Months in series:", nrow(monthly), "\n")

# 3. Base trend model: revenue = b0 + b1 * index
trend_model <- lm(revenue ~ index, data = monthly)
summary(trend_model)

# 4. Durbin-Watson test for autocorrelation in the residuals
dw_trend <- lmtest::dwtest(trend_model)
print(dw_trend)

# 5. Seasonal indices (ratio-to-trend method)
# Each month's actual / trend value, averaged by calendar month and
# normalised so the 12 indices average to 1
monthly <- monthly %>%
  dplyr::mutate(
    trend_fit = fitted(trend_model),
    ratio = revenue / trend_fit
  )

seasonal_indices <- monthly %>%
  dplyr::group_by(month_num) %>%
  dplyr::summarise(raw_index = mean(ratio), .groups = "drop") %>%
  dplyr::mutate(
    seasonal_index = raw_index / mean(raw_index),
    month_name = month.abb[month_num]
  )

print(seasonal_indices)

readr::write_csv(
  seasonal_indices,
  file.path(output_path, "tables", "seasonal_indices.csv")
)

# 6. Seasonally adjusted model
# Deseasonalise revenue, refit the trend, then reseasonalise the fitted values
monthly <- monthly %>%
  dplyr::left_join(
    dplyr::select(seasonal_indices, month_num, seasonal_index),
    by = "month_num"
  ) %>%
  dplyr::mutate(deseasonalised = revenue / seasonal_index)

adj_model <- lm(deseasonalised ~ index, data = monthly)
summary(adj_model)

dw_adj <- lmtest::dwtest(adj_model)
print(dw_adj)

monthly <- monthly %>%
  dplyr::mutate(adj_fit = fitted(adj_model) * seasonal_index)

# In-sample fit comparison: trend-only vs seasonally adjusted
mape <- function(actual, predicted) mean(abs(actual - predicted) / actual) * 100

model_comparison <- data.frame(
  model = c("Trend only", "Trend x seasonal index"),
  r_squared = c(
    summary(trend_model)$r.squared,
    cor(monthly$revenue, monthly$adj_fit)^2
  ),
  mape_pct = c(
    mape(monthly$revenue, monthly$trend_fit),
    mape(monthly$revenue, monthly$adj_fit)
  ),
  durbin_watson = c(dw_trend$statistic, dw_adj$statistic),
  dw_p_value = c(dw_trend$p.value, dw_adj$p.value)
)

print(model_comparison)

readr::write_csv(
  model_comparison,
  file.path(output_path, "tables", "time_series_model_comparison.csv")
)

# 7. Forecast Dec 2011 - Dec 2012
forecast <- data.frame(
  month = seq(max(monthly$month) %m+% months(1), by = "month", length.out = 13)
) %>%
  dplyr::mutate(
    index = max(monthly$index) + dplyr::row_number(),
    month_num = lubridate::month(month)
  ) %>%
  dplyr::left_join(
    dplyr::select(seasonal_indices, month_num, seasonal_index),
    by = "month_num"
  )

trend_pi <- predict(adj_model, newdata = forecast, interval = "prediction")

forecast <- forecast %>%
  dplyr::mutate(
    forecast_revenue = trend_pi[, "fit"] * seasonal_index,
    lower_pi = trend_pi[, "lwr"] * seasonal_index,
    upper_pi = trend_pi[, "upr"] * seasonal_index
  )

print(forecast)

readr::write_csv(
  forecast,
  file.path(output_path, "tables", "revenue_forecast_2012.csv")
)

# 8. Plots
p_ts <- ggplot2::ggplot(monthly, ggplot2::aes(x = month)) +
  ggplot2::geom_line(ggplot2::aes(y = revenue, colour = "Actual"), linewidth = 0.9) +
  ggplot2::geom_line(ggplot2::aes(y = trend_fit, colour = "Linear trend"), linetype = "dashed") +
  ggplot2::geom_line(ggplot2::aes(y = adj_fit, colour = "Trend x seasonal index")) +
  ggplot2::geom_ribbon(
    data = forecast,
    ggplot2::aes(ymin = lower_pi, ymax = upper_pi),
    fill = "grey70", alpha = 0.4
  ) +
  ggplot2::geom_line(
    data = forecast,
    ggplot2::aes(y = forecast_revenue, colour = "Forecast"),
    linewidth = 0.9
  ) +
  ggplot2::scale_y_continuous(labels = scales::dollar) +
  ggplot2::scale_colour_manual(values = c(
    "Actual" = "black",
    "Linear trend" = "grey40",
    "Trend x seasonal index" = "steelblue",
    "Forecast" = "darkorange"
  )) +
  ggplot2::labs(
    title = "Monthly Revenue: Trend, Seasonality and 2012 Forecast",
    subtitle = "Shaded band = 95% prediction interval",
    x = "Month", y = "Revenue", colour = NULL
  ) +
  ggplot2::theme(legend.position = "bottom")

ggplot2::ggsave(
  filename = file.path(output_path, "figures", "revenue_forecast.png"),
  plot = p_ts,
  width = 10,
  height = 5.5
)

p_si <- ggplot2::ggplot(
  seasonal_indices,
  ggplot2::aes(x = factor(month_name, levels = month.abb), y = seasonal_index)
) +
  ggplot2::geom_col(fill = "steelblue") +
  ggplot2::geom_hline(yintercept = 1, linetype = "dashed") +
  ggplot2::labs(
    title = "Seasonal Revenue Index by Month",
    subtitle = "1.0 = average month",
    x = "Month", y = "Seasonal index"
  )

ggplot2::ggsave(
  filename = file.path(output_path, "figures", "seasonal_indices.png"),
  plot = p_si,
  width = 8,
  height = 5
)

cat("Time series outputs saved\n")
