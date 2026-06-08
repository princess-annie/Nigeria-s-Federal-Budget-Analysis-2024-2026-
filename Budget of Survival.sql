-- ============================================================
-- THE BUDGET OF SURVIVAL
-- Nigeria 2026 Federal Budget Analysis

-- Full workflow:
-- 1. Create database and raw tables
-- 2. Clean and standardise data
-- 3. Run analysis
-- 4. Create Power BI views
--
-- Tools:
-- PostgreSQL | Power BI
--
-- Sources:
-- Budget Office of the Federation
-- Debt Management Office (DMO)
-- National Bureau of Statistics (NBS)
-- Central Bank of Nigeria (CBN)
-- ============================================================



-- ============================================================
-- SECTION 1: DATABASE SETUP
-- ============================================================

CREATE DATABASE budget_of_survival_db;

-- Connect to the database before running the rest


-- ============================================================
-- SECTION 2: RAW TABLES
-- Load CSVs exactly as downloaded.
-- No cleaning yet.
-- ============================================================

DROP TABLE IF EXISTS raw_budget_expenditure;
CREATE TABLE raw_budget_expenditure (
    year INTEGER,
    mda TEXT,
    personnel_cost DOUBLE PRECISION,
    overhead_cost DOUBLE PRECISION,
    capital_cost DOUBLE PRECISION,
    retained_independent_revenue DOUBLE PRECISION,
    aid_and_grant_funded DOUBLE PRECISION,
    total_allocation DOUBLE PRECISION
);

DROP TABLE IF EXISTS raw_debt;
CREATE TABLE raw_debt (
    year INTEGER,
    total_public_debt DOUBLE PRECISION,
    domestic_debt DOUBLE PRECISION,
    external_debt DOUBLE PRECISION,
    debt_service DOUBLE PRECISION
);

DROP TABLE IF EXISTS raw_inflation;
CREATE TABLE raw_inflation (
    year INTEGER,
    month INTEGER,
    period TEXT,
    all_items_year_on DOUBLE PRECISION,
    all_items_average DOUBLE PRECISION,
    food_year_on DOUBLE PRECISION,
    food_average DOUBLE PRECISION,
    all_items_less_frm_prod_year_on DOUBLE PRECISION,
    all_items_less_frm_prod_average DOUBLE PRECISION,
    all_items_less_frm_prod_and_energy_year_on DOUBLE PRECISION,
    all_items_less_frm_prod_and_energy_avg DOUBLE PRECISION
);

DROP TABLE IF EXISTS raw_food_prices;
CREATE TABLE raw_food_prices (
    year INTEGER,
    month INTEGER,
    period TEXT,
    food_inflation_yoy DOUBLE PRECISION,
    headline_inflation_yoy DOUBLE PRECISION,
    core_inflation_yoy DOUBLE PRECISION
);

DROP TABLE IF EXISTS raw_socioeconomic;
CREATE TABLE raw_socioeconomic (
    year INTEGER,
    minimum_wage INTEGER,
    unemployment_rate DOUBLE PRECISION,
    poverty_rate DOUBLE PRECISION
);

-- ============================================================
-- LOAD DATA
-- Adjust file paths to your system
-- ============================================================

COPY raw_budget_expenditure
FROM 'C:\Users\Public\budget_expenditure.csv'
CSV HEADER;

COPY raw_debt
FROM 'C:\Users\Public\debt.csv'
CSV HEADER;

COPY raw_inflation
FROM 'C:\Users\Public\Inflation.csv'
CSV HEADER;

COPY raw_food_prices
FROM 'C:\Users\Public\food_prices.csv'
CSV HEADER;

COPY raw_socioeconomic
FROM 'C:\Users\Public\socioeconomic_indicators_raw.csv'
CSV HEADER;



-- ============================================================
-- SECTION 3: DATA CHECKS
-- Quick profiling before cleaning
-- ============================================================

