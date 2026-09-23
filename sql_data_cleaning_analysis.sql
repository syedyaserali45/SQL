-- ============================================================================
--  SQL DATA CLEANING & ANALYSIS  —  E-COMMERCE ORDERS (MySQL 8.0+)
-- ============================================================================
--  What this file does, in order:
--    1. Loads a realistic RAW extract (customers + orders) containing
--       intentional data-quality issues:
--         * duplicate customer rows (same person, different casing/spaces)
--         * duplicate & near-duplicate order rows (same order_id)
--         * inconsistent name / city / category casing and whitespace
--         * missing values (NULLs) and junk values ('N/A', 'kavita.joshi@')
--         * dates stored as text in 3 different formats (+ some missing)
--         * invalid quantities (negative / zero), missing prices & statuses
--         * orphan orders referencing non-existent customers
--    2. Runs a DATA QUALITY AUDIT (duplicate detection, missing-data scans,
--       format-inconsistency checks).
--    3. BUILDS CLEAN, DEDUPLICATED tables (customers, orders) using
--       normalization, ROW_NUMBER() deduplication, STR_TO_DATE parsing,
--       mapping tables and COALESCE imputation.
--    4. Produces an ANALYSIS-READY enriched table + view, a data-quality
--       report, and a set of analytical queries (monthly revenue, top
--       customers, category performance, cohorts, repeat-purchase rate).
--
--  How to run:
--      mysql -u <user> -p < sql_data_cleaning_analysis.sql
--   (or open in MySQL Workbench / Dbeaver and execute the whole file)
--
--  Requires MySQL 8.0+ (CTEs, window functions, REGEXP_REPLACE).
--  The script is idempotent: it drops and rebuilds everything in the
--  `demo_ecommerce` schema, so it is safe to re-run.
-- ============================================================================

-- ============================================================================
-- SECTION 0 — SETUP
-- ============================================================================
CREATE DATABASE IF NOT EXISTS demo_ecommerce;
USE demo_ecommerce;

DROP VIEW IF EXISTS analysis_orders;
DROP TABLE IF EXISTS data_quality_report;
DROP TABLE IF EXISTS enriched_orders;
DROP TABLE IF EXISTS clean_orders;
DROP TABLE IF EXISTS tmp_orders_dedup;
DROP TABLE IF EXISTS raw_customer_map;
DROP TABLE IF EXISTS clean_customers;
DROP TABLE IF EXISTS tmp_ranked;
DROP TABLE IF EXISTS tmp_normalized;
DROP TABLE IF EXISTS tmp_norm_base;
DROP TABLE IF EXISTS raw_orders;
DROP TABLE IF EXISTS raw_customers;
DROP TABLE IF EXISTS product_dim;

-- ============================================================================
-- SECTION 1 — LOAD RAW (DIRTY) DATA
-- ============================================================================

-- 1a. Clean product catalog (the reference we impute missing prices from)
CREATE TABLE product_dim (
    product_key        INT PRIMARY KEY,
    product_name       VARCHAR(100) NOT NULL,
    product_name_lower VARCHAR(100) NOT NULL,   -- used for fuzzy matching
    category           VARCHAR(50)  NOT NULL,
    standard_price     DECIMAL(10,2) NOT NULL
);

INSERT INTO product_dim (product_key, product_name, product_name_lower, category, standard_price) VALUES
    (1, 'Wireless Mouse',      'wireless mouse',      'Electronics', 12.50),
    (2, 'Mechanical Keyboard', 'mechanical keyboard', 'Electronics', 45.00),
    (3, 'USB-C Cable',         'usb-c cable',         'Accessories', 5.25),
    (4, 'Standing Desk',       'standing desk',       'Furniture',   249.99),
    (5, 'Ergo Chair',          'ergo chair',          'Furniture',   399.00),
    (6, '27" Monitor',         '27" monitor',         'Electronics', 329.99);

