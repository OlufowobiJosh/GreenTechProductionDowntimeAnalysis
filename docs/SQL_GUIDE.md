# Running and interpreting the SQL

## Requirements

- SQL Server 2016 SP1 or later, or a compatible Azure SQL Database.
- A client that recognises `GO` batch separators, such as SQL Server Management Studio or `sqlcmd`.
- The four existing source tables: `downtime_factors`, `line_downtime`, `line_productivity_batches` and `products`.
- Permission to read those tables and create or alter the two analysis views.

The script uses the `dbo` schema. Change the schema references if the tables are stored elsewhere. It does not create or load source tables, and this repository does not distribute the source dataset.

`Start_Time` and `End_Time` in the source batch table must contain complete, correctly typed timestamps, including the end date for overnight production. The 13 factor columns must have compatible numeric data types for `UNPIVOT`. Factor identifiers must match the numeric suffixes 1–13. Planned duration is interpreted as hours, following the original analysis.

## Execution

1. Select the database containing the four source tables.
2. Open [GreenTech_Analysis.sql](../sql/GreenTech_Analysis.sql).
3. Run section 1 to inspect the source data. Check date mismatches and duplicate identifiers before interpreting joins.
4. Run section 2 to create or update `dbo.downtimes` and `dbo.batch_pd`.
5. Run the validation and analysis sections. Investigate unexpected source values before drawing conclusions from their totals.

The script reads source data and creates or alters the two views. It does not modify the source rows.

## Calculation definitions

| Measure | Interpretation |
| --- | --- |
| Recorded downtime entries | Number of non-null factor cells returned by `UNPIVOT`; not necessarily the number of distinct batches or separate physical incidents |
| Recorded downtime minutes | Sum of the recorded factor values |
| Batches with recorded downtime | Distinct batches with at least one non-null factor entry; zero values remain visible if present |
| Percentage of batches with recorded downtime | Distinct batches with an entry divided by all distinct batches assigned to that operator |
| Actual duration | Elapsed seconds between the full start and end timestamps, divided by 3,600 |
| Extra time | Actual hours minus planned hours, retaining both positive and negative values |
| Reconciliation difference | Extra time converted to minutes, minus summed recorded downtime minutes |

Recorded downtime and production overrun describe different quantities. Their totals need not match: a discrepancy is a prompt to inspect the records and business definitions, not proof of a data error. Summed factor minutes also do not establish that interruptions occurred sequentially.

## Portfolio revision

The portfolio script retains the original analytical questions, with view batch separators, consistent aliases and a fractional-hour duration calculation. It consolidates the selected operator drilldowns and includes a supporting query for multiple same-day batch assignments.

The screenshots preserve the original report export. They have not been regenerated from this revised script, so duration outputs should not be assumed to reproduce the exported figures exactly. The scheduling query identifies multiple assignments on a date; it does not establish overlapping time intervals.

## Microsoft documentation

- [CREATE VIEW and CREATE OR ALTER](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-view-transact-sql)
- [DATEDIFF and date-part boundaries](https://learn.microsoft.com/en-us/sql/t-sql/functions/datediff-transact-sql)
- [UNPIVOT and null values](https://learn.microsoft.com/en-us/sql/t-sql/queries/from-using-pivot-and-unpivot)
- [GO batch separators](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/sql-server-utilities-statements-go)
