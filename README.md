# SQL Data Cleaning & Analysis Project

This repository contains a MySQL 8.0+ workflow for cleaning and analyzing a realistic but intentionally dirty e-commerce dataset. The project demonstrates common data-quality issues, remediation techniques, and business analysis using SQL.

## Overview

The script in `sql_data_cleaning_analysis.sql` does the following:

- Loads raw customer and order tables with deliberate inconsistencies
- Audits missing values, duplicates, invalid formats, and orphan records
- Normalizes names, phone numbers, cities, dates, and statuses
- Deduplicates records using window functions and rules
- Builds clean customer and order tables
- Produces analysis-ready views and quality summaries
- Runs sample analytical queries for revenue and customer behavior

## Included files

- `sql_data_cleaning_analysis.sql` — full SQL workflow for setup, auditing, cleaning, and analysis
- `make_shots.py` — Python script used to generate screenshots from the SQL script
- `screenshots/` — output images showing the SQL logic and query results

## What the project covers

- Duplicate customer detection and merging
- Phone/email normalization and validation
- Mixed date formats and parsing into valid `DATE` values
- Invalid quantity cleanup and null handling
- Orphan order detection
- Customer deduplication and canonical mapping
- Revenue, category performance, repeat purchase, and cohort-style analysis

## How to run

1. Make sure MySQL 8.0+ is installed.
2. Open a terminal in this project folder.
3. Run:

```bash
mysql -u <username> -p < sql_data_cleaning_analysis.sql
```

The script creates and uses the `demo_ecommerce` schema and is designed to be re-run safely.

## Example outputs

The repository includes visual screenshots under the `screenshots/` folder for:

- audit queries
- cleaning logic
- data quality report
- analysis results

## Notes

This is a portfolio-style SQL project focused on practical data cleaning and analytical SQL patterns. It is intended to show a real-world workflow for transforming dirty operational data into a clean analytical dataset.
