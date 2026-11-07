-- =========================================================
-- FISHERIES ETL + DIMENSIONAL MODEL (consolidated)
-- Target: PostgreSQL
-- Single flow: staging -> profiling -> cleaning -> dimensions -> fact -> checks -> star queries -> SCD2
-- =========================================================

BEGIN;

DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;

-- =========================
-- 1. RAW / STAGING TABLE
-- =========================
CREATE TABLE dw.raw_landing (
    landing_id    INTEGER,
    landing_date  DATE,
    port_code     VARCHAR(20),
    port_name     VARCHAR(100),
    province      VARCHAR(100),
    species_code  VARCHAR(20),
    species_name  VARCHAR(100),
    vessel_id     VARCHAR(30),
    vessel_name   VARCHAR(100),
    vessel_type   VARCHAR(50),
    cooperative   VARCHAR(100),
    kg            NUMERIC(12,2),
    price_per_kg  NUMERIC(12,2)
);

-- =========================
-- 2. MESSY SAMPLE DATA
-- =========================
INSERT INTO dw.raw_landing (
    landing_id, landing_date, port_code, port_name, province,
    species_code, species_name, vessel_id, vessel_name, vessel_type,
    cooperative, kg, price_per_kg
)
VALUES
    (1,  '2020-01-05', 'P001', 'Navotas Fish Port',         'Metro Manila',  'S001', 'Galunggong', 'V001', 'MV San Isidro', 'Motorized',  'Bluewater Cooperative', 250.00, 55.00),
    (2,  '2020-01-06', 'P001', ' Navotas Fish Port ',       'Metro Manila',  'S001', ' galunggong ', 'V001', 'MV San Isidro', 'Motorized', 'Bluewater Cooperative', 260.00, 55.00),
    (3,  '2020-01-07', 'P002', 'Batangas Fish Port',        'Batangas',      'S002', 'Bangus',      'V002', 'MV Mabuhay',    'Motorized',  'Coastal Cooperative',   310.00, 60.00),
    (4,  '2020-01-08', 'P002', 'Batangas Fish Port',        'Batangas',      'S002', 'BANGUS',      'V002', 'MV Mabuhay',    'Motorized',  'Coastal Cooperative',   315.00, 60.00),
    (5,  '2020-01-09', 'P003', 'Iloilo Fish Port',          'Iloilo',        'S003', 'Tilapia',     'V003', 'MV Esperanza',  'Commercial', 'Bluewater Cooperative', 220.00, 48.00),
    (6,  '2020-01-10', 'P003', 'Iloilo Fish Port',          'Iloilo',        'S005', 'Sardines',    'V004', 'MV Lapu-Lapu',  'Motorized',  'Southern Cooperative',  270.00, 52.00),
    (7,  '2020-01-11', 'P004', 'General Santos Fish Port',  'South Cotabato','S004', 'Tuna',        'V005', 'MV Maria',      'Commercial', 'Coastal Cooperative',   420.00, 75.00),
    (8,  '2020-01-12', 'P004', 'General Santos Fish Port',  'South Cotabato','S004', ' tuna ',      'V005', 'MV Maria',      'Commercial', 'Coastal Cooperative',   430.00, 75.00),
    (9,  '2020-01-15', 'P005', 'Zamboanga Fish Port',       'Zamboanga',     'S005', 'Sardines',    'V001', 'MV San Isidro', 'Motorized',  'Bluewater Cooperative', 240.00, 50.00),
    (10, '2020-01-16', 'P005', 'Zamboanga Fish Port',       'Zamboanga',     'S003', 'Tilapia',     'V002', 'MV Mabuhay',    'Motorized',  'Coastal Cooperative',   230.00, 47.00),
    -- missing values
    (11, NULL,         'P001', 'Navotas Fish Port',         'Metro Manila',  'S001', 'Galunggong', 'V001', 'MV San Isidro', 'Motorized',  'Bluewater Cooperative', NULL,   55.00),
    (12, '2020-02-01', NULL,   'Batangas Fish Port',        'Batangas',      'S002', 'Bangus',      'V002', 'MV Mabuhay',    'Motorized',  'Coastal Cooperative',   300.00, NULL),
    (13, '2020-02-02', 'P003', 'Iloilo Fish Port',          'Iloilo',        'S003', 'Tilapia',     'V003', 'MV Esperanza',  'Commercial', 'Bluewater Cooperative', 225.00, 47.00),
    (14, '2020-02-02', 'P003', 'Iloilo Fish Port',          'Iloilo',        'S003', 'Tilapia',     'V003', 'MV Esperanza',  'Commercial', 'Bluewater Cooperative', 225.00, 47.00), -- duplicate
    (15, '2020-02-04', 'P004', 'General Santos Fish Port',  'South Cotabato','S004', 'Tuna',        'V005', 'MV Maria',      'Commercial', 'Coastal Cooperative',   440.00, 78.00),
    (16, '2020-02-05', 'P005', 'Zamboanga Fish Port',       'Zamboanga',     'S005', 'SARDINES',    'V004', 'MV Lapu-Lapu',  'Motorized',  'Southern Cooperative',  260.00, 51.00),
    (17, '2020-02-07', 'P001', 'Navotas Fish Port',         'Metro Manila',  'S001', 'Galunggong', 'V004', 'MV Lapu-Lapu',  'Motorized',  'Southern Cooperative',  285.00, 57.00),
    (18, '2020-02-08', 'P002', 'Batangas Fish Port',        'Batangas',      'S002', 'Bangus',      'V005', 'MV Maria',      'Commercial', 'Coastal Cooperative',   330.00, 62.00),
    (19, '2020-02-09', 'P003', 'Iloilo Fish Port',          'Iloilo',        'S003', 'TILAPIA',     'V003', 'MV Esperanza',  'Commercial', 'Bluewater Cooperative', 200.00, 45.00),
    (20, '2020-02-11', 'P005', 'Zamboanga Fish Port',       'Zamboanga',     'S005', 'Sardines',    'V001', 'MV San Isidro', 'Motorized',  'Bluewater Cooperative', 245.00, 49.00);

