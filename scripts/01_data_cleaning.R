source("scripts/00_setup.R")
library(readxl)

# 1) Load
retail_raw <- read_excel(
  file.path(data_raw, "online_retail_II.xlsx"),
  sheet = "Year 2010-2011"
)

# 2) Clean + business rules + features (single pipeline)
retail_features <- retail_raw %>%
  janitor::clean_names() %>%                     # standardize names
  dplyr::filter(!is.na(customer_id)) %>%         # keep usable customer rows
  dplyr::filter(!stringr::str_starts(invoice, "C")) %>%  # remove cancellations
  dplyr::filter(quantity > 0, price > 0) %>%     # remove invalid values
  dplyr::mutate(
    invoice_date = lubridate::as_datetime(invoice_date),
    revenue = quantity * price,
    month_year = lubridate::floor_date(invoice_date, "month")
  )

# 3) Customer features (small + useful)
customer_features <- retail_features %>%
  dplyr::group_by(customer_id) %>%
  dplyr::summarise(
    total_orders = dplyr::n_distinct(invoice),
    .groups = "drop"
  ) %>%
  dplyr::mutate(repeat_customer = dplyr::if_else(total_orders > 1, 1L, 0L))

retail_features <- retail_features %>%
  dplyr::left_join(customer_features, by = "customer_id")

# 4) Save processed dataset
readr::write_csv(
  retail_features,
  file.path(data_processed, "retail_features.csv")
)

cat("Saved cleaned dataset to data/processed/retail_features.csv\n")
