# author: John.Inman@waterboards.ca.gov with AI coding agent
# model: deepseek/deepseek-v4-flash
# date updated: 2026-09-10

# ---------------------------------------------------------------------------
# build_ref_index.R
#
# PURPOSE:
#   1. Extract reference numbers from the "Data Used to Assess Water Quality
#      References" column of the Comprehensive Report (a tab-delimited text
#      export from the Integrated Report database).
#   2. Find the corresponding files on the S: drive (pre-indexed in
#      sdrive-paths.csv) whose names match /ref<number>.<ext>.
#   3. Copy those files into a local directory tree that mirrors the
#      S: drive folder structure.
#
# The S: drive file list was generated once (offline) because the network
# share may not be available during every run.  See build_sdrive_index().
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
    library(tidyverse)
    library(fs)
    library(data.table)
})

# -- Configuration -----------------------------------------------------------

report_file  <- "resources/ComprehensiveReportTab.txt"
sdrive_file  <- "resources/sdrive-paths.csv"
output_file  <- "ref_index.csv"

sdrive_root  <- "S:/DWQ/DIV/WQSA/Integrated Report"
local_root   <- "sdrive-mirror"

# -- Helpers -----------------------------------------------------------------

# Build the S: drive file index (run once when the share is mounted).
# Returns a tibble with a single column, `path`.
build_sdrive_index <- function(root = sdrive_root,
                               outfile = sdrive_file) {
    dir_ls(root, recurse = TRUE, type = "file") |>
        as_tibble_col(column_name = "path") |>
        fwrite(outfile)
    invisible()
}

# -- Step 1: Extract reference numbers from the report ----------------------

report_raw <- fread(
    report_file,
    sep      = "\t",
    header   = TRUE,
    quote    = "\"",
    colClasses = "character",
    na.strings = ""
) |>
    as_tibble()

# The reference column holds comma-separated numbers (e.g., "11", "6244,4923").
reference_numbers <- report_raw |>
    select(ref_number = `Data Used to Assess Water Quality References`) |>
    filter(!is.na(ref_number), ref_number != "") |>
    separate_longer_delim(ref_number, ", ") |>
    distinct(ref_number)

# -- Step 2: Load the pre-built S: drive index ------------------------------

sdrive_paths <- fread(sdrive_file, sep = ",") |>
    as_tibble()

# -- Step 3: Match references to files on the S: drive ----------------------
#
# File names on the S: drive follow the convention /ref<number>.<ext>
# (e.g.,   .../some/path/ref5891.xlsx).  We extract the numeric portion and
# join against the report's reference numbers.

ref_index <- sdrive_paths |>
    mutate(ref_number = str_extract(
        str_to_lower(path),           # case-insensitive match
        "/ref(\\d+)\\.\\w+$",
        group = 1
    )) |>
    filter(!is.na(ref_number)) |>
    semi_join(reference_numbers, by = "ref_number")

# -- Step 4: Copy matched files into the local refs/ tree -------------------
#
# For each matched file:
#   - Create the destination directory under refs/ (mirroring S: drive path)
#   - Copy the file, overwriting any previous copy

ref_index |>
  mutate(
          src  = path,
          dest = str_replace(path, sdrive_root, local_root)
          ) |>
  pwalk(function(src, dest, ...) {
          dir_create(path_dir(dest))
          # file.copy has copy.date arg to keep mtime
          if (!file_exists(dest)) file.copy(src, dest, copy.date = TRUE)
          })

ref_index |>
  mutate(
          src  = path,
          dest = str_replace(path, sdrive_root, local_root)
          ) |>
  pwalk(function(src, dest, ...) {
          Sys.setFileTime(dest, file_info(src)$modification_time)
          })


# -- Step 5: Write ref index ------------------------------------------------
# fwrite(ref_index, outfile)
