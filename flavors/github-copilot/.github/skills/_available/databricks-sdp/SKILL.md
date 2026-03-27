---
name: databricks-sdp
description: Lakeflow Spark Declarative Pipelines (SDP/DLT) — streaming tables, materialized views, Auto Loader ingestion, CDC/SCD patterns, medallion architecture, and serverless pipeline configuration.
argument-hint: '[focus: ingestion|streaming|cdc|medallion|performance]'
---

# Spark Declarative Pipelines (SDP)

Formerly Delta Live Tables (DLT). The managed pipeline framework for
Databricks — declarative table definitions, automatic dependency
resolution, and built-in data quality expectations.

## When to Use

- When building medallion architecture pipelines (bronze/silver/gold)
- When ingesting files with Auto Loader (`cloudFiles`)
- When implementing Change Data Capture (CDC) or SCD Type 1/2
- When creating streaming tables or materialized views
- When migrating from legacy DLT (`import dlt`) to modern SDP
  (`from pyspark import pipelines as dp`)

## Quick Reference

| Concept | Detail |
|---------|--------|
| **Python import** | `from pyspark import pipelines as dp` |
| **Decorators** | `@dp.table()`, `@dp.materialized_view()`, `@dp.temporary_view()` |
| **Replaces** | Delta Live Tables (DLT) with `import dlt` |
| **Compute** | Serverless by default (classic only for R, RDD, JAR) |
| **UC required** | Yes — Unity Catalog mandatory for serverless |
| **Docs** | https://docs.databricks.com/aws/en/ldp/ |

## Pipeline Structure

```
pipeline-project/
├── databricks.yml              # Bundle config with pipeline resource
├── resources/
│   └── pipeline.yml            # Pipeline definition
└── src/
    └── transformations/
        ├── bronze_orders.sql   # Bronze layer
        ├── silver_orders.sql   # Silver layer
        └── gold_summary.sql    # Gold layer
```

### Bundle Resource Definition

```yaml
# resources/pipeline.yml
resources:
  pipelines:
    my_pipeline:
      name: "[${bundle.target}] Order Pipeline"
      target: my_catalog.my_schema
      libraries:
        - notebook:
            path: ../src/transformations/
      configuration:
        env: ${bundle.target}
        schema_location_base: /Volumes/${var.catalog}/${var.schema}/metadata/schemas
```

## SQL Patterns

### Bronze — Auto Loader Ingestion

```sql
CREATE OR REFRESH STREAMING TABLE bronze_orders
CLUSTER BY (order_date)
AS
SELECT
  *,
  current_timestamp() AS _ingested_at,
  _metadata.file_path AS _source_file
FROM read_files(
  '/Volumes/catalog/schema/raw/orders/',
  format => 'json',
  schemaHints => 'order_id STRING, customer_id STRING, amount DECIMAL(10,2)'
);
```

### Silver — Cleaned and Validated

```sql
CREATE OR REFRESH STREAMING TABLE silver_orders (
  CONSTRAINT valid_order_id EXPECT (order_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_amount EXPECT (amount > 0) ON VIOLATION DROP ROW
)
CLUSTER BY (customer_id)
AS
SELECT
  order_id,
  customer_id,
  CAST(amount AS DECIMAL(10,2)) AS amount,
  order_date,
  _ingested_at
FROM STREAM(LIVE.bronze_orders);
```

### Gold — Aggregated Materialized View

```sql
CREATE OR REFRESH MATERIALIZED VIEW gold_daily_revenue
CLUSTER BY (order_date)
AS
SELECT
  order_date,
  COUNT(*) AS order_count,
  SUM(amount) AS total_revenue,
  AVG(amount) AS avg_order_value
FROM LIVE.silver_orders
GROUP BY order_date;
```

## Python Patterns

### Bronze — Auto Loader

```python
from pyspark import pipelines as dp
from pyspark.sql.functions import col, current_timestamp

schema_base = spark.conf.get("schema_location_base")

@dp.table(name="bronze_events", cluster_by=["event_date"])
def bronze_events():
    return (
        spark.readStream.format("cloudFiles")
        .option("cloudFiles.format", "json")
        .option("cloudFiles.schemaLocation", f"{schema_base}/bronze_events")
        .load("/Volumes/catalog/schema/raw/events/")
        .withColumn("_ingested_at", current_timestamp())
        .withColumn("_source_file", col("_metadata.file_path"))
    )
```

### Silver — Cleaned

```python
@dp.table(name="silver_events", cluster_by=["event_type"])
def silver_events():
    return (
        dp.read_stream("bronze_events")
        .filter("event_id IS NOT NULL")
        .filter("event_type IS NOT NULL")
        .dropDuplicates(["event_id"])
    )
```

