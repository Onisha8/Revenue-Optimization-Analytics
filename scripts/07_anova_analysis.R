# 1. Load setup and data
source("scripts/00_setup.R")

retail <- readr::read_csv(
  file.path(data_processed, "retail_features.csv")
) %>%
  dplyr::mutate(invoice_date = lubridate::as_datetime(invoice_date))

# 2. Prepare invoice level dataset
invoice_data <- retail %>%
  dplyr::group_by(invoice, country) %>%
  dplyr::summarise(
    order_value = sum(revenue),
    .groups = "drop"
  )

# 3. Selectinh top countries
top_countries <- invoice_data %>%
  dplyr::group_by(country) %>%
  dplyr::summarise(total_revenue = sum(order_value)) %>%
  dplyr::arrange(desc(total_revenue)) %>%
  dplyr::slice_head(n = 5) %>%
  dplyr::pull(country)

anova_data <- invoice_data %>%
  dplyr::filter(country %in% top_countries)

# 4. Run ANOVA
anova_model <- aov(order_value ~ country, data = anova_data)

summary(anova_model)

# 5. Visualize Differences
p_anova <- ggplot2::ggplot(anova_data,
                           ggplot2::aes(x = country,
                                        y = order_value)) +
  ggplot2::geom_boxplot() +
  ggplot2::labs(
    title = "Order Value Distribution by Country",
    x = "Country",
    y = "Order Value"
  )

ggplot2::ggsave(
  filename = file.path(output_path,
                       "figures",
                       "anova_country_order_value.png"),
  plot = p_anova,
  width = 9,
  height = 5
)

# 6. ANOVA Results
anova_results <- broom::tidy(anova_model)

readr::write_csv(
  anova_results,
  file.path(output_path,
            "tables",
            "anova_country_results.csv")
)
