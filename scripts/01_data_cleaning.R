# scripts/01_data_cleaning.R
source("scripts/00_setup.R")

# Packages used in this script (explicit = professional)
library(readxl)

# -------------------------------
# 1) LOAD (Raw stays raw)
# -------------------------------
raw_file <- file.path(data_raw, "online_retail_II.xlsx")

retail_raw <- read_excel(
  path  = raw_file,
  sheet = "Year 2010-2011"
)

cat("Rows (raw):", nrow(retail_raw), "\n")

# -------------------------------
# 2) CLEAN (standardize + minimal QA)
# -------------------------------
retail_clean <- retail_raw %>%
  janitor::clean_names()

# Optional: quick column check (helps catch sheet differences)
expected_cols <- c("invoice", "stock_code", "description", "quantity",
                   "invoice_date", "price", "customer_id", "country")
missing_cols <- setdiff(expected_cols, names(retail_clean))
if (length(missing_cols) > 0) {
  stop("Missing expected columns: ", paste(missing_cols, collapse = ", "))
}

# Remove rows missing CustomerID (needed for customer-level analytics)
retail_clean <- retail_clean %>%
  dplyr::filter(!is.na(customer_id))

cat("Rows (after CustomerID filter):", nrow(retail_clean), "\n")

# -------------------------------
# 3) VALIDATE (business rules)
# -------------------------------
retail_valid <- retail_clean %>%
  dplyr::filter(
    !stringr::str_starts(invoice, "C"),  # cancellations
    quantity > 0,
    price > 0
  )

cat("Rows (valid transactions):", nrow(retail_valid), "\n")

# -------------------------------
# 4) FEATURES (analysis-ready dataset)
# -------------------------------
# Ensure datetime type
retail_valid <- retail_valid %>%
  dplyr::mutate(invoice_date = as.POSIXct(invoice_date, tz = "UTC"))

# KPI + time features
retail_features <- retail_valid %>%
  dplyr::mutate(
    revenue    = quantity * price,
    year       = lubridate::year(invoice_date),
    month      = lubridate::month(invoice_date),
    month_year = lubridate::floor_date(invoice_date, unit = "month"),
    day_of_week = lubridate::wday(invoice_date, label = TRUE)
  )

# Customer-level features (purchase frequency + repeat flag)
customer_features <- retail_features %>%
  dplyr::group_by(customer_id) %>%
  dplyr::summarise(
    total_orders = dplyr::n_distinct(invoice),
    first_purchase = min(invoice_date, na.rm = TRUE),
    last_purchase  = max(invoice_date, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    repeat_customer = dplyr::if_else(total_orders > 1, 1L, 0L),
    customer_lifetime_days = as.integer(difftime(last_purchase, first_purchase, units = "days"))
  )

retail_features <- retail_features %>%
  dplyr::left_join(customer_features, by = "customer_id")

# -------------------------------
# 5) FINAL QA (light but meaningful)
# -------------------------------
stopifnot(all(retail_features$revenue > 0))
stopifnot(!any(is.na(retail_features$customer_id)))

cat("Rows (final features):", nrow(retail_features), "\n")
cat("Distinct customers:", dplyr::n_distinct(retail_features$customer_id), "\n")
cat("Distinct invoices:", dplyr::n_distinct(retail_features$invoice), "\n")

# -------------------------------
# 6) SAVE (single source of truth)
# -------------------------------
out_file <- file.path(data_processed, "retail_features.csv")
readr::write_csv(retail_features, out_file)

cat("Saved:", out_file, "\n")
