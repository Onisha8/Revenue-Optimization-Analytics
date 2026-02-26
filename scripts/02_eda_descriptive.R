source("scripts/00_setup.R")

# 1) Load processed data (single source of truth)
retail <- readr::read_csv(file.path(data_processed, "retail_features.csv"))

# 2) Quick sanity checks
cat("Rows:", nrow(retail), "\n")
cat("Customers:", dplyr::n_distinct(retail$customer_id), "\n")
cat("Invoices:", dplyr::n_distinct(retail$invoice), "\n")
cat("Date range:", min(retail$invoice_date), "to", max(retail$invoice_date), "\n")

# 3) KPI Summary (overall)
kpi_overall <- retail %>%
  dplyr::summarise(
    total_revenue = sum(revenue, na.rm = TRUE),
    total_orders  = dplyr::n_distinct(invoice),
    total_customers = dplyr::n_distinct(customer_id),
    avg_order_value = total_revenue / total_orders
  )

readr::write_csv(kpi_overall, file.path(output_path, "tables", "kpi_overall.csv"))

# 4) Monthly trend (revenue + orders)
monthly <- retail %>%
  dplyr::group_by(month_year) %>%
  dplyr::summarise(
    revenue = sum(revenue, na.rm = TRUE),
    orders  = dplyr::n_distinct(invoice),
    .groups = "drop"
  ) %>%
  dplyr::arrange(month_year)

readr::write_csv(monthly, file.path(output_path, "tables", "monthly_trend.csv"))

p_monthly_rev <- ggplot2::ggplot(monthly, ggplot2::aes(x = month_year, y = revenue)) +
  ggplot2::geom_line() +
  ggplot2::labs(
    title = "Monthly Revenue Trend",
    x = "Month",
    y = "Revenue"
  )

ggplot2::ggsave(
  filename = file.path(output_path, "figures", "monthly_revenue_trend.png"),
  plot = p_monthly_rev,
  width = 10,
  height = 5
)

# 5) Top countries by revenue
top_countries <- retail %>%
  dplyr::group_by(country) %>%
  dplyr::summarise(
    revenue = sum(revenue, na.rm = TRUE),
    orders  = dplyr::n_distinct(invoice),
    customers = dplyr::n_distinct(customer_id),
    .groups = "drop"
  ) %>%
  dplyr::arrange(dplyr::desc(revenue)) %>%
  dplyr::slice_head(n = 10)

readr::write_csv(top_countries, file.path(output_path, "tables", "top_10_countries.csv"))

p_countries <- ggplot2::ggplot(top_countries, ggplot2::aes(x = reorder(country, revenue), y = revenue)) +
  ggplot2::geom_col() +
  ggplot2::coord_flip() +
  ggplot2::labs(
    title = "Top 10 Countries by Revenue",
    x = "Country",
    y = "Revenue"
  )

ggplot2::ggsave(
  filename = file.path(output_path, "figures", "top_10_countries_revenue.png"),
  plot = p_countries,
  width = 10,
  height = 6
)

# 6) Top products by revenue (use description; remove missing/blank)
top_products <- retail %>%
  dplyr::filter(!is.na(description), description != "") %>%
  dplyr::group_by(description) %>%
  dplyr::summarise(
    revenue = sum(revenue, na.rm = TRUE),
    quantity = sum(quantity, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  dplyr::arrange(dplyr::desc(revenue)) %>%
  dplyr::slice_head(n = 10)

readr::write_csv(top_products, file.path(output_path, "tables", "top_10_products.csv"))

# 7) Top customers by revenue
top_customers <- retail %>%
  dplyr::group_by(customer_id) %>%
  dplyr::summarise(
    revenue = sum(revenue, na.rm = TRUE),
    orders  = dplyr::n_distinct(invoice),
    .groups = "drop"
  ) %>%
  dplyr::arrange(dplyr::desc(revenue)) %>%
  dplyr::slice_head(n = 10)

readr::write_csv(top_customers, file.path(output_path, "tables", "top_10_customers.csv"))

# 8) Basic distribution: order value (invoice-level)
invoice_values <- retail %>%
  dplyr::group_by(invoice) %>%
  dplyr::summarise(order_value = sum(revenue, na.rm = TRUE), .groups = "drop")

readr::write_csv(invoice_values, file.path(output_path, "tables", "invoice_order_values.csv"))

p_order_hist <- ggplot2::ggplot(invoice_values, ggplot2::aes(x = order_value)) +
  ggplot2::geom_histogram(bins = 50) +
  ggplot2::labs(
    title = "Distribution of Order Value (Invoice Level)",
    x = "Order Value",
    y = "Count of Orders"
  )

ggplot2::ggsave(
  filename = file.path(output_path, "figures", "order_value_distribution.png"),
  plot = p_order_hist,
  width = 10,
  height = 5
)

cat("Step 3 complete: outputs saved to outputs/tables and outputs/figures\n")