-- 1b. Raw customers — deliberately dirty (dates & flags kept as raw text)
CREATE TABLE raw_customers (
    id          INT PRIMARY KEY,
    full_name   VARCHAR(100),
    email       VARCHAR(150),
    phone       VARCHAR(50),
    city        VARCHAR(80),
    signup_date VARCHAR(30),    -- raw: mixed formats / missing
    is_active   VARCHAR(10)     -- raw: Y / yes / 1 / N ...
);

INSERT INTO raw_customers (id, full_name, email, phone, city, signup_date, is_active) VALUES
    ( 1, 'John Smith',    'john.smith@example.com',     '98765 43210',   'Hyderabad', '2023-01-10',   'Y'),
    ( 2, 'john  smith',   'JOHN.SMITH@EXAMPLE.COM',     '+91-98765-43210','HYDERABAD', '2023-01-12',  'yes'),   -- dup of 1 (casing, spacing, phone format)
    ( 3, '  John Smith',  'john.smith@example.com',     NULL,            'Hyd',       'Jan 12, 2023', '1'),     -- dup of 1 (leading spaces, short city, text date)
    ( 4, 'Amit Sharma',   'amit.sharma@example.com',    '9812345678',    'Bangalore', '2023-02-01',   'Y'),
    ( 5, 'AMIT SHARMA',   'amit.sharma@example.com',    NULL,            'blr',       '2023-02-02',   'N'),     -- dup of 4
    ( 6, 'Priya Patel',   'priya.patel@example.com',    '9900011122',    'Mumbai',    '2023-03-05',   'Y'),
    ( 7, 'Priya Patel',   'priya.patel@example.com',    '9900011122',    'mumbai',    '2023-03-05',   'Y'),     -- exact dup of 6
    ( 8, 'Rahul Verma',   'rahul.verma@example.com',    'N/A',           'Delhi',     '2023-04-18',   'Y'),
    ( 9, 'RAHUL VERMA',   'rahul.verma@example.com',    '9855500011',    'delhi',     '2023-04-20',   'yes'),   -- dup of 8 (8 has junk phone)
    (10, 'Sneha Iyer',    'sneha.iyer@example.com',     '9765432109',    'Pune',      '2023-05-11',   'Y'),
    (11, 'sneha iyer',    'sneha.iyer@example.com',     NULL,            'PUNE',      '2023-05-14',   'N'),     -- dup of 10
    (12, 'Vikram Singh',  'vikram.singh@example.com',   '9844455666',    'Hyderabad', '2023-06-21',   'Y'),
    (13, 'Vikram Singh',  'vikram.singh@example.com',   '9844455566',    'Hyderabad', '2023-06-21',   'Y'),     -- near-dup of 12 (phone typo)
    (14, 'Kavita Joshi',  'kavita.joshi@',              '9123487650',    'Mumbai',    '2023-07-09',   'Y'),     -- INVALID email
    (15, 'Ananya Reddy',  'ananya.reddy@example.com',   NULL,            'Hyderabad', NULL,           'Y'),     -- missing phone + signup date
    (16, 'Arjun Mehta',   'arjun.mehta@example.com',    '9877012345',    'Chennai',   '2023-09-30',   'N');

-- 1c. Raw orders — deliberately dirty
CREATE TABLE raw_orders (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    order_id    VARCHAR(20),
    customer_id INT,
    order_date  VARCHAR(30),      -- raw: 'YYYY-MM-DD', 'DD/MM/YYYY', 'Mon DD, YYYY', or NULL
    product     VARCHAR(100),
    category    VARCHAR(60),
    quantity    INT,
    unit_price  DECIMAL(10,2),
    status      VARCHAR(30)
);

