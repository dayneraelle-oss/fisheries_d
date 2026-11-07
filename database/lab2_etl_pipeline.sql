-- =========================================================
-- LAB 2: ETL PIPELINE (EXTRACT -> TRANSFORM -> LOAD)
-- Extracts the raw landings, cleans/deduplicates them, then
-- loads the dimensions and fact table. Also runs the star
-- queries and the SCD Type 2 demo.
-- Requires: lab1_fisheries_star_schema.sql
-- Run this file second.
-- Target: PostgreSQL
-- =========================================================

BEGIN;

-- =========================
-- EXTRACT: RAW / STAGING TABLE
-- =========================
DROP TABLE IF EXISTS dw.clean_landing;
DROP TABLE IF EXISTS dw.rejected_landing;
DROP TABLE IF EXISTS dw.raw_landing;

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
    (11, NULL,         'P001', 'Navotas Fish Port',         'Metro Manila',  'S001', 'Galunggong', 'V001', 'MV San Isidro', 'Motorized',  'Bluewater Cooperative', NULL,   55.00),
    (12, '2020-02-01', NULL,   'Batangas Fish Port',        'Batangas',      'S002', 'Bangus',      'V002', 'MV Mabuhay',    'Motorized',  'Coastal Cooperative',   300.00, NULL),
    (13, '2020-02-02', 'P003', 'Iloilo Fish Port',          'Iloilo',        'S003', 'Tilapia',     'V003', 'MV Esperanza',  'Commercial', 'Bluewater Cooperative', 225.00, 47.00),
    (14, '2020-02-02', 'P003', 'Iloilo Fish Port',          'Iloilo',        'S003', 'Tilapia',     'V003', 'MV Esperanza',  'Commercial', 'Bluewater Cooperative', 225.00, 47.00),
    (15, '2020-02-04', 'P004', 'General Santos Fish Port',  'South Cotabato','S004', 'Tuna',        'V005', 'MV Maria',      'Commercial', 'Coastal Cooperative',   440.00, 78.00),
    (16, '2020-02-05', 'P005', 'Zamboanga Fish Port',       'Zamboanga',     'S005', 'SARDINES',    'V004', 'MV Lapu-Lapu',  'Motorized',  'Southern Cooperative',  260.00, 51.00),
    (17, '2020-02-07', 'P001', 'Navotas Fish Port',         'Metro Manila',  'S001', 'Galunggong', 'V004', 'MV Lapu-Lapu',  'Motorized',  'Southern Cooperative',  285.00, 57.00),
    (18, '2020-02-08', 'P002', 'Batangas Fish Port',        'Batangas',      'S002', 'Bangus',      'V005', 'MV Maria',      'Commercial', 'Coastal Cooperative',   330.00, 62.00),
    (19, '2020-02-09', 'P003', 'Iloilo Fish Port',          'Iloilo',        'S003', 'TILAPIA',     'V003', 'MV Esperanza',  'Commercial', 'Bluewater Cooperative', 200.00, 45.00),
    (20, '2020-02-11', 'P005', 'Zamboanga Fish Port',       'Zamboanga',     'S005', 'Sardines',    'V001', 'MV San Isidro', 'Motorized',  'Bluewater Cooperative', 245.00, 49.00);

-- =========================
-- TRANSFORM: CLEAN + DEDUPLICATE
-- Deduplicate on the business key; route invalid rows to the reject log.
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

DELETE FROM dw.clean_landing
WHERE landing_date IS NULL
   OR kg IS NULL OR kg <= 0
   OR price_per_kg IS NULL OR price_per_kg <= 0;

-- =========================
-- LOAD: RESET TARGET TABLES
-- =========================
TRUNCATE dw.fact_landing RESTART IDENTITY;
DELETE FROM dw.dim_port    WHERE port_key    <> 0;
DELETE FROM dw.dim_species WHERE species_key <> 0;
DELETE FROM dw.dim_vessel  WHERE vessel_key  <> 0;

-- =========================
-- LOAD: DIMENSIONS
-- DISTINCT ON keeps one canonical row per code.
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
-- LOAD: FACT TABLE
-- =========================
INSERT INTO dw.fact_landing (date_key, port_key, species_key, vessel_key, kg, price_per_kg)
SELECT
    COALESCE(d.date_key, 0),
    COALESCE(p.port_key, 0),
    COALESCE(s.species_key, 0),
    COALESCE(v.vessel_key, 0),
    c.kg,
    c.price_per_kg
FROM dw.clean_landing c
LEFT JOIN dw.dim_date d    ON d.full_date    = c.landing_date
LEFT JOIN dw.dim_port p    ON p.port_code    = c.port_code
LEFT JOIN dw.dim_species s ON s.species_code = c.species_code
LEFT JOIN dw.dim_vessel v  ON v.vessel_id    = c.vessel_id AND v.is_current = TRUE;

-- =========================
-- STAR QUERIES
-- =========================

-- kilograms per month
SELECT d.calendar_year, d.month_number, d.month_name, SUM(f.kg) AS total_kg
FROM dw.fact_landing f
JOIN dw.dim_date d ON d.date_key = f.date_key
GROUP BY d.calendar_year, d.month_number, d.month_name
ORDER BY d.calendar_year, d.month_number;

-- top species per port (rank = 1)
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

-- total value per cooperative
SELECT v.cooperative, SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY v.cooperative
ORDER BY total_value DESC;

-- =========================
-- SCD TYPE 2 DEMO: V001 cooperative change
-- =========================
CREATE TEMP TABLE report_before ON COMMIT DROP AS
SELECT
    d.calendar_year, d.month_number, v.vessel_id, v.cooperative,
    SUM(f.kg) AS total_kg, SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_date d   ON d.date_key = f.date_key
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY d.calendar_year, d.month_number, v.vessel_id, v.cooperative;

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

CREATE TEMP TABLE report_after ON COMMIT DROP AS
SELECT
    d.calendar_year, d.month_number, v.vessel_id, v.cooperative,
    SUM(f.kg) AS total_kg, SUM(f.total_value) AS total_value
FROM dw.fact_landing f
JOIN dw.dim_date d   ON d.date_key = f.date_key
JOIN dw.dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY d.calendar_year, d.month_number, v.vessel_id, v.cooperative;

-- vessel history
SELECT * FROM dw.dim_vessel WHERE vessel_id = 'V001' ORDER BY effective_start;

-- historical reports unchanged?
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