-- Row counts
SELECT 'raw_budget_expenditure' AS table_name, COUNT(*) FROM raw_budget_expenditure
UNION ALL
SELECT 'raw_debt', COUNT(*) FROM raw_debt
UNION ALL
SELECT 'raw_inflation', COUNT(*) FROM raw_inflation
UNION ALL
SELECT 'raw_food_prices', COUNT(*) FROM raw_food_prices
UNION ALL
SELECT 'raw_socioeconomic', COUNT(*) FROM raw_socioeconomic;

-- Number of MDAs per year
SELECT year, COUNT(*) AS mda_count
FROM raw_budget_expenditure
GROUP BY year
ORDER BY year;

-- Check missing or suspicious budget values
SELECT
    COUNT(*) FILTER (WHERE mda IS NULL OR mda = '') AS null_mda,
    COUNT(*) FILTER (WHERE total_allocation IS NULL) AS null_total,
    COUNT(*) FILTER (WHERE total_allocation <= 0) AS invalid_total,
    COUNT(*) FILTER (WHERE year NOT IN (2024, 2025, 2026)) AS unexpected_years
FROM raw_budget_expenditure;

-- Check messy MDA names from PDF extraction
SELECT mda, COUNT(*) AS appearances
FROM raw_budget_expenditure
WHERE mda LIKE '%MARINE%'
   OR mda LIKE '%INFORMATION AND%'
   OR mda LIKE '%SPECIAL DUTIES%'
   OR mda LIKE '%HUMANITARIAN%'
GROUP BY mda
ORDER BY mda;

-- Debt table check
SELECT *
FROM raw_debt
ORDER BY year;

-- Inflation coverage
SELECT
    MIN(year) AS earliest_year,
    MAX(year) AS latest_year,
    COUNT(*) AS total_months,
    ROUND(AVG(all_items_year_on)::NUMERIC, 2) AS avg_inflation,
    MAX(food_year_on) AS peak_food_inflation
FROM raw_inflation;

-- Socioeconomic overview
SELECT *
FROM raw_socioeconomic
ORDER BY year;



-- ============================================================
-- SECTION 4: DATA CLEANING
-- Clean, standardise and enrich data
-- ============================================================


-- ============================================================
-- 4.1 CLEAN BUDGET TABLE
-- ============================================================

DROP TABLE IF EXISTS clean_budget_expenditure;

