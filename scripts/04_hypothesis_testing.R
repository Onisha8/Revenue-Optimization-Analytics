source("scripts/00_setup.R")

# 1. Load data
retail <- readr::read_csv(
  file.path(data_processed, "retail_features.csv")
) %>%
  mutate(invoice_date = lubridate::as_datetime(invoice_date))

# 2. Create invoice level dataset
invoice_values <- retail %>%
  group_by(invoice, country) %>%
  summarise(
    order_value = sum(revenue),
    .groups = "drop"
  )

# 3. Create Comparison Groups
invoice_values <- invoice_values %>%
  mutate(
    region_group =
      if_else(country == "United Kingdom",
              "UK",
              "Non-UK")
  )

# 4. Visual Check
ggplot(invoice_values,
       aes(x = region_group,
           y = order_value)) +
  geom_boxplot() +
  labs(
    title = "Order Value Comparison: UK vs Non-UK",
    x = "Region",
    y = "Order Value"
  )

# 5. Two sample t-test
test_result <- t.test(
  order_value ~ region_group,
  data = invoice_values
)

print(test_result)

# 6. Save Results
ht_results <- data.frame(
  statistic = test_result$statistic,
  p_value = test_result$p.value,
  conf_low = test_result$conf.int[1],
  conf_high = test_result$conf.int[2]
)

write_csv(
  ht_results,
  file.path(output_path,
            "tables",
            "hypothesis_test_uk_vs_nonuk.csv")
)




