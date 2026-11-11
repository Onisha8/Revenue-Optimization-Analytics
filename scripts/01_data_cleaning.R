source("00_setup.R")
library(readxl)

# 1) Load both sheets (Dec 2009 - Dec 2011)
# The sheets overlap on 1-9 Dec 2010, so that window is taken from the
# 2010-2011 sheet only to avoid double counting invoices
raw_file <- file.path(data_raw, "online_retail_II.xlsx")

retail_2009_2010 <- read_excel(raw_file, sheet = "Year 2009-2010") %>%
  dplyr::filter(InvoiceDate < as.POSIXct("2010-12-01", tz = "UTC"))

retail_2010_2011 <- read_excel(raw_file, sheet = "Year 2010-2011")

retail_raw <- dplyr::bind_rows(retail_2009_2010, retail_2010_2011)

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