INSERT INTO raw_orders (order_id, customer_id, order_date, product, category, quantity, unit_price, status) VALUES
    ('O-1001',  1, '2024-01-15',  'Wireless Mouse',      'Electronics',  2, 12.50,  'completed'),
    ('O-1001',  1, '2024-01-15',  'Wireless Mouse',      'Electronics',  2, 12.50,  'completed'),   -- exact duplicate
    ('O-1002',  4, '2024-01-22',  'Mechanical Keyboard', 'electronics',  1, 45.00,  'COMPLETED'),   -- category/status casing
    ('O-1003',  2, '15/02/2024',  'USB-C Cable',         'Accessories',  3, 5.25,   'shipped'),     -- DD/MM/YYYY date, dup customer 2
    ('O-1004',  6, 'Feb 20, 2024','Standing Desk',       'Furniture',    1, NULL,   'completed'),   -- text date + MISSING PRICE
    ('O-1005',  8, '2024-03-01',  'Ergo Chair',          'Furniture',    1, 399.00, 'pending'),
    ('O-1006',  7, '2024-03-05',  'Wireless Mouse',      'Electronics', -1, 12.50,  'completed'),   -- NEGATIVE quantity
    ('O-1007', 12, '2024-03-12',  '27" Monitor',         'Electronics',  1, NULL,   'completed'),   -- MISSING PRICE
    ('O-1008',  9, '2024-03-18',  'Standing Desk',       'Furniture',    2, 249.99, 'canceled'),    -- status variant
    ('O-1009', 10, '2024-04-02',  'Mechanical Keyboard', 'Electronics',  1, 45.00,  'shipped'),
    ('O-1010', 14, '2024-04-10',  'USB-C Cable',         'Accessories',  5, 5.25,   'completed'),
    ('O-1011', 15, '2024-04-19',  'Wireless Mouse',      'electronics',  2, 12.50,  'completed'),
    ('O-1011', 15, '19/04/2024',  'wireless mouse',      'electronics',  2, 12.50,  'Completed'),   -- near-duplicate (same order_id)
    ('O-1012', 11, '2024-05-06',  'Ergo Chair',          'Furniture',    1, 399.00, 'pending'),     -- dup customer 11
    ('O-1013', 16, '2024-05-15',  'Standing Desk',       'Furniture',    1, 249.99, 'completed'),
    ('O-1014',  5, '2024-05-28',  '27" Monitor',         'Electronics',  1, 329.99, 'shipped'),     -- dup customer 5
    ('O-1015', 13, '2024-06-10',  'Mechanical Keyboard', 'Electronics',  0, 45.00,  'completed'),   -- ZERO quantity
    ('O-1016',  3, '2024-06-22',  'USB-C Cable',         'Accessories',  4, 5.25,   'completed'),   -- dup customer 3
    ('O-1017', 99, '2024-06-30',  'Wireless Mouse',      'Electronics',  1, 12.50,  'completed'),   -- ORPHAN: customer 99 does not exist
    ('O-1018',  6, '2024-07-08',  'Wireless Mouse',      'Electronics',  1, 12.50,  NULL),          -- MISSING status
    ('O-1019',  8, NULL,          'Standing Desk',       'Furniture',    1, 249.99, 'pending'),     -- MISSING date
    ('O-1020', 12, '2024-08-05',  'Ergo Chair',          'Furniture',    1, 399.00, 'completed'),
    ('O-1021', 15, '2024-08-18',  'Mechanical Keyboard', 'Electronics',  2, 45.00,  'shipped'),
    ('O-1022', 16, '2024-09-12',  '27" Monitor',         'Electronics',  1, 329.99, 'completed'),
    ('O-1023', 10, '2024-09-25',  'Standing Desk',       'Furniture',    1, 249.99, 'cancelled');   -- status variant

-- ============================================================================
-- SECTION 2 — DATA QUALITY AUDIT  (each query returns a result set — review)
-- ============================================================================

-- 2.1 Overall row counts -----------------------------------------------------
SELECT 'raw_customers' AS table_name, COUNT(*) AS row_count FROM raw_customers
UNION ALL
SELECT 'raw_orders',    COUNT(*) FROM raw_orders;

