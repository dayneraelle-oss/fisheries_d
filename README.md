# Fisheries Data Warehouse

A PostgreSQL star-schema data warehouse for fish landing data. It contains a
complete ETL flow (staging -> cleaning -> dimensions -> fact), data quality
checks, star queries, and a Slowly Changing Dimension (SCD Type 2)
implementation for vessels.

## Repository structure

```
fisheries_d/
│
├── powerbi/
│   └── fisheries_dashboard.pbix
│
├── database/
│   └── schema.sql
│
├── screenshots/
│   └── dashboard.png
│
└── README.md
```

## Database

`database/schema.sql` creates a `dw` schema containing:

- **Staging:** `raw_landing`
- **Cleaning:** `clean_landing`, `rejected_landing` (audit trail for invalid rows)
- **Dimensions:** `dim_date`, `dim_port`, `dim_species`, `dim_vessel` (SCD Type 2)
- **Fact:** `fact_landing` (`total_value` is a generated column)

Each dimension has an `UNKNOWN` member with key `0` so that unresolved
references never break the load. The script also includes data profiling,
deduplication, quality checks, star queries, and an SCD Type 2 test that
verifies historical reports are unchanged.

## Getting started

Requirements:

- PostgreSQL 12 or newer (tested on 18)
- Power BI Desktop (for the dashboard)

Create a database and run the schema:

```bash
createdb fisheries
psql -U postgres -d fisheries -f database/schema.sql
```

The script runs in a single transaction and can be re-run safely; it drops and
recreates the `dw` schema each time.

## Power BI dashboard

Open `powerbi/fisheries_dashboard.pbix` in Power BI Desktop and point the
PostgreSQL connection to your local database. Use the tables in the `dw`
schema (`dim_*` and `fact_landing`).

## Screenshots

![Dashboard](screenshots/dashboard.png)

## Notes

The report file is `powerbi/fisheries_dashboard.pbix`. The dashboard screenshot
(`screenshots/dashboard.png`) still needs to be added.
