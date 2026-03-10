# 1. Load setup and data
source("scripts/00_setup.R")

retail <- readr::read_csv(
  file.path(data_processed, "retail_features.csv")
) %>%
  dplyr::mutate(invoice_date = lubridate::as_datetime(invoice_date))

# 2. Prepare invoice-level dataset
invoice_data <- retail %>%
  dplyr::group_by(invoice, country) %>%
  dplyr::summarise(
    order_value = sum(revenue),
    total_items = sum(quantity),
    avg_price = mean(price),
    .groups = "drop"
  )

# 3. Fit a Regression Model
# Order Value=f(total items, avg price, country)
model <- lm(order_value ~ total_items + avg_price + country,
            data = invoice_data)

# 4. Model Results
summary(model)

model_results <- broom::tidy(model)

readr::write_csv(
  model_results,
  file.path(output_path, "tables", "regression_results.csv")
)

# 5. Diagnostic Plot 
plot(model)
