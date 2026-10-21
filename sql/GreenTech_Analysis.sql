/*
GreenTech Production Downtime Analysis
Oluwatobiloba Olufowobi | Individual project

Portfolio revision of the original analysis.
SQL Server 2016 SP1+; run in SSMS/sqlcmd against the source database.
See ../docs/SQL_GUIDE.md for source requirements and calculation definitions.

The script reads four source tables and creates or alters two analysis views.
Source rows are not changed. Screenshots retain the original report export.
*/

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- 1. DATA ASSESSMENT

SELECT TOP (10) * FROM dbo.downtime_factors;
SELECT TOP (10) * FROM dbo.line_downtime;
SELECT TOP (10) * FROM dbo.line_productivity_batches;
SELECT TOP (10) * FROM dbo.products;

SELECT 'downtime_factors' AS Table_Name, COUNT(*) AS Row_Count
FROM dbo.downtime_factors
UNION ALL
SELECT 'line_downtime', COUNT(*) FROM dbo.line_downtime
UNION ALL
SELECT 'line_productivity_batches', COUNT(*) FROM dbo.line_productivity_batches
UNION ALL
SELECT 'products', COUNT(*) FROM dbo.products;

SELECT COUNT(*) AS Factor_1_Null_Count
FROM dbo.line_downtime
WHERE Factor_1 IS NULL;

SELECT COUNT(*) AS Factor_2_Null_Count
FROM dbo.line_downtime
WHERE Factor_2 IS NULL;

SELECT COUNT(*) AS All_Factors_Null_Count
FROM dbo.line_downtime
WHERE COALESCE(
    Factor_1, Factor_2, Factor_3, Factor_4, Factor_5, Factor_6, Factor_7,
    Factor_8, Factor_9, Factor_10, Factor_11, Factor_12, Factor_13
) IS NULL;

-- Compare the recorded date with the date in the start timestamp.
;WITH Start_Dates AS (
    SELECT
        Batch_ID,
        CAST([Date] AS date) AS Recorded_Date,
        CAST(Start_Time AS date) AS Timestamp_Start_Date
    FROM dbo.line_productivity_batches
)
SELECT *
FROM Start_Dates
WHERE Recorded_Date <> Timestamp_Start_Date
   OR Recorded_Date IS NULL
   OR Timestamp_Start_Date IS NULL;

-- Check identifier uniqueness before interpreting joined totals.
SELECT Batch_ID, COUNT(*) AS Source_Rows
FROM dbo.line_productivity_batches
GROUP BY Batch_ID
HAVING COUNT(*) > 1;

SELECT Product_ID, COUNT(*) AS Source_Rows
FROM dbo.products
GROUP BY Product_ID
HAVING COUNT(*) > 1;

SELECT Factor_ID, COUNT(*) AS Source_Rows
FROM dbo.downtime_factors
GROUP BY Factor_ID
HAVING COUNT(*) > 1;
GO

-- 2. DATA TRANSFORMATION
-- UNPIVOT omits null cells. Zero and negative values are retained.
CREATE OR ALTER VIEW dbo.downtimes AS
SELECT
    u.Batch_ID,
    CAST(REPLACE(u.Factor, 'Factor_', '') AS int) AS Factor_ID,
    u.Minutes
FROM (
    SELECT
        Batch_ID,
        Factor_1, Factor_2, Factor_3, Factor_4, Factor_5, Factor_6,
        Factor_7, Factor_8, Factor_9, Factor_10, Factor_11, Factor_12,
        Factor_13
    FROM dbo.line_downtime
) AS src
UNPIVOT (
    Minutes FOR Factor IN (
        Factor_1, Factor_2, Factor_3, Factor_4, Factor_5, Factor_6,
        Factor_7, Factor_8, Factor_9, Factor_10, Factor_11, Factor_12,
        Factor_13
    )
) AS u;
GO

