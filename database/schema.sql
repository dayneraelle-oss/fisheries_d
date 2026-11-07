-- fisheries db
-- 1. CREATE SCHEMA AND TABLES

DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;

CREATE TABLE dw.dim_date (
    date_key INTEGER PRIMARY KEY,
    full_date DATE UNIQUE NOT NULL,
    calendar_year INTEGER NOT NULL,
    month_number INTEGER NOT NULL,
    month_name VARCHAR(15) NOT NULL,
    day_of_month INTEGER NOT NULL
);

CREATE TABLE dw.dim_port (
    port_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    port_code VARCHAR(10) UNIQUE NOT NULL,
    port_name VARCHAR(100) NOT NULL,
    province VARCHAR(100) NOT NULL
);

CREATE TABLE dw.dim_species (
    species_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    species_code VARCHAR(10) UNIQUE NOT NULL,
    species_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL
);

CREATE TABLE dw.dim_vessel (
    vessel_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vessel_id VARCHAR(20) NOT NULL,
    vessel_name VARCHAR(100) NOT NULL,
    vessel_type VARCHAR(50) NOT NULL,
    cooperative VARCHAR(100) NOT NULL,
    effective_start DATE NOT NULL,
    effective_end DATE NOT NULL,
    is_current BOOLEAN NOT NULL
);

CREATE UNIQUE INDEX ux_dim_vessel_current
ON dw.dim_vessel(vessel_id)
WHERE is_current = TRUE;

CREATE TABLE dw.fact_landing (
    landing_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_key INTEGER NOT NULL REFERENCES dw.dim_date(date_key),
    port_key BIGINT NOT NULL REFERENCES dw.dim_port(port_key),
    species_key BIGINT NOT NULL REFERENCES dw.dim_species(species_key),
    vessel_key BIGINT NOT NULL REFERENCES dw.dim_vessel(vessel_key),
    kg NUMERIC(12,2) NOT NULL CHECK (kg > 0),
    price_per_kg NUMERIC(12,2) NOT NULL CHECK (price_per_kg > 0),
    total_value NUMERIC(14,2)
        GENERATED ALWAYS AS (kg * price_per_kg) STORED
);