CREATE TABLE clean_budget_expenditure AS
SELECT
    year,

    -- Standardise inconsistent ministry names
    CASE mda
        WHEN 'FEDERAL MINISTRY OFMARINE AND BLUE ECONOMY'
            THEN 'FEDERAL MINISTRY OF MARINE AND BLUE ECONOMY'

        WHEN 'FEDERAL MINISTRY OF INFORMATION AND'
            THEN 'FEDERAL MINISTRY OF INFORMATION AND NATIONAL ORIENTATION'

        WHEN 'NATIONAL ORIENTATION MINISTRY OF INTERIOR'
            THEN 'MINISTRY OF INTERIOR'

        WHEN 'LIVESTOCK JUDICIARY FEDERAL MINISTRY OF'
            THEN 'JUDICIARY'

        WHEN 'FEDERAL MINISTRY OF HUMANITARIAN AFFAIRS AND POVERTY'
            THEN 'FEDERAL MINISTRY OF HUMANITARIAN AFFAIRS AND POVERTY ALLEVIATION'

        ELSE mda
    END AS mda,

    -- Sector grouping for dashboard storytelling
    CASE
        WHEN mda IN (
            'MINISTRY OF DEFENCE',
            'NATIONAL SECURITY ADVISER',
            'FEDERAL MINISTRY OF POLICE AFFAIRS',
            'MINISTRY OF INTERIOR'
        ) THEN 'Defence & Security'

        WHEN mda = 'FEDERAL MINISTRY OF EDUCATION'
            THEN 'Education'

        WHEN mda = 'FEDERAL MINISTRY OF HEALTH AND SOCIAL WELFARE'
            THEN 'Health'

        WHEN mda IN (
            'FEDERAL MINISTRY OF WORKS',
            'FEDERAL MINISTRY OF POWER',
            'FEDERAL MINISTRY OF TRANSPORT'
        ) THEN 'Infrastructure'

        WHEN mda IN (
            'FEDERAL MINISTRY OF AGRICULTURE AND FOOD SECURITY',
            'FEDERAL MINISTRY OF LIVESTOCK'
        ) THEN 'Agriculture & Food'

        WHEN mda IN (
            'FEDERAL MINISTRY OF FINANCE',
            'FEDERAL MINISTRY OF BUDGET AND ECONOMIC PLANNING'
        ) THEN 'Debt & Finance'

        WHEN mda IN (
            'FEDERAL MINISTRY OF HUMANITARIAN AFFAIRS AND POVERTY ALLEVIATION',
            'FEDERAL MINISTRY OF WOMEN AFFAIRS',
            'FEDERAL MINISTRY OF YOUTH DEVELOPMENT'
        ) THEN 'Social Protection'

        WHEN mda IN (
            'FEDERAL MINISTRY OF COMMUNICATIONS AND DIGITAL ECONOMY',
            'FEDERAL MINISTRY OF INDUSTRY, TRADE AND INVESTMENT',
            'FEDERAL MINISTRY OF LABOUR AND EMPLOYMENT'
        ) THEN 'Economy & Trade'

        WHEN mda IN (
            'FEDERAL MINISTRY OF ENVIRONMENT',
            'FEDERAL MINISTRY OF SOLID MINERALS DEVELOPMENT',
            'FEDERAL MINISTRY OF MARINE AND BLUE ECONOMY'
        ) THEN 'Environment & Resources'

        WHEN mda IN (
            'PRESIDENCY',
            'NATIONAL ASSEMBLY',
            'JUDICIARY'
        ) THEN 'Administration'

        ELSE 'Others'
    END AS sector,

    -- Convert to billions for easier reporting
    ROUND((personnel_cost / 1e9)::NUMERIC, 2) AS personnel_cost_bn,
    ROUND((overhead_cost / 1e9)::NUMERIC, 2) AS overhead_cost_bn,
    ROUND((capital_cost / 1e9)::NUMERIC, 2) AS capital_cost_bn,
    ROUND((total_allocation / 1e9)::NUMERIC, 2) AS total_allocation_bn,

    -- Spending pattern
    CASE
        WHEN capital_cost > (personnel_cost + overhead_cost)
        THEN 'Capital-Heavy'
        ELSE 'Recurrent-Heavy'
    END AS spending_type

FROM raw_budget_expenditure
WHERE total_allocation > 0;



-- ============================================================
-- 4.2 SUPPORTING CLEAN TABLES
-- ============================================================

DROP TABLE IF EXISTS clean_debt;
CREATE TABLE clean_debt AS
SELECT
    year,
    total_public_debt AS total_public_debt_tn,
    domestic_debt AS domestic_debt_tn,
    external_debt AS external_debt_tn,
    debt_service AS debt_service_tn
FROM raw_debt;


DROP TABLE IF EXISTS clean_inflation;
CREATE TABLE clean_inflation AS
SELECT
    year,
    month,
    period,
    all_items_year_on AS headline_inflation_pct,
    food_year_on AS food_inflation_pct,
    all_items_less_frm_prod_year_on AS core_inflation_pct
FROM raw_inflation
ORDER BY year, month;


DROP TABLE IF EXISTS clean_food_prices;
CREATE TABLE clean_food_prices AS
SELECT
    year,
    month,
    period,
    food_inflation_yoy AS food_inflation_pct,
    headline_inflation_yoy AS headline_inflation_pct,
    core_inflation_yoy AS core_inflation_pct
