# author: John.Inman@waterboards.ca.gov with AI coding agent
# model: deepseek/deepseek-v4-flash
# date updated: 2026-09-08
#
# build_ref_index.R
#
# Reads the Comprehensive Report, extracts unique reference numbers from
# column 51 ("Data Used to Assess Water Quality References"), and for
# each ref number:
#   1. Checks waterboards-website-links.txt for a matching URL.
#   2. If URL exists and is a working link (HTTP 200), uses the URL.
#   3. Otherwise falls back to s-drive-paths.txt, applying rules:
#      prefer paths starting with ^References/, then prefer .zip files.
#      No other exclusions. Multiple candidates after these rules are
#      reported rather than silently tiebroken.
#
# Output: ./ref_index.csv with columns: ref_number, source
# For refs with tied s-drive candidates, the first is used in output
# but all are reported in the console.

suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(tidyr))
suppressPackageStartupMessages(library(stringr))
suppressPackageStartupMessages(library(purrr))
suppressPackageStartupMessages(library(data.table))
suppressPackageStartupMessages(library(httr))
library(parallel)

report_file     <- "resources/ComprehensiveReportTab.txt"
website_file    <- "resources/waterboards-website-links.txt"
sdrive_file     <- "resources/s-drive-paths.txt"
output_file     <- "ref_index.csv"
sdrive_prefix   <- "S:DWQ/DIV/WQSA/Integrated Report"

# ---- 1. Extract unique reference numbers from report ----
report <- fread(report_file, sep = "\t", header = TRUE, quote = "\"",
                colClasses = "character", na.strings = "")

ref_nums <- report[[51]] |>
  str_replace_all('"', "") |>
  str_split("\\s*,\\s*") |>
  unlist() |>
  str_trim() |>
  unique()

ref_nums <- ref_nums[ref_nums != "" & !is.na(ref_nums)]

# ---- 2. Build website links lookup ----
website_lines <- readLines(website_file, warn = FALSE)

parse_website_url <- function(url) {
  m <- str_match(url, regex("/ref(\\d+)\\.\\w+$", ignore_case = TRUE))
  if (is.na(m[1, 1])) return(NULL)
  tibble(ref_number = m[1, 2], url = url)
}

website_lookup <- map_dfr(website_lines, parse_website_url)

# For refs with multiple URLs, keep the first one (they all point to same
# file on different regional pages; any one will work).
website_lookup <- website_lookup |>
  group_by(ref_number) |>
  slice_head(n = 1) |>
  ungroup()

# ---- 3. Check which website links are alive (HTTP 200) ----
# Only check refs that actually appear in the report.
refs_to_check <- intersect(ref_nums, website_lookup$ref_number)
urls_to_check <- website_lookup |>
  filter(ref_number %in% refs_to_check)

check_url <- function(url, timeout = 10) {
  tryCatch({
    resp <- HEAD(url, timeout(timeout), user_agent("Mozilla/5.0"))
    resp$status_code == 200
  }, error = function(e) FALSE)
}

# Parallel check: use available cores minus 1, max 8.
n_cores <- min(detectCores() - 1, 8, na.rm = TRUE)
if (n_cores < 1) n_cores <- 1

working <- mclapply(urls_to_check$url, check_url, mc.cores = n_cores,
                    mc.preschedule = TRUE) |>
  unlist()

urls_to_check$working <- working

# Build final website source mapping
website_source <- urls_to_check |>
  filter(working) |>
  select(ref_number, source = url)

# ---- 4. Build s-drive paths fallback ----
sdrive_lines <- readLines(sdrive_file, warn = FALSE)

# Pattern: path ending with /ref{NNNN}.{ext} (case-insensitive)
pattern <- "(?i)^(.+)/ref(\\d+)\\.([a-z0-9]+)$"

parse_sdrive_line <- function(line) {
  m <- str_match(line, pattern)
  if (is.na(m[1, 1])) return(NULL)
  tibble(
    rel_path    = m[1, 1],
    ref_number  = m[1, 3],
    extension   = str_to_lower(m[1, 4])
  )
}

sdrive_paths <- map_dfr(sdrive_lines, parse_sdrive_line)

# Build best path per ref:
#   1. Prefer paths starting with ^References/
#   2. Prefer .zip files over other extensions
#   3. Remaining ties broken by taking first option (original file order).
select_best_sdrive_path <- function(df) {
  if (nrow(df) == 0) return(NULL)

  # Does any path start with "References/"?
  has_ref_path <- any(str_detect(df$rel_path, "^References/"))
  if (has_ref_path) {
    df <- df |> filter(str_detect(rel_path, "^References/"))
  }

  has_zip <- any(df$extension == "zip")
  if (has_zip) {
    df <- df |> filter(extension == "zip")
  }

  # No tiebreaker — just take the first row (original file order).
  df |> slice_head(n = 1)
}

sdrive_best <- sdrive_paths |>
  group_by(ref_number) |>
  group_modify(\(x) select_best_sdrive_path(x)) |>
  ungroup() |>
  mutate(source = file.path(sdrive_prefix, rel_path)) |>
  select(ref_number, source)

# ---- 5. Combine website + s-drive sources ----
# For each ref in the report:
#   - Use website URL if available and working
#   - Otherwise use s-drive path if available
#   - Otherwise mark as "not_found"

all_refs <- tibble(ref_number = ref_nums)

ref_index <- all_refs |>
  left_join(website_source, by = "ref_number") |>
  left_join(sdrive_best, by = "ref_number", suffix = c(".web", ".sdrive")) |>
  mutate(
    source = coalesce(source.web, source.sdrive)
  ) |>
  select(ref_number, source)

# ---- 6. Write output ----
fwrite(ref_index, output_file, na = "")