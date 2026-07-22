source("scripts/00_setup.R")

# 1. Load data
retail <- readr::read_csv(
  file.path(data_processed, "retail_features.csv")
) %>%
  mutate(invoice_date = lubridate::as_datetime(invoice_date))

# 2. Create invoice level dataset
invoice_values <- retail %>%
  group_by(invoice) %>%
  summarise(
    order_value = sum(revenue),
    .groups = "drop"
  )

# 3. Sample statistics
n <- nrow(invoice_values)
mean_order <- mean(invoice_values$order_value)
sd_order <- sd(invoice_values$order_value)

cat("Sample size:", n, "\n")
cat("Mean Order Value:", mean_order, "\n")

# 4. Compute 95% Confidence Interval
alpha <- 0.05

t_value <- qt(1 - alpha/2, df = n - 1)

margin_error <- t_value * (sd_order / sqrt(n))

ci_lower <- mean_order - margin_error
ci_upper <- mean_order + margin_error

cat("95% Confidence Interval for Average Order Value:\n")
cat(ci_lower, "to", ci_upper, "\n")

# 5. Save Result
ci_results <- data.frame(
  metric = "Average Order Value",
  mean = mean_order,
  lower_ci = ci_lower,
  upper_ci = ci_upper
)

write_csv(
  ci_results,
  file.path(output_path, "tables", "confidence_interval_aov.csv")
)