-- 2.2 Missing / invalid values per customer column ---------------------------
SELECT
    COUNT(*)                                                    AS total_rows,
    SUM(email IS NULL)                                          AS missing_email,
    SUM(email IS NOT NULL
          AND NOT (LOWER(TRIM(email)) REGEXP '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$'))
                                                                AS invalid_email,
    SUM(phone IS NULL OR TRIM(phone) IN ('', 'N/A'))           AS missing_or_junk_phone,
    SUM(signup_date IS NULL OR TRIM(signup_date) = '')         AS missing_signup_date,
    SUM(is_active IS NULL)                                      AS missing_active_flag
FROM raw_customers;

-- 2.3 Duplicate customer records (same name + email, case-insensitive) -------
SELECT LOWER(TRIM(full_name)) AS name,
       LOWER(TRIM(email))     AS email,
       COUNT(*)               AS occurrences,
       GROUP_CONCAT(id ORDER BY id) AS raw_row_ids
FROM raw_customers
GROUP BY LOWER(TRIM(full_name)), LOWER(TRIM(email))
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;

-- 2.4 Same entity stored in different formats (casing / whitespace variants) --
SELECT LOWER(TRIM(full_name))  AS normalized_name,
       COUNT(DISTINCT full_name) AS stored_variants,
       GROUP_CONCAT(DISTINCT full_name ORDER BY full_name SEPARATOR ' | ') AS variants
FROM raw_customers
GROUP BY LOWER(TRIM(full_name))
HAVING stored_variants > 1;

SELECT LOWER(TRIM(city))  AS normalized_city,
       COUNT(DISTINCT city) AS stored_variants,
       GROUP_CONCAT(DISTINCT city ORDER BY city SEPARATOR ' | ') AS variants
FROM raw_customers
GROUP BY LOWER(TRIM(city))
HAVING stored_variants > 1;

-- 2.5 Duplicate order ids -----------------------------------------------------
SELECT order_id,
       COUNT(*) AS occurrences,
       GROUP_CONCAT(id ORDER BY id) AS raw_row_ids
FROM raw_orders
GROUP BY order_id
HAVING COUNT(*) > 1;

-- 2.6 Invalid quantities ------------------------------------------------------
SELECT id, order_id, quantity
FROM raw_orders
WHERE quantity IS NULL OR quantity <= 0;

-- 2.7 Orphan orders (customer does not exist) ---------------------------------
SELECT o.id, o.order_id, o.customer_id
FROM raw_orders o
LEFT JOIN raw_customers c ON o.customer_id = c.id
WHERE c.id IS NULL;

