# 1. Load setup and data
source("00_setup.R")

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

# Keep only countries with enough invoices for stable regression estimates
min_invoices <- 30

country_counts <- invoice_data %>%
  dplyr::count(country, name = "n_invoices")

valid_countries <- country_counts %>%
  dplyr::filter(n_invoices >= min_invoices) %>%
  dplyr::pull(country)

n_excluded <- nrow(country_counts) - length(valid_countries)
cat("Excluding", n_excluded, "low-volume countries (fewer than",
    min_invoices, "invoices) from regression\n")

invoice_data <- invoice_data %>%
  dplyr::filter(country %in% valid_countries)

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
png(
  filename = file.path(output_path, "figures", "regression_diagnostics.png"),
  width = 1200,
  height = 800,
  type = "cairo"
)

par(mfrow = c(2, 2))
plot(model)

dev.off()