-- =========================
-- 3. DATA PROFILE
-- =========================
SELECT 'landing_date' AS column_name, COUNT(*) AS total_rows,
       COUNT(landing_date) AS non_null_count, COUNT(*) - COUNT(landing_date) AS missing_count
FROM dw.raw_landing
UNION ALL
SELECT 'port_code', COUNT(*), COUNT(port_code), COUNT(*) - COUNT(port_code) FROM dw.raw_landing
UNION ALL
SELECT 'species_name', COUNT(*), COUNT(species_name), COUNT(*) - COUNT(species_name) FROM dw.raw_landing
UNION ALL
SELECT 'kg', COUNT(*), COUNT(kg), COUNT(*) - COUNT(kg) FROM dw.raw_landing
UNION ALL
SELECT 'price_per_kg', COUNT(*), COUNT(price_per_kg), COUNT(*) - COUNT(price_per_kg) FROM dw.raw_landing;

-- duplicate check (by landing_id)
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT landing_id) AS unique_landing_ids,
       COUNT(*) - COUNT(DISTINCT landing_id) AS duplicate_ids
FROM dw.raw_landing;

-- species casing/spacing variants
SELECT TRIM(LOWER(species_name)) AS normalized_species, COUNT(*) AS frequency
FROM dw.raw_landing
WHERE species_name IS NOT NULL
GROUP BY TRIM(LOWER(species_name))
ORDER BY frequency DESC;

-- =========================
-- 4. CLEANING + DEDUPLICATION
-- Deduplicate on the business key (all descriptive measures), not landing_id.
-- Invalid rows are routed to dw.rejected_landing instead of being silently dropped.
-- =========================
CREATE TABLE dw.rejected_landing (
    landing_id   INTEGER,
    landing_date DATE,
    kg           NUMERIC(12,2),
    price_per_kg NUMERIC(12,2),
    reason       TEXT NOT NULL
);