-- 2.8 Date format mix ----------------------------------------------------------
SELECT
    SUM(order_date IS NULL)                                   AS missing_date,
    SUM(order_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')     AS fmt_iso        , -- 2024-01-15
    SUM(order_date REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$') AS fmt_ddmmyyyy   , -- 15/02/2024
    SUM(order_date REGEXP '^[A-Za-z]{3} ')                    AS fmt_text       -- 'Feb 20, 2024'
FROM raw_orders;

-- 2.9 Inconsistent status / category values -----------------------------------
SELECT 'status'   AS field, status   AS value, COUNT(*) AS row_count FROM raw_orders GROUP BY status
UNION ALL
SELECT 'category', category, COUNT(*) FROM raw_orders GROUP BY category
ORDER BY field, row_count DESC;

-- 2.10 Missing prices -----------------------------------------------------------
SELECT COUNT(*) AS orders_missing_unit_price FROM raw_orders WHERE unit_price IS NULL;

-- ============================================================================
-- SECTION 3 — CLEANING: CUSTOMERS
--   normalize -> dedupe (keep most complete record) -> canonical values
-- ============================================================================

-- 3a. Normalize every raw customer row -----------------------------------------
CREATE TABLE tmp_norm_base AS
SELECT
    id,
    full_name,
    email,
    phone,
    city,
    signup_date,
    is_active,
    TRIM(REGEXP_REPLACE(full_name, '\\s+', ' '))        AS norm_name,      -- collapse spaces, trim
    LOWER(TRIM(REGEXP_REPLACE(full_name, '\\s+', ' '))) AS name_lc,
    LOWER(TRIM(email))                                  AS email_norm,
    (LOWER(TRIM(email)) REGEXP '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$')
                                                       AS valid_email,
    IF(LENGTH(REGEXP_REPLACE(phone, '[^0-9]', '')) >= 10,
       RIGHT(REGEXP_REPLACE(phone, '[^0-9]', ''), 10),
       NULL)                                            AS phone_10,       -- strip junk, keep last 10 digits
    LOWER(TRIM(city))                                   AS city_lc,
    CASE
        WHEN signup_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'     THEN STR_TO_DATE(signup_date, '%Y-%m-%d')
        WHEN signup_date REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' THEN STR_TO_DATE(signup_date, '%d/%m/%Y')
        WHEN signup_date REGEXP '^[A-Za-z]{3} [0-9]{1,2}, [0-9]{4}$' THEN STR_TO_DATE(signup_date, '%b %d, %Y')
        ELSE NULL
    END                                                 AS signup_parsed,
    CASE
        WHEN is_active IN ('Y', 'y', '1', 'yes', 'YES') THEN 1
        WHEN is_active IN ('N', 'n', '0', 'no',  'NO')  THEN 0
        ELSE NULL
    END                                                 AS active_flag
FROM raw_customers;

-- 3b. Build the dedup key + a completeness score (how many usable fields) ----
CREATE TABLE tmp_normalized AS
SELECT
    b.*,
    IF(b.valid_email = 1,
       CONCAT('e:', b.email_norm),
       CONCAT('n:', b.name_lc, '|', b.city_lc))         AS dedup_key,
    ((b.norm_name <> '') + b.valid_email
     + (b.phone_10 IS NOT NULL)
     + (b.city IS NOT NULL AND TRIM(b.city) <> '')
     + (b.signup_parsed IS NOT NULL)
     + (b.active_flag IS NOT NULL))                     AS completeness
FROM tmp_norm_base b;

-- 3c. Rank rows inside each duplicate cluster; remember the survivor's id ----
CREATE TABLE tmp_ranked AS
SELECT
    n.*,
    ROW_NUMBER()  OVER (PARTITION BY n.dedup_key ORDER BY n.completeness DESC, n.id) AS rn,
    FIRST_VALUE(n.id) OVER (PARTITION BY n.dedup_key ORDER BY n.completeness DESC, n.id) AS kept_id
FROM tmp_normalized n;

-- 3d. Clean customers: one row per person, canonical name/city, usable values -
CREATE TABLE clean_customers AS
SELECT
    id AS customer_id,                                   -- survivor's raw id becomes the stable key
    CASE name_lc
        WHEN 'john smith'   THEN 'John Smith'
        WHEN 'amit sharma'  THEN 'Amit Sharma'
        WHEN 'priya patel'  THEN 'Priya Patel'
        WHEN 'rahul verma'  THEN 'Rahul Verma'
        WHEN 'sneha iyer'   THEN 'Sneha Iyer'
        WHEN 'vikram singh' THEN 'Vikram Singh'
        WHEN 'kavita joshi' THEN 'Kavita Joshi'
        WHEN 'ananya reddy' THEN 'Ananya Reddy'
        WHEN 'arjun mehta'  THEN 'Arjun Mehta'
        ELSE norm_name
    END                                                  AS full_name,
    IF(valid_email = 1, email_norm, NULL)                AS email,        -- invalid emails nulled out
    phone_10                                             AS phone,        -- junk/NULL phones -> NULL
    CASE city_lc
        WHEN 'hyd'        THEN 'Hyderabad'
        WHEN 'hbd'        THEN 'Hyderabad'
        WHEN 'hyderabad'  THEN 'Hyderabad'
        WHEN 'blr'        THEN 'Bangalore'
        WHEN 'bangalore'  THEN 'Bangalore'
        WHEN 'mumbai'     THEN 'Mumbai'
        WHEN 'delhi'      THEN 'Delhi'
        WHEN 'pune'       THEN 'Pune'
        WHEN 'chennai'    THEN 'Chennai'
        ELSE TRIM(city)
    END                                                  AS city,
    signup_parsed                                        AS signup_date,
    active_flag                                          AS is_active
FROM tmp_ranked
WHERE rn = 1;

-- 3e. Map EVERY raw customer id to the surviving (canonical) customer id -----
CREATE TABLE raw_customer_map AS
SELECT id AS raw_id, kept_id AS customer_id FROM tmp_ranked;

DROP TABLE tmp_ranked;
DROP TABLE tmp_normalized;
DROP TABLE tmp_norm_base;

-- ============================================================================
-- SECTION 4 — CLEANING: ORDERS
--   dedupe on order_id -> parse dates -> fix values -> drop invalid rows
-- ============================================================================

-- 4a. Parse dates, then keep only the most complete row per order_id ----------
CREATE TABLE tmp_orders_dedup AS
WITH base AS (
    SELECT
        o.*,
        CASE
            WHEN order_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'     THEN STR_TO_DATE(order_date, '%Y-%m-%d')
            WHEN order_date REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' THEN STR_TO_DATE(order_date, '%d/%m/%Y')
            WHEN order_date REGEXP '^[A-Za-z]{3} [0-9]{1,2}, [0-9]{4}$' THEN STR_TO_DATE(order_date, '%b %d, %Y')
            ELSE NULL
        END AS order_date_parsed
    FROM raw_orders o
),
ranked AS (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY (order_date_parsed IS NOT NULL) DESC,
                     (unit_price IS NOT NULL)        DESC,
                     (status IS NOT NULL)            DESC,
                     id ASC
        ) AS rn
    FROM base b
)
SELECT * FROM ranked;

-- 4b. Build the clean order table ----------------------------------------------
CREATE TABLE clean_orders AS
SELECT
    d.order_id,
    m.customer_id,                                     -- mapped to canonical customer (drops orphans)
    d.order_date_parsed                                AS order_date,
    p.product_name                                     AS product,      -- canonical name
    p.category                                         AS category,     -- canonical category
    d.quantity,
    COALESCE(d.unit_price, p.standard_price)           AS unit_price,   -- imputed from catalog
    CASE UPPER(TRIM(d.status))
        WHEN 'COMPLETED' THEN 'Completed'
        WHEN 'SHIPPED'   THEN 'Shipped'
        WHEN 'PENDING'   THEN 'Pending'
        WHEN 'CANCELED'  THEN 'Cancelled'
        WHEN 'CANCELLED' THEN 'Cancelled'
        ELSE 'Unknown'
    END                                                AS status,
    ROUND(d.quantity * COALESCE(d.unit_price, p.standard_price), 2)
                                                       AS line_total,
    (d.unit_price IS NULL)                             AS price_imputed,
    (d.order_date_parsed IS NULL)                      AS date_missing,
    (d.status IS NULL)                                 AS status_missing
FROM tmp_orders_dedup d
JOIN raw_customer_map m
    ON m.raw_id = d.customer_id                        -- inner join removes orphan orders
JOIN product_dim p
    ON p.product_name_lower = LOWER(TRIM(REGEXP_REPLACE(d.product, '\\s+', ' ')))
WHERE d.rn = 1
  AND d.quantity IS NOT NULL
  AND d.quantity > 0;                                  -- reject negative / zero quantities

DROP TABLE tmp_orders_dedup;

-- ============================================================================
-- SECTION 5 — ANALYSIS-READY EXTRACT
-- ============================================================================

-- One row per order, joined to the canonical customer. This is the table
-- analysts/dashboards should query from.
CREATE TABLE enriched_orders AS
SELECT
    o.*,
    c.full_name    AS customer_name,
    c.city,
    c.email        AS customer_email,
    c.signup_date  AS customer_signup_date
FROM clean_orders o
JOIN clean_customers c ON c.customer_id = o.customer_id;

-- Convenience view over the extract
CREATE OR REPLACE VIEW analysis_orders AS
SELECT * FROM enriched_orders;

-- ============================================================================
-- SECTION 6 — DATA QUALITY REPORT (before/after, computed, not hard-coded)
-- ============================================================================
CREATE TABLE data_quality_report (
    step_order INT PRIMARY KEY,
    object     VARCHAR(40),
    check_name VARCHAR(60),
    value      INT,
    details    VARCHAR(120)
);

INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT  1, 'raw_customers', 'Rows in raw extract',        COUNT(*), 'Dirty source load' FROM raw_customers;
INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT  2, 'raw_customers', 'Duplicate customer rows removed',
       (SELECT COUNT(*) FROM raw_customers) - (SELECT COUNT(*) FROM clean_customers),
       'Deduped on email, fallback name+city; kept most complete record' FROM (SELECT 1) t;
INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT  3, 'raw_customers', 'Emails missing or invalid',
       SUM(email IS NULL) + SUM(email IS NOT NULL AND NOT (LOWER(TRIM(email)) REGEXP '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$')),
       'Invalid emails set to NULL in clean table' FROM raw_customers;
INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT  4, 'clean_customers', 'Clean customer rows', COUNT(*), 'One row per person, canonical values' FROM clean_customers;
INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT  5, 'raw_orders', 'Rows in raw extract', COUNT(*), 'Dirty source load' FROM raw_orders;
INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT  6, 'raw_orders', 'Duplicate order rows removed',
       COUNT(*) - COUNT(DISTINCT order_id), 'Kept most complete row per order_id' FROM raw_orders;
INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT  7, 'raw_orders', 'Rejected: invalid quantity',
       SUM(quantity IS NULL OR quantity <= 0), 'Quantity NULL / 0 / negative' FROM raw_orders;
INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT  8, 'raw_orders', 'Rejected: unknown customer',
       COUNT(*), 'Orphan customer_id, no match in customer master'
FROM raw_orders o LEFT JOIN raw_customers c ON o.customer_id = c.id
WHERE c.id IS NULL;
INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT  9, 'clean_orders', 'Unit prices imputed from catalog',
       SUM(price_imputed), 'COALESCE(raw price, product_dim.standard_price)' FROM clean_orders;
INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT 10, 'clean_orders', 'Orders kept with missing date',
       SUM(date_missing), 'Date left NULL; excluded from monthly analysis' FROM clean_orders;
INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT 11, 'clean_orders', 'Orders with missing status',
       SUM(status_missing), 'Status normalized to Unknown' FROM clean_orders;
INSERT INTO data_quality_report (step_order, object, check_name, value, details)
SELECT 12, 'clean_orders', 'Final analysis-ready order rows',
       COUNT(*), 'Cleaned extract (enriched_orders)' FROM clean_orders;

SELECT * FROM data_quality_report ORDER BY step_order;

-- ============================================================================
-- SECTION 7 — ANALYTICAL QUERIES (each returns a result set)
-- ============================================================================

-- 7.1 Headline KPIs ------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM clean_customers)                                   AS customers,
    COUNT(*)                                                                 AS orders,
    ROUND(SUM(CASE WHEN status <> 'Cancelled' THEN line_total END), 2)       AS net_revenue,
    ROUND(AVG(CASE WHEN status <> 'Cancelled' THEN line_total END), 2)       AS avg_order_value
