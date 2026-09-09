# author: John.Inman@waterboards.ca.gov with AI coding agent
# model: deepseek/deepseek-v4-flash
# date updated: 2026-09-09
#
# build_ref_index.R
#
# Reads the Comprehensive Report, extracts unique reference numbers from column 51 ("Data Used to Assess Water Quality References"), and for
# each ref number:
#   1. Checks waterboards-website-links.txt for a matching URL.
#   2. If URL exists and is a working link (HTTP 200), uses the URL.
#   3. Otherwise falls back to s-drive-paths.txt, applying rules:
#      prefer paths starting with ^References/, then prefer .zip files.
#      No other exclusions. Multiple candidates after these rules are
#      reported rather than silently tiebroken.
#
# Output: ./ref_index.csv with columns: ref_number, source
# Refs are downloaded/copied to ./refs/<ref_number>/original/; zip
# archives are extracted to ./refs/<ref_number>/extracted/.
# For refs with tied s-drive candidates, the first is used in output
# but all are reported in the console.

suppressPackageStartupMessages({
    library(dplyr)
    library(tidyr)
    library(stringr)
    library(purrr)
    library(fs)
    library(data.table)
    library(curl)
})

report_file     <- "resources/ComprehensiveReportTab.txt"
website_file    <- "resources/waterboards-website-links.txt"
sdrive_file     <- "resources/s-drive-paths.txt"
output_file     <- "ref_index.csv"
sdrive_prefix   <- "S:/DWQ/DIV/WQSA/Integrated Report"

# ---- 1. Get ref numbers in comp report ----
if (!exists(".report")) {
        .report <- fread(report_file, 
                         sep = "\t", 
                         header = TRUE, 
                         quote = "\"",
                         colClasses = "character", 
                         na.strings = "") |>
        as_tibble()
}

comp_refs <- .report  |>
    select(ref_number = `Data Used to Assess Water Quality References`) |>
    filter(!is.na(ref_number), ref_number != "") |>
    separate_longer_delim(ref_number, ", ") |>
    distinct(ref_number)

# ---- 2. Get ref urls on website ----
website_refs <- 
    tibble(source = readLines(website_file, warn = FALSE)) |>
    mutate(ref_number = str_extract(source, "/ref(\\d+)\\.\\w+$", group = 1)) |>
    group_by(ref_number) |>
    slice_head(n = 1) |>
    ungroup() |>
    # Only download refs that actually appear in the report.
    inner_join(comp_refs, by = "ref_number")

# ---- 3. Download refs ----

dest_dir <- path("refs", "original")
dir_create(dest_dir)
dest_files <- path(dest_dir, path_file(website_refs$source))

results <- multi_download(
    urls = website_refs$source,
    destfiles = dest_files,
    resume = TRUE,
    progress = TRUE
)

downloaded_files <- 
    tibble(file = dir_ls("./refs", recurse = TRUE, type = "file")) |>
    mutate(ref_number = str_extract(file, "/ref(\\d+)\\.\\w+$", group = 1),
           size = file_info(file)$size) |>
    filter(size > 0)

# only keep refs that actually downloaded (they all did)
website_refs <- semi_join(website_refs, downloaded_files, by = "ref_number")

# ---- 4. Build s-drive paths fallback ----

# Build best path per ref:
#   1. Prefer paths starting with ^References/
#   2. Prefer .zip files over other extensions
#   3. Remaining ties broken by taking first option (original file order).
select_best_path <- function(df) {
  # Does any path start with "References/"?
  has_ref_path <- any(str_detect(df$source, "^References/"))
  if (has_ref_path) {
    df <- df |> 
        filter(str_detect(source, "^References/"))
  }
  has_zip <- any(str_detect(df$source, "zip"))
  if (has_zip) {
    df <- df |> 
        filter(str_detect(source, "zip"))
  }
  # take the first of remaining rows (original file order).
  df |>  
      slice_head(n = 1)
}

# Pattern: path ending with /ref{NNNN}.{ext} (case-insensitive)
sdrive_refs <- 
    tibble(source = readLines(sdrive_file, warn = FALSE)) |>
    mutate(ref_number = str_extract(source, "/ref(\\d+)\\.\\w+$", group = 1)) |>
    filter(!is.na(ref_number)) |>
    group_by(ref_number) |>
    group_modify(\(x, ...) select_best_path(x)) |>
    ungroup() |>
    mutate(source = path(sdrive_prefix, source)) |>
    inner_join(comp_refs, by = "ref_number") |>
    anti_join(website_refs, by = "ref_number")

select(sdrive_refs, path = source) |> 
mutate(new_path = path("refs", "original", path_file(path))) |>
pmap(file_copy)