CREATE TABLE dw.clean_landing AS
WITH normalized AS (
    SELECT
        landing_id,
        landing_date,
        NULLIF(TRIM(port_code), '')                                   AS port_code,
        COALESCE(NULLIF(INITCAP(TRIM(port_name)), ''), 'Unknown')     AS port_name,
        COALESCE(NULLIF(INITCAP(TRIM(province)), ''), 'Unknown')      AS province,
        NULLIF(TRIM(species_code), '')                                AS species_code,
        COALESCE(NULLIF(INITCAP(TRIM(species_name)), ''), 'Unknown')  AS species_name,
        NULLIF(TRIM(vessel_id), '')                                   AS vessel_id,
        COALESCE(NULLIF(INITCAP(TRIM(vessel_name)), ''), 'Unknown')   AS vessel_name,
        COALESCE(NULLIF(INITCAP(TRIM(vessel_type)), ''), 'Unknown')   AS vessel_type,
        COALESCE(NULLIF(INITCAP(TRIM(cooperative)), ''), 'Unknown')   AS cooperative,
        kg,
        price_per_kg
    FROM dw.raw_landing
),
deduped AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY landing_date, port_code, species_code,
                         vessel_id, kg, price_per_kg
            ORDER BY landing_id
        ) AS rn
    FROM normalized
)
SELECT landing_id, landing_date, port_code, port_name, province,
       species_code, species_name, vessel_id, vessel_name, vessel_type,
       cooperative, kg, price_per_kg
FROM deduped
WHERE rn = 1;

-- route invalid rows to the reject log (keeps an audit trail)
INSERT INTO dw.rejected_landing (landing_id, landing_date, kg, price_per_kg, reason)
SELECT
    landing_id, landing_date, kg, price_per_kg,
    CONCAT_WS('; ',
        CASE WHEN landing_date IS NULL THEN 'missing landing_date' END,
        CASE WHEN kg IS NULL OR kg <= 0 THEN 'invalid kg' END,
        CASE WHEN price_per_kg IS NULL OR price_per_kg <= 0 THEN 'invalid price_per_kg' END
    )
FROM dw.clean_landing
WHERE landing_date IS NULL
   OR kg IS NULL OR kg <= 0
   OR price_per_kg IS NULL OR price_per_kg <= 0;

-- keep only valid rows in the cleaning table
DELETE FROM dw.clean_landing
WHERE landing_date IS NULL
   OR kg IS NULL OR kg <= 0
   OR price_per_kg IS NULL OR price_per_kg <= 0;

SELECT * FROM dw.clean_landing ORDER BY landing_id;
SELECT * FROM dw.rejected_landing ORDER BY landing_id;

-- =========================
-- 5. DIMENSIONS (with UNKNOWN members, keys = 0)
-- =========================
CREATE TABLE dw.dim_date (
    date_key      INTEGER PRIMARY KEY,
    full_date     DATE UNIQUE NOT NULL,
    calendar_year INTEGER NOT NULL,
    month_number  INTEGER NOT NULL,
    month_name    VARCHAR(20) NOT NULL,
    day_of_month  INTEGER NOT NULL
);

CREATE TABLE dw.dim_port (
    port_key  BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    port_code VARCHAR(20) UNIQUE NOT NULL,
    port_name VARCHAR(100) NOT NULL,
    province  VARCHAR(100) NOT NULL
);

CREATE TABLE dw.dim_species (
    species_key  BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    species_code VARCHAR(20) UNIQUE NOT NULL,
    species_name VARCHAR(100) NOT NULL,
    category     VARCHAR(50) NOT NULL
);

CREATE TABLE dw.dim_vessel (
    vessel_key     BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    vessel_id      VARCHAR(30) NOT NULL,
    vessel_name    VARCHAR(100) NOT NULL,
    vessel_type    VARCHAR(50) NOT NULL,
    cooperative    VARCHAR(100) NOT NULL,
    effective_start DATE NOT NULL,
    effective_end   DATE NOT NULL,
    is_current      BOOLEAN NOT NULL
);

CREATE UNIQUE INDEX ux_dim_vessel_current
    ON dw.dim_vessel(vessel_id)
    WHERE is_current = TRUE;

-- unknown members
INSERT INTO dw.dim_date (date_key, full_date, calendar_year, month_number, month_name, day_of_month)
VALUES (0, DATE '1900-01-01', 1900, 1, 'Unknown', 1);

INSERT INTO dw.dim_port (port_key, port_code, port_name, province)
VALUES (0, 'UNKNOWN', 'Unknown', 'Unknown');

INSERT INTO dw.dim_species (species_key, species_code, species_name, category)
VALUES (0, 'UNKNOWN', 'Unknown', 'Unknown');