-- 2. POPULATE DIM_DATE FOR 2020–2030
INSERT INTO dw.dim_date (
    date_key, full_date, calendar_year,
    month_number, month_name, day_of_month
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER,
    d::DATE,
    EXTRACT(YEAR FROM d)::INTEGER,
    EXTRACT(MONTH FROM d)::INTEGER,
    TO_CHAR(d, 'FMMonth'),
    EXTRACT(DAY FROM d)::INTEGER
FROM GENERATE_SERIES(
    DATE '2020-01-01',
    DATE '2030-12-31',
    INTERVAL '1 day'
) AS dates(d);


-- 3. INSERT SAMPLE DIMENSION ROWS
INSERT INTO dw.dim_port (port_code, port_name, province)
VALUES
    ('P001', 'Navotas Fish Port', 'Metro Manila'),
    ('P002', 'Batangas Fish Port', 'Batangas'),
    ('P003', 'Iloilo Fish Port', 'Iloilo'),
    ('P004', 'General Santos Fish Port', 'South Cotabato'),
    ('P005', 'Zamboanga Fish Port', 'Zamboanga');

INSERT INTO dw.dim_species (species_code, species_name, category)
VALUES
    ('S001', 'Galunggong', 'Marine'),
    ('S002', 'Bangus', 'Marine'),
    ('S003', 'Tilapia', 'Freshwater'),
    ('S004', 'Tuna', 'Marine'),
    ('S005', 'Sardines', 'Marine');

INSERT INTO dw.dim_vessel (
    vessel_id, vessel_name, vessel_type, cooperative,
    effective_start, effective_end, is_current
)
VALUES
    ('V001', 'MV San Isidro', 'Motorized', 'Bluewater Cooperative',
     DATE '2020-01-01', DATE '9999-12-31', TRUE),
    ('V002', 'MV Mabuhay', 'Motorized', 'Coastal Cooperative',
     DATE '2020-01-01', DATE '9999-12-31', TRUE),
    ('V003', 'MV Esperanza', 'Commercial', 'Bluewater Cooperative',
     DATE '2020-01-01', DATE '9999-12-31', TRUE),
    ('V004', 'MV Lapu-Lapu', 'Motorized', 'Southern Cooperative',
     DATE '2020-01-01', DATE '9999-12-31', TRUE),
    ('V005', 'MV Maria', 'Commercial', 'Coastal Cooperative',
     DATE '2020-01-01', DATE '9999-12-31', TRUE);


-- 4. INSERT 200 SAMPLE FACT ROWS
WITH numbered AS (
    SELECT
        n,
        DATE '2020-01-01'
        + ((n * 17) % (CURRENT_DATE - DATE '2020-01-01' + 1))
        AS landing_date
    FROM GENERATE_SERIES(1, 200) AS s(n)
),
ports AS (
    SELECT port_key,
           ROW_NUMBER() OVER (ORDER BY port_key) AS rn
    FROM dw.dim_port
),
species AS (
    SELECT species_key,
           ROW_NUMBER() OVER (ORDER BY species_key) AS rn
    FROM dw.dim_species
),
vessels AS (
    SELECT vessel_key,
           ROW_NUMBER() OVER (ORDER BY vessel_key) AS rn
    FROM dw.dim_vessel
    WHERE is_current = TRUE
)
INSERT INTO dw.fact_landing (
    date_key, port_key, species_key,
    vessel_key, kg, price_per_kg
)
SELECT
    d.date_key,
    p.port_key,
    s.species_key,
    v.vessel_key,
    (25 + ((n.n * 37) % 300))::NUMERIC(12,2),
    (50 + ((n.n * 13) % 80))::NUMERIC(12,2)
FROM numbered n
JOIN dw.dim_date d
    ON d.full_date = n.landing_date
JOIN ports p
    ON p.rn = ((n.n - 1) % (SELECT COUNT(*) FROM dw.dim_port)) + 1
JOIN species s
    ON s.rn = ((n.n - 1) % (SELECT COUNT(*) FROM dw.dim_species)) + 1
JOIN vessels v
    ON v.rn = ((n.n - 1) % (
        SELECT COUNT(*) FROM dw.dim_vessel WHERE is_current = TRUE
    )) + 1;


-- 5. STAR QUERY: KILOGRAMS PER MONTH
SELECT
    d.calendar_year,
    d.month_number,
    d.month_name,
    SUM(f.kg) AS total_kg
FROM dw.fact_landing f
JOIN dw.dim_date d ON d.date_key = f.date_key
GROUP BY d.calendar_year, d.month_number, d.month_name
ORDER BY d.calendar_year, d.month_number;


-- 6. STAR QUERY: TOP SPECIES PER PORT
WITH species_totals AS (
    SELECT
        p.port_name,
        s.species_name,
        SUM(f.kg) AS total_kg,
        RANK() OVER (
            PARTITION BY p.port_key
            ORDER BY SUM(f.kg) DESC
        ) AS species_rank
    FROM dw.fact_landing f
    JOIN dw.dim_port p ON p.port_key = f.port_key
    JOIN dw.dim_species s ON s.species_key = f.species_key
    GROUP BY p.port_key, p.port_name,
             s.species_key, s.species_name
)
SELECT port_name, species_name, total_kg
FROM species_totals
WHERE species_rank = 1
ORDER BY port_name;


-- 7. STAR QUERY: TOTAL VALUE PER COOPERATIVE
SELECT
    v.cooperative,
    SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY v.cooperative
ORDER BY total_value DESC;


-- 8. SAVE THE EXISTING REPORT BEFORE THE SCD TYPE 2 CHANGE
CREATE TEMP TABLE report_before AS
SELECT
    d.calendar_year,
    d.month_number,
    v.vessel_id,
    v.cooperative,
    SUM(f.kg) AS total_kg,
    SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_date d ON d.date_key = f.date_key
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY
    d.calendar_year, d.month_number,
    v.vessel_id, v.cooperative;


-- 9. IMPLEMENT SCD TYPE 2 FOR VESSEL V001
UPDATE dw.dim_vessel
SET
    effective_end = CURRENT_DATE - 1,
    is_current = FALSE
WHERE vessel_id = 'V001'
  AND is_current = TRUE;

INSERT INTO dw.dim_vessel (
    vessel_id, vessel_name, vessel_type, cooperative,
    effective_start, effective_end, is_current
)
SELECT
    vessel_id,
    vessel_name,
    vessel_type,
    'Northern Fisheries Cooperative',
    CURRENT_DATE,
    DATE '9999-12-31',
    TRUE
FROM dw.dim_vessel
WHERE vessel_id = 'V001'
  AND is_current = FALSE
  AND effective_end = CURRENT_DATE - 1;


-- 10. SAVE THE REPORT AFTER THE SCD TYPE 2 CHANGE
CREATE TEMP TABLE report_after AS
SELECT
    d.calendar_year,
    d.month_number,
    v.vessel_id,
    v.cooperative,
    SUM(f.kg) AS total_kg,
    SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_date d ON d.date_key = f.date_key
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY
    d.calendar_year, d.month_number,
    v.vessel_id, v.cooperative;


-- 11. VERIFY THAT OLD REPORTS ARE UNCHANGED
WITH differences AS (
    (SELECT * FROM report_before
     EXCEPT
     SELECT * FROM report_after)

    UNION ALL

    (SELECT * FROM report_after
     EXCEPT
     SELECT * FROM report_before)
)
SELECT
    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS: Old reports unchanged'
        ELSE 'FAIL: Old reports changed'
    END AS scd_type2_test,
    COUNT(*) AS difference_count
FROM differences;


-- 12. VERIFY THE VESSEL HISTORY
SELECT *
FROM dw.dim_vessel
WHERE vessel_id = 'V001'
ORDER BY effective_start;


-- 13. VERIFY THE NUMBER OF FACT ROWS
SELECT COUNT(*) AS fact_row_count
FROM dw.fact_landing;


-- =========================================================
-- ETL ACTIVITY: FISH LANDING DATA CLEANING AND DIMENSIONAL MODEL
-- =========================================================

DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;

-- reset session temp tables left by the previous activity
DROP TABLE IF EXISTS report_before;
DROP TABLE IF EXISTS report_after;

-- =========================
-- 1. RAW/STAGING TABLE
-- =========================
CREATE TABLE dw.raw_landing (
    landing_id           INTEGER,
    landing_date         DATE,
    port_code            VARCHAR(20),
    port_name            VARCHAR(100),
    province             VARCHAR(100),
    species_code         VARCHAR(20),
    species_name         VARCHAR(100),
    vessel_id            VARCHAR(30),
    vessel_name          VARCHAR(100),
    vessel_type          VARCHAR(50),
    cooperative          VARCHAR(100),
    kg                   NUMERIC(12,2),
    price_per_kg         NUMERIC(12,2)
);

-- =========================
-- 2. INSERT MESSY DATA
-- This data is intentionally dirty:
-- - missing values
-- - inconsistent casing
-- - duplicated rows
-- - extra spaces
-- - null prices
-- - spelling issues
-- =========================
INSERT INTO dw.raw_landing (
    landing_id, landing_date, port_code, port_name, province,
    species_code, species_name, vessel_id, vessel_name, vessel_type,
    cooperative, kg, price_per_kg
)
VALUES
    (1, '2020-01-05', 'P001', 'Navotas Fish Port', 'Metro Manila', 'S001', 'Galunggong', 'V001', 'MV San Isidro', 'Motorized', 'Bluewater Cooperative', 250.00, 55.00),
    (2, '2020-01-06', 'P001', ' Navotas Fish Port ', 'Metro Manila', 'S001', ' galunggong ', 'V001', 'MV San Isidro', 'Motorized', 'Bluewater Cooperative', 260.00, 55.00),
    (3, '2020-01-07', 'P002', 'Batangas Fish Port', 'Batangas', 'S002', 'Bangus', 'V002', 'MV Mabuhay', 'Motorized', 'Coastal Cooperative', 310.00, 60.00),
    (4, '2020-01-08', 'P002', 'Batangas Fish Port', 'Batangas', 'S002', 'BANGUS', 'V002', 'MV Mabuhay', 'Motorized', 'Coastal Cooperative', 315.00, 60.00),
    (5, '2020-01-09', 'P003', 'Iloilo Fish Port', 'Iloilo', 'S003', 'Tilapia', 'V003', 'MV Esperanza', 'Commercial', 'Bluewater Cooperative', 220.00, 48.00),
    (6, '2020-01-10', 'P003', 'Iloilo Fish Port', 'Iloilo', 'S005', 'Sardines', 'V004', 'MV Lapu-Lapu', 'Motorized', 'Southern Cooperative', 270.00, 52.00),
    (7, '2020-01-11', 'P004', 'General Santos Fish Port', 'South Cotabato', 'S004', 'Tuna', 'V005', 'MV Maria', 'Commercial', 'Coastal Cooperative', 420.00, 75.00),
    (8, '2020-01-12', 'P004', 'General Santos Fish Port', 'South Cotabato', 'S004', ' tuna ', 'V005', 'MV Maria', 'Commercial', 'Coastal Cooperative', 430.00, 75.00),
    (9, '2020-01-15', 'P005', 'Zamboanga Fish Port', 'Zamboanga', 'S005', 'Sardines', 'V001', 'MV San Isidro', 'Motorized', 'Bluewater Cooperative', 240.00, 50.00),
    (10, '2020-01-16', 'P005', 'Zamboanga Fish Port', 'Zamboanga', 'S003', 'Tilapia', 'V002', 'MV Mabuhay', 'Motorized', 'Coastal Cooperative', 230.00, 47.00),

    -- sample with missing values
    (11, NULL, 'P001', 'Navotas Fish Port', 'Metro Manila', 'S001', 'Galunggong', 'V001', 'MV San Isidro', 'Motorized', 'Bluewater Cooperative', NULL, 55.00),
    (12, '2020-02-01', NULL, 'Batangas Fish Port', 'Batangas', 'S002', 'Bangus', 'V002', 'MV Mabuhay', 'Motorized', 'Coastal Cooperative', 300.00, NULL),
    (13, '2020-02-02', 'P003', 'Iloilo Fish Port', 'Iloilo', 'S003', 'Tilapia', 'V003', 'MV Esperanza', 'Commercial', 'Bluewater Cooperative', 225.00, 47.00),
    (14, '2020-02-02', 'P003', 'Iloilo Fish Port', 'Iloilo', 'S003', 'Tilapia', 'V003', 'MV Esperanza', 'Commercial', 'Bluewater Cooperative', 225.00, 47.00), -- duplicate row
    (15, '2020-02-04', 'P004', 'General Santos Fish Port', 'South Cotabato', 'S004', 'Tuna', 'V005', 'MV Maria', 'Commercial', 'Coastal Cooperative', 440.00, 78.00),
    (16, '2020-02-05', 'P005', 'Zamboanga Fish Port', 'Zamboanga', 'S005', 'SARDINES', 'V004', 'MV Lapu-Lapu', 'Motorized', 'Southern Cooperative', 260.00, 51.00),
    (17, '2020-02-07', 'P001', 'Navotas Fish Port', 'Metro Manila', 'S001', 'Galunggong', 'V004', 'MV Lapu-Lapu', 'Motorized', 'Southern Cooperative', 285.00, 57.00),
    (18, '2020-02-08', 'P002', 'Batangas Fish Port', 'Batangas', 'S002', 'Bangus', 'V005', 'MV Maria', 'Commercial', 'Coastal Cooperative', 330.00, 62.00),
    (19, '2020-02-09', 'P003', 'Iloilo Fish Port', 'Iloilo', 'S003', 'TILAPIA', 'V003', 'MV Esperanza', 'Commercial', 'Bluewater Cooperative', 200.00, 45.00),
    (20, '2020-02-11', 'P005', 'Zamboanga Fish Port', 'Zamboanga', 'S005', 'Sardines', 'V001', 'MV San Isidro', 'Motorized', 'Bluewater Cooperative', 245.00, 49.00);

-- =========================
-- 3. DATA PROFILE
-- Check missing values and duplicates
-- =========================
SELECT
    'landing_date' AS column_name,
    COUNT(*) AS total_rows,
    COUNT(landing_date) AS non_null_count,
    COUNT(*) - COUNT(landing_date) AS missing_count
FROM dw.raw_landing

UNION ALL

SELECT
    'port_code',
    COUNT(*),
    COUNT(port_code),
    COUNT(*) - COUNT(port_code)
FROM dw.raw_landing

UNION ALL

SELECT
    'species_name',
    COUNT(*),
    COUNT(species_name),
    COUNT(*) - COUNT(species_name)
FROM dw.raw_landing

UNION ALL

SELECT
    'kg',
    COUNT(*),
    COUNT(kg),
    COUNT(*) - COUNT(kg)
FROM dw.raw_landing

UNION ALL

SELECT
    'price_per_kg',
    COUNT(*),
    COUNT(price_per_kg),
    COUNT(*) - COUNT(price_per_kg)
FROM dw.raw_landing;

-- duplicate check
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT landing_id) AS unique_landing_ids,
    COUNT(*) - COUNT(DISTINCT landing_id) AS duplicate_rows