FROM raw_food_prices
ORDER BY year, month;


DROP TABLE IF EXISTS clean_socioeconomic;
CREATE TABLE clean_socioeconomic AS
SELECT
    s.year,
    s.minimum_wage,
    s.unemployment_rate,
    s.poverty_rate,

    -- Inflation-adjusted wage estimate
    ROUND(
        (
            s.minimum_wage /
            (1 + COALESCE(inf.avg_inflation, 0) / 100)
        )::NUMERIC,
    0) AS real_wage_adjusted,

    inf.avg_inflation AS annual_avg_inflation_pct

FROM raw_socioeconomic s

LEFT JOIN (
    SELECT
        year,
        ROUND(AVG(all_items_year_on)::NUMERIC, 2) AS avg_inflation
    FROM raw_inflation
    GROUP BY year
) inf
ON s.year = inf.year;



-- ============================================================
-- SECTION 5: ANALYSIS
-- Main numbers powering the story
-- ============================================================


-- Budget summary by year
SELECT
    year,
    COUNT(DISTINCT mda) AS total_mdas,
    ROUND(SUM(total_allocation_bn)::NUMERIC, 1) AS total_budget_bn,
    ROUND(SUM(capital_cost_bn)::NUMERIC, 1) AS total_capital_bn,
    ROUND(
        SUM(capital_cost_bn) * 100.0 /
        SUM(total_allocation_bn), 1
    ) AS capital_pct
FROM clean_budget_expenditure
GROUP BY year
ORDER BY year;

-- Sector share by year
SELECT
    year,
    sector,
    ROUND(SUM(total_allocation_bn)::NUMERIC, 1) AS sector_total_bn,
    ROUND(
        (SUM(total_allocation_bn) * 100.0 / 
        SUM(SUM(total_allocation_bn)) OVER (PARTITION BY year))::NUMERIC, 2
    ) AS pct_of_budget
FROM clean_budget_expenditure
GROUP BY year, sector
ORDER BY year, pct_of_budget DESC;

-- Debt vs Education + Health
SELECT
    year,

    ROUND(
        SUM(total_allocation_bn)
        FILTER (WHERE sector = 'Debt & Finance')::NUMERIC, 1
    ) AS debt_finance_bn,

    ROUND(
        SUM(total_allocation_bn)
        FILTER (WHERE sector IN ('Education','Health'))::NUMERIC, 1
    ) AS edu_health_bn,

    ROUND(
        SUM(total_allocation_bn)
        FILTER (WHERE sector = 'Debt & Finance')
        /
        NULLIF(
            SUM(total_allocation_bn)
            FILTER (WHERE sector IN ('Education','Health')), 0
        ),
    1) AS debt_vs_edu_health_ratio

FROM clean_budget_expenditure
GROUP BY year
ORDER BY year;

-- Inflation summary
SELECT
    year,
    ROUND(AVG(headline_inflation_pct)::NUMERIC, 2) AS avg_headline_inflation,
    ROUND(AVG(food_inflation_pct)::NUMERIC, 2) AS avg_food_inflation,
    MAX(food_inflation_pct) AS peak_food_inflation
FROM clean_inflation
GROUP BY year
ORDER BY year;


-- Minimum wage reality check
SELECT
    s.year,
    s.minimum_wage,
    s.poverty_rate,
    s.unemployment_rate,

    ROUND(i.avg_headline_inflation::NUMERIC, 1) AS avg_inflation_pct,

    -- Fixed: Cast the division result to NUMERIC before rounding
    ROUND(
        (s.minimum_wage / (1 + i.peak_food_inflation / 100))::NUMERIC, 
        0
    ) AS real_wage_at_peak_food_inflation

FROM clean_socioeconomic s

JOIN (
    SELECT
        year,
        AVG(headline_inflation_pct) AS avg_headline_inflation,
        MAX(food_inflation_pct) AS peak_food_inflation
    FROM clean_inflation
    GROUP BY year
) i
ON s.year = i.year
ORDER BY s.year;