FROM clean_orders;

-- 7.2 Monthly revenue trend (orders with a parseable date) ---------------------
SELECT
    DATE_FORMAT(order_date, '%Y-%m')                                         AS month_id,
    COUNT(*)                                                                 AS orders,
    ROUND(SUM(CASE WHEN status <> 'Cancelled' THEN line_total END), 2)       AS net_revenue,
    ROUND(AVG(CASE WHEN status <> 'Cancelled' THEN line_total END), 2)       AS avg_order_value
FROM enriched_orders
WHERE order_date IS NOT NULL
GROUP BY month_id
ORDER BY month_id;

-- 7.3 Top 10 customers by spend ------------------------------------------------
SELECT
    customer_id,
    customer_name,
    city,
    COUNT(*)                                                                 AS orders,
    ROUND(SUM(line_total), 2)                                                AS total_spend,
    ROUND(AVG(line_total), 2)                                                AS avg_order_value,
    MAX(order_date)                                                          AS last_order_date
FROM enriched_orders
WHERE status <> 'Cancelled'
GROUP BY customer_id, customer_name, city
ORDER BY total_spend DESC
LIMIT 10;

-- 7.4 Category performance with revenue share ----------------------------------
SELECT
    category,
    COUNT(*)                                                                 AS orders,
    SUM(quantity)                                                            AS units_sold,
    ROUND(SUM(line_total), 2)                                                AS net_revenue,
    ROUND(100.0 * SUM(line_total)
          / NULLIF((SELECT SUM(line_total) FROM clean_orders WHERE status <> 'Cancelled'), 0), 1)
                                                                             AS revenue_share_pct
