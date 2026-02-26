############################################################
# Project: Revenue Optimization & Customer Behavior Analytics
# File: 00_setup.R
# Purpose: Initialize reproducible analytical environment
############################################################

# -------------------------------
# 1. Clear Environment
# -------------------------------
rm(list = ls())
gc()

# -------------------------------
# 2. Global Options
# -------------------------------
options(
  scipen = 999,        # disable scientific notation
  stringsAsFactors = FALSE
)

# -------------------------------
# 3. Set Random Seed
# -------------------------------
set.seed(1234)

# -------------------------------
# 4. Load Required Packages
# -------------------------------

required_packages <- c(
  "tidyverse",
  "lubridate",
  "readr",
  "janitor",
  "broom",
  "ggplot2",
  "car",
  "MASS",
  "scales",
  "patchwork"
)

# Install missing packages automatically
installed <- rownames(installed.packages())

for(pkg in required_packages){
  if(!(pkg %in% installed)){
    install.packages(pkg)
  }
}

# Load libraries
lapply(required_packages, library, character.only = TRUE)

# -------------------------------
# 5. Define Project Paths
# -------------------------------

project_root <- here::here()

data_raw <- file.path(project_root, "data", "raw")
data_processed <- file.path(project_root, "data", "processed")

scripts_path <- file.path(project_root, "scripts")
output_path <- file.path(project_root, "outputs")
reports_path <- file.path(project_root, "reports")

# -------------------------------
# 6. Create Missing Folders
# -------------------------------

dirs <- c(
  data_processed,
  output_path,
  reports_path
)

for(d in dirs){
  if(!dir.exists(d)){
    dir.create(d, recursive = TRUE)
  }
}

# -------------------------------
# 7. Session Information
# -------------------------------
cat("Environment successfully initialized\n")
cat("Project Root:", project_root, "\n")
cat("Loaded Packages:", paste(required_packages, collapse=", "), "\n")

############################################################
# END OF SETUP
############################################################
