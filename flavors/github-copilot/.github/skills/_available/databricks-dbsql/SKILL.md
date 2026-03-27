---
name: databricks-dbsql
description: Databricks SQL advanced features — SQL scripting, stored procedures, materialized views, pipe syntax, geospatial (H3/ST), collations, AI functions, and data modeling best practices.
argument-hint: '[focus: scripting|procedures|materialized-views|geospatial|ai-functions]'
---

# Databricks SQL (DBSQL)

Advanced SQL features for Databricks SQL warehouses.

## When to Use

- When writing stored procedures or SQL scripting blocks
- When creating materialized views with scheduled refresh
- When using AI functions (`ai_query`, `ai_classify`, `ai_extract`)
- When working with geospatial data (H3, ST_ functions)
- When using pipe syntax (`|>`) for readable transformations
- When configuring case-insensitive collations

## Feature Reference

| Feature | Syntax | Since |
|---------|--------|-------|
| SQL Scripting | `BEGIN...END`, `DECLARE`, `IF/WHILE/FOR` | DBR 16.3+ |
| Stored Procedures | `CREATE PROCEDURE`, `CALL` | DBR 17.0+ |
| Recursive CTEs | `WITH RECURSIVE` | DBR 17.0+ |
| Materialized Views | `CREATE MATERIALIZED VIEW` | Pro/Serverless |
| Temp Tables | `CREATE TEMPORARY TABLE` | All |
| Pipe Syntax | `\|>` operator | DBR 16.1+ |
| Geospatial (H3) | `h3_longlatash3()` | DBR 11.2+ |
| Geospatial (ST) | `ST_Point()`, `ST_Contains()`, 80+ funcs | DBR 16.0+ |
| Collations | `COLLATE UTF8_LCASE` | DBR 16.1+ |
| AI Functions | `ai_query()`, `ai_classify()`, 11+ funcs | DBR 15.1+ |

## SQL Scripting

### Procedural ETL Block

```sql
BEGIN
  DECLARE v_count INT;
  DECLARE v_status STRING DEFAULT 'pending';

  SET v_count = (SELECT COUNT(*) FROM catalog.schema.raw_orders
                 WHERE status = 'new');

  IF v_count > 0 THEN
    INSERT INTO catalog.schema.processed_orders
    SELECT *, current_timestamp() AS processed_at
    FROM catalog.schema.raw_orders WHERE status = 'new';
    SET v_status = 'completed';
  ELSE
    SET v_status = 'skipped';
  END IF;

  SELECT v_status AS result, v_count AS rows_processed;
END
```

### Stored Procedure with Error Handling

```sql
CREATE OR REPLACE PROCEDURE catalog.schema.upsert_customers(
  IN p_source STRING,
  OUT p_rows_affected INT
)
LANGUAGE SQL
SQL SECURITY INVOKER
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    SET p_rows_affected = -1;
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = concat('Upsert failed for source: ', p_source);
  END;

  MERGE INTO catalog.schema.dim_customer AS t
  USING (SELECT * FROM identifier(p_source)) AS s
  ON t.customer_id = s.customer_id
  WHEN MATCHED THEN UPDATE SET *
  WHEN NOT MATCHED THEN INSERT *;

  SET p_rows_affected = (SELECT COUNT(*) FROM identifier(p_source));
END;

-- Invoke:
CALL catalog.schema.upsert_customers('catalog.schema.staging', ?);
```

## Materialized Views

```sql
CREATE OR REPLACE MATERIALIZED VIEW catalog.schema.daily_revenue
  CLUSTER BY (order_date)
  SCHEDULE EVERY 1 HOUR
  COMMENT 'Hourly-refreshed daily revenue by region'
AS SELECT
    order_date,
    region,
    SUM(amount) AS total_revenue,
    COUNT(DISTINCT customer_id) AS unique_customers
FROM catalog.schema.fact_orders
JOIN catalog.schema.dim_store USING (store_id)
GROUP BY order_date, region;
```

## Pipe Syntax

Readable, top-to-bottom data transformations:

```sql
FROM catalog.schema.fact_orders
  |> WHERE order_date >= current_date() - INTERVAL 30 DAYS
  |> AGGREGATE SUM(amount) AS total, COUNT(*) AS cnt
     GROUP BY region, product_category
  |> WHERE total > 10000
  |> ORDER BY total DESC
  |> LIMIT 20;
```

## AI Functions

```sql
-- Classify text
SELECT
  ticket_id,
  ai_classify(description,
    ARRAY('billing', 'technical', 'account', 'feature_request')
  ) AS category,
  ai_analyze_sentiment(description) AS sentiment
FROM catalog.schema.support_tickets
LIMIT 100;

-- Extract entities
SELECT
  doc_id,
  ai_extract(content,
    ARRAY('person_name', 'company', 'dollar_amount')
  ) AS entities
FROM catalog.schema.contracts;

-- General-purpose query with structured output
SELECT ai_query(
  'databricks-meta-llama-3-3-70b-instruct',
  concat('Summarize: ', feedback),
  returnType => 'STRUCT<topic STRING, sentiment STRING>'
) AS analysis
FROM catalog.schema.feedback
LIMIT 50;
```

## Geospatial

### H3 Indexing

```sql
SELECT
  h3_longlatash3(longitude, latitude, 7) AS h3_cell,
  COUNT(*) AS event_count
FROM catalog.schema.events
GROUP BY h3_cell;
```

### ST Functions — Proximity Search

```sql
SELECT
  c.customer_id,
  s.store_id,
  ST_Distance(
    ST_Point(c.longitude, c.latitude),
    ST_Point(s.longitude, s.latitude)
  ) AS distance_m
FROM catalog.schema.customers c
CROSS JOIN catalog.schema.stores s
WHERE ST_Distance(
  ST_Point(c.longitude, c.latitude),
  ST_Point(s.longitude, s.latitude)
) < 5000;
```

## Collations

```sql
-- Case-insensitive column
CREATE TABLE catalog.schema.products (
  product_id BIGINT GENERATED ALWAYS AS IDENTITY,
  name STRING COLLATE UTF8_LCASE,
  category STRING COLLATE UTF8_LCASE
);

-- No LOWER() needed — case-insensitive automatically
SELECT * FROM catalog.schema.products
WHERE name = 'MacBook Pro';  -- matches 'macbook pro', 'MACBOOK PRO'
```

## Data Modeling Best Practices

### Star Schema

```sql
-- Fact table: Liquid Clustering on common filter columns
CREATE TABLE catalog.schema.fact_orders (
  order_id BIGINT,
  customer_key BIGINT,
  product_key BIGINT,
  order_date DATE,
  amount DECIMAL(10,2)
) CLUSTER BY (order_date, customer_key);

-- Dimension table
CREATE TABLE catalog.schema.dim_customer (
  customer_key BIGINT GENERATED ALWAYS AS IDENTITY,
  customer_id STRING,
  name STRING,
  tier STRING
);
```

### Liquid Clustering (Replaces Z-ORDER)

```sql
-- Create with clustering
CREATE TABLE t CLUSTER BY (col1, col2);

-- Add clustering to existing table
ALTER TABLE t CLUSTER BY (col1, col2);

-- Remove clustering
ALTER TABLE t CLUSTER BY NONE;
```

## Quality Gates

| Gate | Type | How to Verify |
|------|------|---------------|
| Uses 3-level UC table references | HARD | No 2-level `schema.table` refs |
| CLUSTER BY instead of PARTITION BY | HARD | Grep for `PARTITION BY` |
| AI functions use approved models | SOFT | Review model endpoint names |
| Materialized views have refresh schedule | SOFT | Check SCHEDULE clause |

## References

- SQL Language Reference: https://docs.databricks.com/sql/language-manual/
- Databricks SQL Features: https://docs.databricks.com/sql/
- AI Functions: https://docs.databricks.com/en/large-language-models/ai-functions.html
- Geospatial: https://docs.databricks.com/en/sql/language-manual/functions/h3.html