### Gold — Materialized View

```python
from pyspark.sql.functions import count, sum as spark_sum

@dp.materialized_view(name="gold_event_summary")
def gold_event_summary():
    return (
        dp.read("silver_events")
        .groupBy("event_type", "event_date")
        .agg(
            count("*").alias("event_count"),
            spark_sum("value").alias("total_value")
        )
    )
```

## Data Quality Expectations

### SQL

```sql
CREATE OR REFRESH STREAMING TABLE validated_orders (
  CONSTRAINT valid_id EXPECT (id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT positive_amount EXPECT (amount > 0) ON VIOLATION FAIL UPDATE
)
AS SELECT * FROM STREAM(LIVE.raw_orders);
```

### Python

```python
@dp.table(
    name="validated_orders",
    expectations={
        "valid_id": dp.expect("id IS NOT NULL", on_violation="DROP"),
        "positive_amount": dp.expect("amount > 0", on_violation="FAIL"),
    }
)
def validated_orders():
    return dp.read_stream("raw_orders")
```

**Violation actions:**
- `DROP ROW` / `"DROP"` — silently drop failing rows
- `FAIL UPDATE` / `"FAIL"` — abort pipeline on violation

## Change Data Capture (AUTO CDC)

### SCD Type 1 (Latest Only)

```sql
CREATE OR REFRESH STREAMING TABLE dim_customers;

APPLY CHANGES INTO LIVE.dim_customers
FROM STREAM(LIVE.raw_customer_changes)
KEYS (customer_id)
SEQUENCE BY updated_at
STORED AS SCD TYPE 1;
```

### SCD Type 2 (Full History)

```sql
CREATE OR REFRESH STREAMING TABLE dim_customers;

APPLY CHANGES INTO LIVE.dim_customers
FROM STREAM(LIVE.raw_customer_changes)
KEYS (customer_id)
SEQUENCE BY updated_at
STORED AS SCD TYPE 2;
```

## Performance

| Technique | When | How |
|-----------|------|-----|
| **CLUSTER BY** | Always — replaces PARTITION BY and Z-ORDER | `CLUSTER BY (col1, col2)` |
| **Schema location** | Auto Loader with schema inference | `cloudFiles.schemaLocation` volume path |
| **Serverless** | Default — no cluster management | Omit cluster config |
| **Expectations** | Data quality without extra pipelines | `EXPECT ... ON VIOLATION` |

## Multi-Schema Patterns

**Default:** Single target schema per pipeline with name prefixes.

```python
# All tables in catalog.schema: bronze_*, silver_*, gold_*
@dp.table(name="bronze_orders")
@dp.table(name="silver_orders")
@dp.materialized_view(name="gold_summary")
```

For separate schemas, use pipeline configuration parameters:

```python
silver_schema = spark.conf.get("silver_schema")
gold_schema = spark.conf.get("gold_schema")

@dp.table(name=f"{silver_schema}.orders_clean")
@dp.materialized_view(name=f"{gold_schema}.daily_revenue")
```

## DLT → SDP Migration

| Legacy DLT | Modern SDP |
|------------|-----------|
| `import dlt` | `from pyspark import pipelines as dp` |
| `@dlt.table()` | `@dp.table()` |
| `@dlt.view()` | `@dp.temporary_view()` |
| `dlt.read()` | `dp.read()` |
| `dlt.read_stream()` | `dp.read_stream()` |
| `dlt.expect()` | `dp.expect()` |

## Common Commands

```bash
# Initialize new pipeline project
databricks pipelines init

# Deploy via bundle
databricks bundle deploy

# Run pipeline
databricks bundle run my_pipeline

# Validate config
databricks bundle validate
```

## Quality Gates

| Gate | Type | How to Verify |
|------|------|---------------|
| Pipeline validates without errors | HARD | `databricks bundle validate` |
| Serverless compute used (no classic clusters) | SOFT | Review pipeline config |
| CLUSTER BY used (not PARTITION BY) | HARD | Grep for PARTITION BY in SQL files |
| Schema location for Auto Loader | HARD | Verify `cloudFiles.schemaLocation` present |
| Data quality expectations defined | SOFT | Review bronze/silver tables |

## References

- SDP Overview: https://docs.databricks.com/aws/en/ldp/
- Python API: https://docs.databricks.com/aws/en/ldp/developer/python-ref
- SQL Reference: https://docs.databricks.com/aws/en/ldp/developer/sql-dev
- Auto Loader: https://docs.databricks.com/aws/en/ldp/load
- CDC: https://docs.databricks.com/aws/en/ldp/cdc