-- ============================================================
-- SECTION 6: POWER BI VIEWS
-- Clean views for dashboard connection
-- ============================================================


-- ============================================================
-- PAGE 1: NIGERIA'S BUDGET AT A GLANCE
-- ============================================================

DROP VIEW IF EXISTS vw_page1_budget_overview;

CREATE VIEW vw_page1_budget_overview AS
SELECT
    year,
    sector,

    ROUND(SUM(total_allocation_bn)::NUMERIC, 1) AS allocation_bn,

    ROUND(
        SUM(total_allocation_bn) * 100.0 /
        SUM(SUM(total_allocation_bn)) OVER (PARTITION BY year), 2
    ) AS pct_of_total_budget,

    ROUND(SUM(capital_cost_bn)::NUMERIC, 1) AS capital_bn,

    ROUND(
        SUM(personnel_cost_bn + overhead_cost_bn)::NUMERIC, 1
    ) AS recurrent_bn

FROM clean_budget_expenditure
GROUP BY year, sector;



DROP VIEW IF EXISTS vw_page1_kpi;

CREATE VIEW vw_page1_kpi AS
SELECT
    year,

    ROUND(SUM(total_allocation_bn)::NUMERIC, 1) AS total_budget_bn,

    ROUND(
        SUM(total_allocation_bn)
        FILTER (WHERE sector = 'Debt & Finance')::NUMERIC, 1
    ) AS debt_finance_bn,

    ROUND(
        SUM(total_allocation_bn)
        FILTER (WHERE sector = 'Education')::NUMERIC, 1
    ) AS education_bn,

    ROUND(
        SUM(total_allocation_bn)
        FILTER (WHERE sector = 'Health')::NUMERIC, 1
    ) AS health_bn

FROM clean_budget_expenditure
GROUP BY year
ORDER BY year;



-- ============================================================
-- PAGE 2: WHAT NIGERIANS ACTUALLY FEEL
-- ============================================================

DROP VIEW IF EXISTS vw_page2_cost_of_living;

CREATE VIEW vw_page2_cost_of_living AS
SELECT
    i.year,
    i.month,
    i.period,
    i.headline_inflation_pct,
    i.food_inflation_pct,
    i.core_inflation_pct,

    s.minimum_wage,
    s.poverty_rate,
    s.unemployment_rate,

    -- Fixed: Added ::NUMERIC cast for the ROUND function
    ROUND(
        (s.minimum_wage / (1 + i.food_inflation_pct / 100))::NUMERIC, 
        0
    ) AS real_food_purchasing_power,

    CASE
        WHEN i.food_inflation_pct >= 40 THEN 'Crisis'
        WHEN i.food_inflation_pct >= 25 THEN 'Severe'
        WHEN i.food_inflation_pct >= 15 THEN 'High'
        ELSE 'Moderate'
    END AS food_inflation_severity

FROM clean_inflation i
LEFT JOIN clean_socioeconomic s
ON i.year = s.year;



-- ============================================================
-- PAGE 3: WINNERS AND LOSERS
-- ============================================================

DROP VIEW IF EXISTS vw_page3_winners_losers;

CREATE VIEW vw_page3_winners_losers AS

WITH sector_pivot AS (
    SELECT
        sector,
        SUM(total_allocation_bn)
            FILTER (WHERE year = 2025) AS alloc_2025,

        SUM(total_allocation_bn)
            FILTER (WHERE year = 2026) AS alloc_2026

    FROM clean_budget_expenditure
    GROUP BY sector
)