FROM clean_orders
WHERE status <> 'Cancelled'
GROUP BY category
ORDER BY net_revenue DESC;

-- 7.5 Order status breakdown -----------------------------------------------------
SELECT
    status,
    COUNT(*)                                                                 AS orders,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM clean_orders), 1)         AS pct_of_orders,
    ROUND(SUM(line_total), 2)                                                AS gross_value
FROM clean_orders
GROUP BY status
ORDER BY orders DESC;

-- 7.6 Signup-month cohort performance ---------------------------------------------
SELECT
    DATE_FORMAT(c.signup_date, '%Y-%m')                                      AS signup_month,
    COUNT(DISTINCT c.customer_id)                                            AS customers,
    COUNT(o.order_id)                                                        AS orders,
    ROUND(COALESCE(SUM(CASE WHEN o.status <> 'Cancelled' THEN o.line_total END), 0), 2) AS net_revenue
FROM clean_customers c
LEFT JOIN clean_orders o ON o.customer_id = c.customer_id
GROUP BY signup_month
ORDER BY signup_month;

-- 7.7 Repeat-purchase rate -----------------------------------------------------------
SELECT
    COUNT(*)                                                                 AS customers_with_orders,
    SUM(order_count > 1)                                                     AS repeat_customers,
    ROUND(100.0 * SUM(order_count > 1) / COUNT(*), 1)                        AS repeat_purchase_pct
FROM (
    SELECT customer_id, COUNT(*) AS order_count
    FROM clean_orders
    WHERE status <> 'Cancelled'
    GROUP BY customer_id
) t;

-- 7.8 The analysis-ready extract itself (what downstream consumers get) -------------
SELECT *
FROM enriched_orders
ORDER BY (order_date IS NULL), order_date, order_id;

-- ============================================================================
--  END OF SCRIPT
--  Schema produced:
--    raw_customers / raw_orders   – original dirty extract (kept for audit)
--    product_dim                  – clean product catalog (reference)
--    clean_customers              – deduplicated, canonical customer master
--    raw_customer_map             – raw id -> canonical id bridge
--    clean_orders                 – deduplicated, corrected orders
--    enriched_orders + analysis_orders (view) – analysis-ready extract
--    data_quality_report          – before/after quality metrics
-- ============================================================================