-- Calculate duration from full timestamps before extracting display times.
-- Fractional hours replace the original hour-boundary calculation.
CREATE OR ALTER VIEW dbo.batch_pd AS
SELECT
    CAST(b.[Date] AS date) AS Start_Date,
    b.Product_ID,
    b.Batch_ID,
    b.[Operator],
    CAST(b.End_Time AS date) AS End_Date,
    CAST(b.Start_Time AS time) AS Start_Time,
    CAST(b.End_Time AS time) AS End_Time,
    b.Planned_min_Batch_Hours,
    CAST(
        DATEDIFF(SECOND, b.Start_Time, b.End_Time) / 3600.0
        AS decimal(18, 6)
    ) AS Actual_Duration,
    CAST(
        DATEDIFF(SECOND, b.Start_Time, b.End_Time) / 3600.0
            - b.Planned_min_Batch_Hours
        AS decimal(18, 6)
    ) AS Extra_Time_Hr
FROM dbo.line_productivity_batches AS b;
GO

-- 3. VALIDATION AND RECONCILIATION

SELECT *
FROM dbo.downtimes
ORDER BY Batch_ID, Factor_ID;

-- Retained values that may need investigation; no automatic replacement.
SELECT *
FROM dbo.downtimes
WHERE Minutes <= 0;

SELECT Batch_ID, Start_Time, End_Time, Planned_min_Batch_Hours
FROM dbo.line_productivity_batches
WHERE Start_Time IS NULL
   OR End_Time IS NULL
   OR End_Time < Start_Time
   OR Planned_min_Batch_Hours IS NULL
   OR Planned_min_Batch_Hours <= 0;

-- Unmatched keys would otherwise disappear from inner-join analyses.
SELECT DISTINCT d.Batch_ID
FROM dbo.downtimes AS d
LEFT JOIN dbo.batch_pd AS b ON b.Batch_ID = d.Batch_ID
WHERE b.Batch_ID IS NULL;

SELECT DISTINCT d.Factor_ID
FROM dbo.downtimes AS d
LEFT JOIN dbo.downtime_factors AS f ON f.Factor_ID = d.Factor_ID
WHERE f.Factor_ID IS NULL;

SELECT DISTINCT b.Product_ID
FROM dbo.batch_pd AS b
LEFT JOIN dbo.products AS p ON p.Product_ID = b.Product_ID
WHERE p.Product_ID IS NULL;

-- Compare minutes with minutes. A difference is not automatically an error.
;WITH Downtime_Totals AS (
    SELECT Batch_ID, SUM(Minutes) AS Recorded_Downtime_Minutes
    FROM dbo.downtimes
    GROUP BY Batch_ID
)
SELECT
    b.Batch_ID,
    b.Extra_Time_Hr,
    ROUND(b.Extra_Time_Hr * 60.0, 2) AS Extra_Time_Minutes,
    COALESCE(d.Recorded_Downtime_Minutes, 0) AS Recorded_Downtime_Minutes,
    ROUND(
        b.Extra_Time_Hr * 60.0 - COALESCE(d.Recorded_Downtime_Minutes, 0),
        2
    ) AS Overrun_Minus_Downtime_Minutes
FROM dbo.batch_pd AS b
LEFT JOIN Downtime_Totals AS d ON d.Batch_ID = b.Batch_ID
ORDER BY b.Batch_ID;

-- 4. DOWNTIME FACTOR ANALYSIS
-- An entry means a non-null factor cell, not a distinct production batch.

SELECT
    f.Factor_ID,
    f.Factor_Name,
    COUNT(*) AS Recorded_Downtime_Entries,
    SUM(d.Minutes) AS Delay_Minutes
FROM dbo.downtimes AS d
JOIN dbo.downtime_factors AS f ON f.Factor_ID = d.Factor_ID
GROUP BY f.Factor_ID, f.Factor_Name
ORDER BY Recorded_Downtime_Entries DESC, Delay_Minutes DESC;

