# Data dictionary

This dictionary covers the source columns referenced in the analysis SQL and the fields produced by its two views. It is not a complete database schema: source data types, field lengths and enforced constraints have not been supplied.

## Source tables

### `downtime_factors`

| Column | Meaning in this analysis |
| --- | --- |
| `Factor_ID` | Identifier used to match a factor to an unpivoted downtime entry; the SQL expects identifiers compatible with 1–13 |
| `Factor_Name` | Name of the downtime factor |
| `Description` | Description of the factor |
| `Operator_Error` | Source classification: `1` = operator-related; `0` = non-operator-related |

### `line_downtime`

| Column | Meaning in this analysis |
| --- | --- |
| `Batch_ID` | Identifier linking downtime records to a production batch |
| `Factor_1` | Recorded downtime minutes for factor 1 |
| `Factor_2` | Recorded downtime minutes for factor 2 |
| `Factor_3` | Recorded downtime minutes for factor 3 |
| `Factor_4` | Recorded downtime minutes for factor 4 |
| `Factor_5` | Recorded downtime minutes for factor 5 |
| `Factor_6` | Recorded downtime minutes for factor 6 |
| `Factor_7` | Recorded downtime minutes for factor 7 |
| `Factor_8` | Recorded downtime minutes for factor 8 |
| `Factor_9` | Recorded downtime minutes for factor 9 |
| `Factor_10` | Recorded downtime minutes for factor 10 |
| `Factor_11` | Recorded downtime minutes for factor 11 |
| `Factor_12` | Recorded downtime minutes for factor 12 |
| `Factor_13` | Recorded downtime minutes for factor 13 |

A non-null factor value becomes a row in `downtimes`. A null is omitted by `UNPIVOT`; it is not replaced with zero. Zero and negative values, if present, are retained for inspection.

### `line_productivity_batches`

| Column | Meaning in this analysis |
| --- | --- |
| `Date` | Recorded production date; exposed as `Start_Date` in `batch_pd` |
| `Product_ID` | Product associated with the batch |
| `Batch_ID` | Production batch identifier |
| `Operator` | Operator assigned to the batch |
| `Start_Time` | Source start timestamp, including its date for duration calculations |
| `End_Time` | Source end timestamp, including its date for duration calculations |
| `Planned_min_Batch_Hours` | Planned batch duration, interpreted as hours in the supplied analysis and dashboard |

### `products`

| Column | Meaning in this analysis |
| --- | --- |
| `Product_ID` | Product identifier used to join batches to product names |
| `Product_Name` | Product name shown in the analysis |

## Derived views

### `dbo.downtimes`

Grain: one output row for each non-null factor cell in `line_downtime`.

| Column | Definition |
| --- | --- |
| `Batch_ID` | Batch identifier from `line_downtime` |
| `Factor_ID` | Integer obtained by removing `Factor_` from the source column name |
| `Minutes` | Recorded value from the factor column, in minutes |

### `dbo.batch_pd`

Grain: one output row per source row in `line_productivity_batches`.

| Column | Definition |
| --- | --- |
| `Start_Date` | `Date`, cast to a calendar date |
| `Product_ID` | Source product identifier |
| `Batch_ID` | Source batch identifier |
| `Operator` | Source operator |
| `End_Date` | Date extracted from the source end timestamp |
| `Start_Time` | Time component of the source start timestamp |
| `End_Time` | Time component of the source end timestamp |
| `Planned_min_Batch_Hours` | Source planned batch duration in hours |
| `Actual_Duration` | Difference between full source timestamps, calculated in seconds and converted to fractional hours |
| `Extra_Time_Hr` | `Actual_Duration` minus planned hours; negative values indicate completion before the planned duration |

## Joins and counting

- `line_productivity_batches.Product_ID` joins to `products.Product_ID`.
- `batch_pd.Batch_ID` joins to `downtimes.Batch_ID`.
- `downtimes.Factor_ID` joins to `downtime_factors.Factor_ID`.
- Distinct batch counts are used after the batch-to-downtime join so multiple factor entries do not inflate the batch denominator.

See the [SQL guide](SQL_GUIDE.md) for the distinction between recorded downtime entries and elapsed production overrun.
