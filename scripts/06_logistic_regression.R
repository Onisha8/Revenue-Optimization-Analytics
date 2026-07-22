# 1. Load setup and data
source("00_setup.R")

retail <- readr::read_csv(
  file.path(data_processed, "retail_features.csv")
) %>%
  dplyr::mutate(invoice_date = lubridate::as_datetime(invoice_date))

# 2. Build invoice-level dates first (needed for time-based features)
invoice_dates <- retail %>%
  dplyr::group_by(customer_id, invoice) %>%
  dplyr::summarise(
    invoice_date = dplyr::first(invoice_date),
    invoice_revenue = sum(revenue, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  dplyr::arrange(customer_id, invoice_date)

# Reference date = one day after the last transaction in the dataset
reference_date <- max(invoice_dates$invoice_date) + lubridate::days(1)

# 3. Build customer-level dataset with leakage-free predictors
customer_data <- invoice_dates %>%
  dplyr::group_by(customer_id) %>%
  dplyr::summarise(
    total_orders = dplyr::n_distinct(invoice),
    first_order_date = min(invoice_date),
    first_order_value = dplyr::first(invoice_revenue),
    days_since_first_purchase = as.numeric(difftime(reference_date, min(invoice_date), units = "days")),
    avg_days_between_purchases = if_else(
      dplyr::n_distinct(invoice) > 1,
      as.numeric(difftime(max(invoice_date), min(invoice_date), units = "days")) / (dplyr::n_distinct(invoice) - 1),
      NA_real_
    ),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    repeat_customer = if_else(total_orders > 1, 1, 0)
  )

# 4. Add distinct products purchased (separate summarise, joined back)
product_diversity <- retail %>%
  dplyr::group_by(customer_id) %>%
  dplyr::summarise(
    distinct_products = dplyr::n_distinct(stock_code),
    first_country = dplyr::first(country),
    .groups = "drop"
  )

customer_data <- customer_data %>%
  dplyr::left_join(product_diversity, by = "customer_id")

# 5. For one-time customers, avg_days_between_purchases is NA by construction —
# fill with 0 so the model can use these rows (0 = "no repeat interval observed yet")
customer_data <- customer_data %>%
  dplyr::mutate(
    avg_days_between_purchases = tidyr::replace_na(avg_days_between_purchases, 0)
  )

# Restrict to customers who had a fair chance to become repeat buyers
# (avoids observation-window bias: customers who first purchased near the
# end of the dataset haven't had time to reorder, which artificially
# separates the classes)
min_observation_days <- 90

customer_data <- customer_data %>%
  dplyr::filter(
    as.numeric(difftime(reference_date, first_order_date, units = "days")) >= min_observation_days
  )

cat("Customers remaining after observation-window filter:", nrow(customer_data), "\n")

# 6. Fit Logistic Regression Model
logit_model <- glm(
  repeat_customer ~ first_order_value + days_since_first_purchase + distinct_products,
  data = customer_data,
  family = binomial
)

summary(logit_model)

# 7. Add predicted probabilities
customer_data <- customer_data %>%
  dplyr::mutate(
    predicted_probability = predict(logit_model, type = "response")
  )

# 8. Save Results
# Model coefficients
logit_results <- broom::tidy(logit_model)

readr::write_csv(
  logit_results,
  file.path(output_path, "tables", "logistic_regression_results.csv")
)
# Customer prediction output
readr::write_csv(
  customer_data,
  file.path(output_path, "tables", "customer_repeat_purchase_predictions.csv")
)

# 9. Visualtization
p_logit <- ggplot2::ggplot(customer_data, ggplot2::aes(x = predicted_probability)) +
  ggplot2::geom_histogram(bins = 30) +
  ggplot2::labs(
    title = "Predicted Probability of Repeat Purchase",
    x = "Predicted Probability",
    y = "Number of Customers"
  )

ggplot2::ggsave(
  filename = file.path(output_path, "figures", "predicted_repeat_purchase_probability.png"),
  plot = p_logit,
  width = 9,
  height = 5
)