FROM dw.raw_landing;

-- species inconsistency check
SELECT
    TRIM(LOWER(species_name)) AS normalized_species,
    COUNT(*) AS frequency
FROM dw.raw_landing
WHERE species_name IS NOT NULL
GROUP BY TRIM(LOWER(species_name))
ORDER BY frequency DESC;

-- =========================
-- 4. CLEANING
-- Create cleaned staging table
-- =========================
CREATE TABLE dw.clean_landing AS
SELECT
    landing_id,
    landing_date,
    TRIM(port_code) AS port_code,
    TRIM(port_name) AS port_name,
    TRIM(province) AS province,
    TRIM(species_code) AS species_code,
    CASE
        WHEN species_name IS NULL THEN 'UNKNOWN'
        ELSE INITCAP(TRIM(species_name))
    END AS species_name,
    TRIM(vessel_id) AS vessel_id,
    TRIM(vessel_name) AS vessel_name,
    TRIM(vessel_type) AS vessel_type,
    TRIM(cooperative) AS cooperative,
    CASE
        WHEN kg IS NULL THEN 0
        ELSE kg
    END AS kg,
    CASE
        WHEN price_per_kg IS NULL THEN 0
        ELSE price_per_kg
    END AS price_per_kg
FROM dw.raw_landing;