INSERT INTO dw.dim_vessel (vessel_key, vessel_id, vessel_name, vessel_type, cooperative,
                           effective_start, effective_end, is_current)
VALUES (0, 'UNKNOWN', 'Unknown', 'Unknown', 'Unknown', DATE '1900-01-01', DATE '9999-12-31', TRUE);

-- =========================
-- 6. POPULATE DIM_DATE (2020-2030)
-- =========================
INSERT INTO dw.dim_date (date_key, full_date, calendar_year, month_number, month_name, day_of_month)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER,
    d::DATE,
    EXTRACT(YEAR FROM d)::INTEGER,
    EXTRACT(MONTH FROM d)::INTEGER,
    TO_CHAR(d, 'FMMonth'),
    EXTRACT(DAY FROM d)::INTEGER
FROM generate_series(DATE '2020-01-01', DATE '2030-12-31', INTERVAL '1 day') AS g(d);

-- =========================
-- 7. LOAD DIMENSIONS (canonical row per code prevents UNIQUE violations)
-- =========================
INSERT INTO dw.dim_port (port_code, port_name, province)
SELECT DISTINCT ON (port_code) port_code, port_name, province
FROM dw.clean_landing
WHERE port_code IS NOT NULL
ORDER BY port_code, port_name;

INSERT INTO dw.dim_species (species_code, species_name, category)
SELECT DISTINCT ON (species_code)
    species_code,
    species_name,
    CASE
        WHEN LOWER(species_name) IN ('galunggong', 'bangus', 'tuna', 'sardines') THEN 'Marine'
        WHEN LOWER(species_name) = 'tilapia' THEN 'Freshwater'
        ELSE 'Unknown'
    END
FROM dw.clean_landing
WHERE species_code IS NOT NULL
ORDER BY species_code, species_name;

INSERT INTO dw.dim_vessel (vessel_id, vessel_name, vessel_type, cooperative,
                           effective_start, effective_end, is_current)
SELECT DISTINCT ON (vessel_id)
    vessel_id, vessel_name, vessel_type, cooperative,
    DATE '2020-01-01', DATE '9999-12-31', TRUE
FROM dw.clean_landing
WHERE vessel_id IS NOT NULL
ORDER BY vessel_id, vessel_name;

-- =========================
-- 8. FACT TABLE (generated total_value)
-- =========================
CREATE TABLE dw.fact_landing (
    landing_key   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_key      INTEGER NOT NULL REFERENCES dw.dim_date(date_key),
    port_key      BIGINT  NOT NULL REFERENCES dw.dim_port(port_key),
    species_key   BIGINT  NOT NULL REFERENCES dw.dim_species(species_key),
    vessel_key    BIGINT  NOT NULL REFERENCES dw.dim_vessel(vessel_key),
    kg            NUMERIC(12,2) NOT NULL CHECK (kg > 0),
    price_per_kg  NUMERIC(12,2) NOT NULL CHECK (price_per_kg > 0),
    total_value   NUMERIC(14,2) GENERATED ALWAYS AS (kg * price_per_kg) STORED
);

CREATE INDEX ix_fact_landing_date    ON dw.fact_landing(date_key);
CREATE INDEX ix_fact_landing_port    ON dw.fact_landing(port_key);
CREATE INDEX ix_fact_landing_species ON dw.fact_landing(species_key);
CREATE INDEX ix_fact_landing_vessel  ON dw.fact_landing(vessel_key);

INSERT INTO dw.fact_landing (date_key, port_key, species_key, vessel_key, kg, price_per_kg)
SELECT
    COALESCE(d.date_key, 0),
    COALESCE(p.port_key, 0),
    COALESCE(s.species_key, 0),
    COALESCE(v.vessel_key, 0),
    c.kg,
    c.price_per_kg
FROM dw.clean_landing c
LEFT JOIN dw.dim_date d    ON d.full_date   = c.landing_date
LEFT JOIN dw.dim_port p    ON p.port_code   = c.port_code
LEFT JOIN dw.dim_species s ON s.species_code = c.species_code
LEFT JOIN dw.dim_vessel v  ON v.vessel_id   = c.vessel_id AND v.is_current = TRUE;