-- Operator-related versus non-operator-related source classifications.
SELECT
    CASE f.Operator_Error
        WHEN 1 THEN 'Operator-related'
        WHEN 0 THEN 'Non-operator-related'
        ELSE 'Unclassified'
    END AS Downtime_Classification,
    COUNT(*) AS Recorded_Downtime_Entries,
    SUM(d.Minutes) AS Delay_Minutes
FROM dbo.downtimes AS d
JOIN dbo.downtime_factors AS f ON f.Factor_ID = d.Factor_ID
GROUP BY f.Operator_Error;

SELECT
    f.Factor_ID,
    f.Factor_Name,
    f.Description,
    COUNT(*) AS Recorded_Downtime_Entries,
    SUM(d.Minutes) AS Delay_Minutes
FROM dbo.downtimes AS d
JOIN dbo.downtime_factors AS f ON f.Factor_ID = d.Factor_ID
WHERE f.Operator_Error = 1
GROUP BY f.Factor_ID, f.Factor_Name, f.Description
ORDER BY Delay_Minutes DESC;

SELECT
    f.Factor_ID,
    f.Factor_Name,
    f.Description,
    COUNT(*) AS Recorded_Downtime_Entries,
    SUM(d.Minutes) AS Delay_Minutes
FROM dbo.downtimes AS d
JOIN dbo.downtime_factors AS f ON f.Factor_ID = d.Factor_ID
WHERE f.Operator_Error = 0
GROUP BY f.Factor_ID, f.Factor_Name, f.Description
ORDER BY Delay_Minutes DESC;

-- 5. PRODUCT ANALYSIS

SELECT
    b.Product_ID,
    p.Product_Name,
    COUNT(*) AS Recorded_Downtime_Entries,
    SUM(d.Minutes) AS Delay_Minutes
FROM dbo.batch_pd AS b
JOIN dbo.downtimes AS d ON d.Batch_ID = b.Batch_ID
JOIN dbo.products AS p ON p.Product_ID = b.Product_ID
GROUP BY b.Product_ID, p.Product_Name
ORDER BY Delay_Minutes DESC;

SELECT
    b.Product_ID,
    p.Product_Name,
    COUNT(DISTINCT d.Factor_ID) AS Distinct_Downtime_Factors
FROM dbo.batch_pd AS b
JOIN dbo.products AS p ON p.Product_ID = b.Product_ID
JOIN dbo.downtimes AS d ON d.Batch_ID = b.Batch_ID
GROUP BY b.Product_ID, p.Product_Name;

-- Batch-level averages are calculated before any one-to-many downtime join.
SELECT
    b.Product_ID,
    p.Product_Name,
    AVG(CAST(b.Planned_min_Batch_Hours AS decimal(18, 6))) AS Avg_Planned_Hours,
    AVG(b.Actual_Duration) AS Avg_Actual_Hours
FROM dbo.batch_pd AS b
JOIN dbo.products AS p ON p.Product_ID = b.Product_ID
GROUP BY b.Product_ID, p.Product_Name;

-- Top five factors by recorded delay minutes for each selected product.
SELECT TOP (5)
    f.Factor_Name, SUM(d.Minutes) AS Delay_Minutes
FROM dbo.downtimes AS d
JOIN dbo.downtime_factors AS f ON f.Factor_ID = d.Factor_ID
JOIN dbo.batch_pd AS b ON b.Batch_ID = d.Batch_ID
WHERE b.Product_ID = 'PRD001'
GROUP BY f.Factor_Name
ORDER BY Delay_Minutes DESC, f.Factor_Name;

SELECT TOP (5)
    f.Factor_Name, SUM(d.Minutes) AS Delay_Minutes
FROM dbo.downtimes AS d
JOIN dbo.downtime_factors AS f ON f.Factor_ID = d.Factor_ID
JOIN dbo.batch_pd AS b ON b.Batch_ID = d.Batch_ID
WHERE b.Product_ID = 'PRD002'
GROUP BY f.Factor_Name
ORDER BY Delay_Minutes DESC, f.Factor_Name;