-- remove duplicates based on all important fields
CREATE TABLE dw.clean_landing_no_dups AS
SELECT DISTINCT *
FROM dw.clean_landing;

-- normalize inconsistent text values
UPDATE dw.clean_landing_no_dups
SET
    species_name = CASE
        WHEN LOWER(species_name) IN ('galunggong', 'galunggong') THEN 'Galunggong'
        WHEN LOWER(species_name) = 'bangus' THEN 'Bangus'
        WHEN LOWER(species_name) = 'tilapia' THEN 'Tilapia'
        WHEN LOWER(species_name) = 'tuna' THEN 'Tuna'
        WHEN LOWER(species_name) = 'sardines' THEN 'Sardines'
        ELSE species_name
    END,
    port_name = CASE
        WHEN port_name IS NULL THEN 'UNKNOWN'
        ELSE TRIM(port_name)
    END,
    province = CASE
        WHEN province IS NULL THEN 'UNKNOWN'
        ELSE TRIM(province)
    END,
    vessel_type = CASE
        WHEN vessel_type IS NULL THEN 'UNKNOWN'
        ELSE TRIM(vessel_type)
    END,
    cooperative = CASE
        WHEN cooperative IS NULL THEN 'UNKNOWN'
        ELSE TRIM(cooperative)
    END;

