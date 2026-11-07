-- =========================================================
-- LAB 3: DATA CLEANING AND PROFILING
-- Profiles the raw data, then rebuilds the cleaned staging
-- tables (clean_landing / rejected_landing) with the full
-- cleaning rules and prints data quality checks.
-- Requires: lab2_etl_pipeline.sql (creates dw.raw_landing)
-- Run this file third.
-- Target: PostgreSQL
-- =========================================================

BEGIN;

-- =========================
-- 1. DATA PROFILE
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

-- duplicate landing_id check
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
-- 2. CLEANING
-- =========================
DROP TABLE IF EXISTS dw.clean_landing;
DROP TABLE IF EXISTS dw.rejected_landing;

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

-- route invalid rows to the reject log (audit trail)
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

-- =========================
-- 3. CLEANED OUTPUT
-- =========================
SELECT * FROM dw.clean_landing ORDER BY landing_id;
SELECT * FROM dw.rejected_landing ORDER BY landing_id;

-- =========================
-- 4. DATA QUALITY CHECKS
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
SELECT 'species_variations', COUNT(DISTINCT species_name) FROM dw.clean_landing;

COMMIT;