SELECT TOP (5)
    f.Factor_Name, SUM(d.Minutes) AS Delay_Minutes
FROM dbo.downtimes AS d
JOIN dbo.downtime_factors AS f ON f.Factor_ID = d.Factor_ID
JOIN dbo.batch_pd AS b ON b.Batch_ID = d.Batch_ID
WHERE b.Product_ID = 'PRD003'
GROUP BY f.Factor_Name
ORDER BY Delay_Minutes DESC, f.Factor_Name;

SELECT TOP (5)
    f.Factor_Name, SUM(d.Minutes) AS Delay_Minutes
FROM dbo.downtimes AS d
JOIN dbo.downtime_factors AS f ON f.Factor_ID = d.Factor_ID
JOIN dbo.batch_pd AS b ON b.Batch_ID = d.Batch_ID
WHERE b.Product_ID = 'PRD004'
GROUP BY f.Factor_Name
ORDER BY Delay_Minutes DESC, f.Factor_Name;

-- 6. OPERATOR ANALYSIS

SELECT
    [Operator],
    COUNT(DISTINCT Batch_ID) AS Number_Of_Batches,
    COUNT(DISTINCT Product_ID) AS Number_Of_Products
FROM dbo.batch_pd
GROUP BY [Operator];

-- The original "delayed batches" query measures batches with an entry.
-- It does not test whether Actual_Duration exceeds planned duration.
SELECT
    b.[Operator],
    COUNT(DISTINCT b.Batch_ID) AS Total_Batches,
    COUNT(DISTINCT d.Batch_ID) AS Batches_With_Recorded_Downtime,
    COUNT(d.Batch_ID) AS Recorded_Downtime_Entries,
    COALESCE(SUM(d.Minutes), 0) AS Delay_Minutes,
    CAST(
        COUNT(DISTINCT d.Batch_ID) * 100.0
            / NULLIF(COUNT(DISTINCT b.Batch_ID), 0)
        AS decimal(10, 2)
    ) AS Percentage_Batches_With_Recorded_Downtime
FROM dbo.batch_pd AS b
LEFT JOIN dbo.downtimes AS d ON d.Batch_ID = b.Batch_ID
GROUP BY b.[Operator]
ORDER BY Percentage_Batches_With_Recorded_Downtime DESC;

-- Selected operator drilldowns from the original analysis.
-- These names are explicit selections, not a dynamically calculated top three.
SELECT
    b.[Operator],
    f.Factor_Name,
    SUM(d.Minutes) AS Delay_Minutes
FROM dbo.downtime_factors AS f
JOIN dbo.downtimes AS d ON d.Factor_ID = f.Factor_ID
JOIN dbo.batch_pd AS b ON b.Batch_ID = d.Batch_ID
WHERE b.[Operator] IN ('Paul', 'James', 'Emily', 'Linda', 'Sophia', 'Rita')
GROUP BY b.[Operator], f.Factor_Name
ORDER BY b.[Operator], Delay_Minutes DESC;

-- 7. SUPPORTING SCHEDULING QUERY
-- Multiple batches on a date do not, by themselves, establish overlap.
;WITH Multiple_Batch_Days AS (
    SELECT [Operator], Start_Date
    FROM dbo.batch_pd
    GROUP BY [Operator], Start_Date
    HAVING COUNT(DISTINCT Batch_ID) > 1
)
SELECT
    b.[Operator],
    b.Start_Date,
    b.Start_Time,
    b.End_Date,
    b.End_Time,
    b.Product_ID,
    p.Product_Name,
    b.Batch_ID
FROM dbo.batch_pd AS b
JOIN Multiple_Batch_Days AS m
    ON m.[Operator] = b.[Operator]
   AND m.Start_Date = b.Start_Date
LEFT JOIN dbo.products AS p ON p.Product_ID = b.Product_ID
ORDER BY b.[Operator], b.Start_Date, b.Start_Time, b.Batch_ID;