-- standardize null dates
UPDATE dw.clean_landing_no_dups
SET landing_date = '2020-01-01'
WHERE landing_date IS NULL;

-- standardize zero values as null or keep them if needed
-- For the ETL we can keep zero, since it is numeric
SELECT * FROM dw.clean_landing_no_dups ORDER BY landing_id;

-- =========================
-- 5. CREATE DIMENSIONS AND FACT TABLE
-- =========================
CREATE TABLE dw.dim_date (
    date_key INTEGER PRIMARY KEY,
    full_date DATE UNIQUE NOT NULL,
    calendar_year INTEGER NOT NULL,
    month_number INTEGER NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    day_of_month INTEGER NOT NULL
);

CREATE TABLE dw.dim_port (
    port_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    port_code VARCHAR(20) UNIQUE NOT NULL,
    port_name VARCHAR(100) NOT NULL,
    province VARCHAR(100) NOT NULL
);

CREATE TABLE dw.dim_species (
    species_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    species_code VARCHAR(20) UNIQUE NOT NULL,
    species_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL
);

CREATE TABLE dw.dim_vessel (
    vessel_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vessel_id VARCHAR(30) NOT NULL,
    vessel_name VARCHAR(100) NOT NULL,
    vessel_type VARCHAR(50) NOT NULL,
    cooperative VARCHAR(100) NOT NULL,
    effective_start DATE NOT NULL,
    effective_end DATE NOT NULL,
    is_current BOOLEAN NOT NULL
);