SELECT
    sector,

    ROUND(alloc_2025::NUMERIC, 1) AS alloc_2025_bn,
    ROUND(alloc_2026::NUMERIC, 1) AS alloc_2026_bn,

    ROUND((alloc_2026 - alloc_2025)::NUMERIC, 1) AS change_bn,

    ROUND(
        (alloc_2026 - alloc_2025) * 100.0 /
        NULLIF(alloc_2025, 0), 1
    ) AS pct_change,

    CASE
        WHEN (alloc_2026 - alloc_2025) > 0 THEN 'Winner'
        ELSE 'Loser'
    END AS outcome_label

FROM sector_pivot
ORDER BY pct_change DESC;



-- ============================================================
-- PAGE 4: THE BIG QUESTION
-- ============================================================

DROP VIEW IF EXISTS vw_page4_the_big_question;

CREATE VIEW vw_page4_the_big_question AS

SELECT
    b.year,

    ROUND(
        SUM(b.total_allocation_bn)
        FILTER (WHERE b.sector = 'Debt & Finance')::NUMERIC, 1
    ) AS debt_finance_bn,

    ROUND(
        SUM(b.total_allocation_bn)
        FILTER (WHERE b.sector IN ('Education','Health'))::NUMERIC, 1
    ) AS edu_health_bn,

    ROUND(
        SUM(b.total_allocation_bn)
        FILTER (WHERE b.sector = 'Defence & Security')::NUMERIC, 1
    ) AS defence_bn,

    ROUND(
        SUM(b.total_allocation_bn)
        FILTER (WHERE b.sector = 'Social Protection')::NUMERIC, 1
    ) AS social_protection_bn,

    ROUND(
        SUM(b.total_allocation_bn)
        FILTER (WHERE b.sector = 'Debt & Finance')
        /
        NULLIF(
            SUM(b.total_allocation_bn)
            FILTER (WHERE b.sector IN ('Education','Health')), 0
        ),
    1) AS debt_vs_edu_health_ratio,

    d.total_public_debt_tn,
    d.debt_service_tn,

    s.poverty_rate,
    s.minimum_wage,
    s.unemployment_rate

FROM clean_budget_expenditure b

LEFT JOIN clean_debt d
ON b.year = d.year

LEFT JOIN clean_socioeconomic s
ON b.year = s.year

GROUP BY
    b.year,
    d.total_public_debt_tn,
    d.debt_service_tn,
    s.poverty_rate,
    s.minimum_wage,
    s.unemployment_rate

ORDER BY b.year;



-- ============================================================
-- BONUS VIEW: MDA DRILLDOWN
-- ============================================================

DROP VIEW IF EXISTS vw_mda_detail;

CREATE VIEW vw_mda_detail AS
SELECT
    year,
    sector,
    mda,
    personnel_cost_bn,
    overhead_cost_bn,
    capital_cost_bn,
    total_allocation_bn,
    spending_type,

    RANK() OVER (
        PARTITION BY year, sector
        ORDER BY total_allocation_bn DESC
    ) AS rank_within_sector

FROM clean_budget_expenditure;



-- ============================================================
-- FINAL VALIDATION
-- ============================================================

-- Confirm all views exist
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public'
AND table_name LIKE 'vw_%'
ORDER BY table_name;


-- Quick check for Page 4
SELECT
    year,
    debt_finance_bn,
    edu_health_bn,
    debt_vs_edu_health_ratio
FROM vw_page4_the_big_question
ORDER BY year;


-- Highest food inflation periods
SELECT
    period,
    food_inflation_pct
FROM vw_page2_cost_of_living
ORDER BY food_inflation_pct DESC
LIMIT 5;


-- Biggest winners
SELECT
    sector,
    alloc_2026_bn,
    pct_change,
    outcome_label
FROM vw_page3_winners_losers
ORDER BY pct_change DESC;



-- ============================================================
-- END OF SCRIPT
-- ============================================================
-- Dashboard Pages:
--
-- Page 1 → Nigeria's Budget at a Glance
-- Page 2 → What Nigerians Actually Feel
-- Page 3 → Winners and Losers
-- Page 4 → The Big Question
-- ============================================================