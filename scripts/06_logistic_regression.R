# 1. Load setup and data
source("scripts/00_setup.R")

retail <- readr::read_csv(
  file.path(data_processed, "retail_features.csv")
) %>%
  dplyr::mutate(invoice_date = lubridate::as_datetime(invoice_date))

# 2. Build customer-level dataset
customer_data <- retail %>%
  dplyr::group_by(customer_id) %>%
  dplyr::summarise(
    total_revenue = sum(revenue, na.rm = TRUE),
    avg_order_value = mean(revenue, na.rm = TRUE),
    total_orders = dplyr::n_distinct(invoice),
    first_country = dplyr::first(country),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    repeat_customer = if_else(total_orders > 1, 1, 0)
  )

# 3. Fit Logistic Regression Model
logit_model <- glm(
  repeat_customer ~ total_revenue + avg_order_value,
  data = customer_data,
  family = binomial
)

# 4. View Results
summary(logit_model)

# 5. Add Predicted probabilities
customer_data <- customer_data %>%
  dplyr::mutate(
    predicted_probability = predict(logit_model, type = "response")
  )

# 6. Save Results
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

# 7. Visualtization
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