-- =========================
-- 9. DATA QUALITY CHECKS
-- =========================
SELECT 'duplicate_business_keys' AS check_name, COUNT(*) AS result
FROM (
    SELECT landing_date, port_code, species_code, vessel_id, kg, price_per_kg
    FROM dw.clean_landing
    GROUP BY landing_date, port_code, species_code, vessel_id, kg, price_per_kg
    HAVING COUNT(*) > 1
) x
UNION ALL
SELECT 'rejected_rows', COUNT(*) FROM dw.rejected_landing
UNION ALL
SELECT 'facts_with_unknown_keys', COUNT(*)
FROM dw.fact_landing
WHERE date_key = 0 OR port_key = 0 OR species_key = 0 OR vessel_key = 0;

SELECT COUNT(*) AS fact_row_count FROM dw.fact_landing;

-- =========================
-- 10. STAR QUERIES
-- =========================

-- 10a. kilograms per month
SELECT d.calendar_year, d.month_number, d.month_name, SUM(f.kg) AS total_kg
FROM dw.fact_landing f
JOIN dw.dim_date d ON d.date_key = f.date_key
GROUP BY d.calendar_year, d.month_number, d.month_name
ORDER BY d.calendar_year, d.month_number;

-- 10b. top species per port (rank = 1)
WITH species_totals AS (
    SELECT
        p.port_name,
        s.species_name,
        SUM(f.kg) AS total_kg,
        RANK() OVER (PARTITION BY p.port_key ORDER BY SUM(f.kg) DESC) AS species_rank
    FROM dw.fact_landing f
    JOIN dw.dim_port p    ON p.port_key = f.port_key
    JOIN dw.dim_species s ON s.species_key = f.species_key
    GROUP BY p.port_key, p.port_name, s.species_key, s.species_name
)
SELECT port_name, species_name, total_kg
FROM species_totals
WHERE species_rank = 1
ORDER BY port_name;

-- 10c. total value per cooperative
SELECT v.cooperative, SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY v.cooperative
ORDER BY total_value DESC;

-- =========================
-- 11. REPORT BEFORE SCD TYPE 2
-- =========================
CREATE TEMP TABLE report_before AS
SELECT
    d.calendar_year, d.month_number, v.vessel_id, v.cooperative,
    SUM(f.kg) AS total_kg, SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_date d   ON d.date_key = f.date_key
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY d.calendar_year, d.month_number, v.vessel_id, v.cooperative;

-- =========================
-- 12. SCD TYPE 2: V001 cooperative -> Northern Fisheries Cooperative
-- =========================
UPDATE dw.dim_vessel
SET effective_end = CURRENT_DATE - 1,
    is_current    = FALSE
WHERE vessel_id = 'V001'
  AND is_current = TRUE;

INSERT INTO dw.dim_vessel (vessel_id, vessel_name, vessel_type, cooperative,
                           effective_start, effective_end, is_current)
SELECT vessel_id, vessel_name, vessel_type,
       'Northern Fisheries Cooperative',
       CURRENT_DATE, DATE '9999-12-31', TRUE
FROM dw.dim_vessel
WHERE vessel_id = 'V001'
  AND is_current = FALSE
  AND effective_end = CURRENT_DATE - 1;

-- =========================
-- 13. REPORT AFTER SCD TYPE 2
-- =========================
CREATE TEMP TABLE report_after AS
SELECT
    d.calendar_year, d.month_number, v.vessel_id, v.cooperative,
    SUM(f.kg) AS total_kg, SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_date d   ON d.date_key = f.date_key
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY d.calendar_year, d.month_number, v.vessel_id, v.cooperative;

-- =========================
-- 14. VERIFY SCD2
-- =========================
SELECT * FROM dw.dim_vessel WHERE vessel_id = 'V001' ORDER BY effective_start;

WITH differences AS (
    (SELECT * FROM report_before EXCEPT SELECT * FROM report_after)
    UNION ALL
    (SELECT * FROM report_after  EXCEPT SELECT * FROM report_before)
)
SELECT
    CASE WHEN COUNT(*) = 0
         THEN 'PASS: Old reports unchanged'
         ELSE 'FAIL: Old reports changed'
    END AS scd_type2_test,
    COUNT(*) AS difference_count
FROM differences;

COMMIT;
