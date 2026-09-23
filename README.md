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

### Option 1: MySQL or MariaDB locally

1. Start a local MySQL/MariaDB server.
2. Open PowerShell in this project folder.
3. Add the database client to `PATH` if needed.
4. Run the script:

```powershell
$env:Path += ";C:\Program Files\MariaDB 13.0\bin"
Get-Content .\sql_data_cleaning_analysis.sql | mariadb --batch --skip-column-names -u root
```

If you are using MySQL instead of MariaDB, replace the path with your MySQL install, for example:

```powershell
$env:Path += ";C:\Program Files\MySQL\MySQL Server 8.4\bin"
Get-Content .\sql_data_cleaning_analysis.sql | mysql -u root -p
```

The script creates and uses the `demo_ecommerce` schema and is designed to be re-run safely.

### Option 2: Generate the project screenshots

From the project directory:

```powershell
python .\make_shots.py
```

This regenerates the PNG files under the `screenshots/` folder.

## Example outputs

The repository includes visual screenshots under the `screenshots/` folder for:

- audit queries
- cleaning logic
- data quality report
- analysis results

## Notes

This is a portfolio-style SQL project focused on practical data cleaning and analytical SQL patterns. It is intended to show a real-world workflow for transforming dirty operational data into a clean analytical dataset.