CREATE UNIQUE INDEX ux_dim_vessel_current
ON dw.dim_vessel(vessel_id)
WHERE is_current = TRUE;

CREATE TABLE dw.fact_landing (
    landing_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_key INTEGER NOT NULL REFERENCES dw.dim_date(date_key),
    port_key BIGINT NOT NULL REFERENCES dw.dim_port(port_key),
    species_key BIGINT NOT NULL REFERENCES dw.dim_species(species_key),
    vessel_key BIGINT NOT NULL REFERENCES dw.dim_vessel(vessel_key),
    kg NUMERIC(12,2) NOT NULL CHECK (kg >= 0),
    price_per_kg NUMERIC(12,2) NOT NULL CHECK (price_per_kg >= 0),
    total_value NUMERIC(14,2)
);

-- =========================
-- 6. POPULATE DIM_DATE
-- =========================
INSERT INTO dw.dim_date (
    date_key, full_date, calendar_year,
    month_number, month_name, day_of_month
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER,
    d::DATE,
    EXTRACT(YEAR FROM d)::INTEGER,
    EXTRACT(MONTH FROM d)::INTEGER,
    TO_CHAR(d, 'Month'),
    EXTRACT(DAY FROM d)::INTEGER
FROM GENERATE_SERIES(
    DATE '2020-01-01',
    DATE '2030-12-31',
    INTERVAL '1 day'
) AS dates(d);

-- =========================
-- 7. LOAD DIMENSION TABLES
-- =========================
INSERT INTO dw.dim_port (port_code, port_name, province)
SELECT DISTINCT
    port_code,
    port_name,
    province
FROM dw.clean_landing_no_dups
WHERE port_code IS NOT NULL
ORDER BY port_code;

INSERT INTO dw.dim_species (species_code, species_name, category)
SELECT DISTINCT
    species_code,
    species_name,
    CASE
        WHEN LOWER(species_name) IN ('galunggong', 'bangus', 'tuna', 'sardines') THEN 'Marine'
        WHEN LOWER(species_name) = 'tilapia' THEN 'Freshwater'
        ELSE 'Unknown'
    END AS category
FROM dw.clean_landing_no_dups
WHERE species_code IS NOT NULL
ORDER BY species_code;

INSERT INTO dw.dim_vessel (
    vessel_id, vessel_name, vessel_type, cooperative,
    effective_start, effective_end, is_current
)
SELECT DISTINCT
    vessel_id,
    vessel_name,
    vessel_type,
    cooperative,
    DATE '2020-01-01',
    DATE '9999-12-31',
    TRUE
FROM dw.clean_landing_no_dups
WHERE vessel_id IS NOT NULL
ORDER BY vessel_id;

-- =========================
-- 8. FACT TABLE LOAD
-- =========================
INSERT INTO dw.fact_landing (
    date_key, port_key, species_key, vessel_key,
    kg, price_per_kg, total_value
)
SELECT
    d.date_key,
    p.port_key,
    s.species_key,
    v.vessel_key,
    c.kg,
    c.price_per_kg,
    (c.kg * c.price_per_kg) AS total_value
FROM dw.clean_landing_no_dups c
JOIN dw.dim_date d
    ON d.full_date = c.landing_date
JOIN dw.dim_port p
    ON p.port_code = c.port_code
JOIN dw.dim_species s
    ON s.species_code = c.species_code
JOIN dw.dim_vessel v
    ON v.vessel_id = c.vessel_id
WHERE c.kg > 0
  AND c.price_per_kg > 0;

-- =========================
-- 9. DATA QUALITY CHECKS
-- =========================
SELECT
    'missing_dates' AS check_name,
    COUNT(*) AS result
FROM dw.clean_landing_no_dups
WHERE landing_date IS NULL

UNION ALL

SELECT
    'duplicate_rows',
    COUNT(*)
FROM (
    SELECT landing_id, landing_date, port_code, species_code, vessel_id, kg, price_per_kg
    FROM dw.clean_landing_no_dups
    GROUP BY landing_id, landing_date, port_code, species_code, vessel_id, kg, price_per_kg
    HAVING COUNT(*) > 1
) x

UNION ALL

SELECT
    'species_variations',
    COUNT(DISTINCT species_name)
FROM dw.clean_landing_no_dups;

-- =========================
-- 10. STAR QUERIES
-- =========================

-- total kilograms by year and month
SELECT
    d.calendar_year,
    d.month_number,
    d.month_name,
    SUM(f.kg) AS total_kg
FROM dw.fact_landing f
JOIN dw.dim_date d ON d.date_key = f.date_key
GROUP BY d.calendar_year, d.month_number, d.month_name
ORDER BY d.calendar_year, d.month_number;

-- top species by port
SELECT
    p.port_name,
    s.species_name,
    SUM(f.kg) AS total_kg
FROM dw.fact_landing f
JOIN dw.dim_port p ON p.port_key = f.port_key
JOIN dw.dim_species s ON s.species_key = f.species_key
GROUP BY p.port_name, s.species_name
ORDER BY p.port_name, total_kg DESC;

-- total value by cooperative
SELECT
    v.cooperative,
    SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY v.cooperative
ORDER BY total_value DESC;

-- =========================
-- 11. REPORT BEFORE SCD TYPE 2 CHANGE
-- =========================
CREATE TEMP TABLE report_before AS
SELECT
    d.calendar_year,
    d.month_number,
    v.vessel_id,
    v.cooperative,
    SUM(f.kg) AS total_kg,
    SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_date d ON d.date_key = f.date_key
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY d.calendar_year, d.month_number, v.vessel_id, v.cooperative;

-- =========================
-- 12. SCD TYPE 2 CHANGE
-- Change vessel V001 cooperative from Bluewater to Northern Fisheries
-- =========================
UPDATE dw.dim_vessel
SET
    effective_end = CURRENT_DATE - 1,
    is_current = FALSE
WHERE vessel_id = 'V001'
  AND is_current = TRUE;

INSERT INTO dw.dim_vessel (
    vessel_id, vessel_name, vessel_type, cooperative,
    effective_start, effective_end, is_current
)
VALUES
    ('V001', 'MV San Isidro', 'Motorized', 'Northern Fisheries Cooperative',
     CURRENT_DATE, DATE '9999-12-31', TRUE);

-- =========================
-- 13. REPORT AFTER SCD TYPE 2 CHANGE
-- =========================
CREATE TEMP TABLE report_after AS
SELECT
    d.calendar_year,
    d.month_number,
    v.vessel_id,
    v.cooperative,
    SUM(f.kg) AS total_kg,
    SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_date d ON d.date_key = f.date_key
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY d.calendar_year, d.month_number, v.vessel_id, v.cooperative;

-- =========================
-- 14. VERIFY SCD TYPE 2 HISTORY
-- =========================
SELECT *
FROM dw.dim_vessel
WHERE vessel_id = 'V001'
ORDER BY effective_start;

-- check if old reports changed
WITH differences AS (
    (SELECT * FROM report_before
     EXCEPT
     SELECT * FROM report_after)

    UNION ALL

    (SELECT * FROM report_after
     EXCEPT
     SELECT * FROM report_before)
)
SELECT
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS: Old reports unchanged'
        ELSE 'FAIL: Old reports changed'
    END AS scd_type2_test,
    COUNT(*) AS difference_count
FROM differences;