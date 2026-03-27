---
name: databricks-synthetic-data
description: Generate realistic synthetic data using Spark + Faker + Pandas UDFs — weighted distributions, referential integrity, time patterns, and domain-specific generators for testing and demos.
argument-hint: '[focus: schema-design|distributions|referential-integrity|domains]'
---

# Synthetic Data Generation

Generate realistic, scalable synthetic data on Databricks using
Spark + Faker + Pandas UDFs.

## When to Use

- When creating test datasets for pipeline development
- When building demo environments with realistic data
- When generating data for property-based or integration testing
- When populating Unity Catalog tables for prototyping

## Approach Selection

| Approach | Scale | When |
|----------|-------|------|
| **Spark + Faker + Pandas UDFs** | 1K–100M+ rows | Default — scalable, parallel |
| **Polars / Pandas local** | < 30K rows | Quick prototyping, no cluster needed |
| **Hypothesis (property testing)** | Per-test | Automated test input generation |

## Quick Start: Spark + Faker

```python
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, DoubleType
import pandas as pd
import numpy as np

# Pandas UDFs for realistic data
@F.pandas_udf(StringType())
def fake_name(ids: pd.Series) -> pd.Series:
    from faker import Faker
    fake = Faker()
    return pd.Series([fake.name() for _ in range(len(ids))])

@F.pandas_udf(StringType())
def fake_email(ids: pd.Series) -> pd.Series:
    from faker import Faker
    fake = Faker()
    return pd.Series([fake.email() for _ in range(len(ids))])

@F.pandas_udf(DoubleType())
def lognormal_amount(tiers: pd.Series) -> pd.Series:
    params = {"Enterprise": (7.5, 0.8), "Pro": (5.5, 0.7), "Free": (4.0, 0.6)}
    return pd.Series([
        float(np.random.lognormal(*params.get(t, (4.0, 0.6))))
        for t in tiers
    ])

# Generate master table
customers_df = (
    spark.range(0, 10000, numPartitions=16)
    .select(
        F.concat(F.lit("CUST-"), F.lpad("id", 5, "0")).alias("customer_id"),
        fake_name(F.col("id")).alias("name"),
        fake_email(F.col("id")).alias("email"),
        F.when(F.rand() < 0.6, "Free")
         .when(F.rand() < 0.9, "Pro")
         .otherwise("Enterprise").alias("tier"),
    )
)

# Save to Unity Catalog
CATALOG = "my_catalog"
SCHEMA = "test_data"
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.{SCHEMA}")
customers_df.write.mode("overwrite").saveAsTable(f"{CATALOG}.{SCHEMA}.customers")
```

## Distribution Patterns

### Weighted Categories

```python
# 60% Free, 30% Pro, 10% Enterprise
F.when(F.rand() < 0.6, "Free")
 .when(F.rand() < 0.9, "Pro")
 .otherwise("Enterprise")
```

### Log-Normal Amounts (Realistic Pricing)

```python
@F.pandas_udf(DoubleType())
def generate_amount(tiers: pd.Series) -> pd.Series:
    tier_params = {
        "Enterprise": (7.5, 0.8),  # mean ~$1800
        "Pro": (5.5, 0.7),         # mean ~$245
        "Free": (4.0, 0.6),        # mean ~$55
    }
    return pd.Series([
        round(float(np.random.lognormal(*tier_params.get(t, (4.0, 0.6)))), 2)
        for t in tiers
    ])
```

### Date Range (Last N Months)

```python
from datetime import datetime, timedelta

END = datetime.now()
START = END - timedelta(days=180)
RANGE_DAYS = (END - START).days

# Random date in range
F.date_add(F.lit(START.date()), (F.rand() * RANGE_DAYS).cast("int"))
```

### Status Distribution

```python
F.when(F.rand() < 0.65, "delivered")
 .when(F.rand() < 0.80, "shipped")
 .when(F.rand() < 0.90, "processing")
 .when(F.rand() < 0.95, "pending")
 .otherwise("cancelled")
```

## Referential Integrity

**Rule:** Create master tables first, then generate child tables with
valid foreign keys by joining or sampling.

```python
# Step 1: Create and save master table
customers_df.write.mode("overwrite").saveAsTable(f"{CATALOG}.{SCHEMA}.customers")

# Step 2: Read back master keys
customer_keys = spark.table(f"{CATALOG}.{SCHEMA}.customers").select("customer_id")

# Step 3: Generate child table with valid FKs
orders_df = (
    spark.range(0, 50000, numPartitions=32)
    .join(
        customer_keys.orderBy(F.rand()).limit(50000),
        how="cross"  # or sample with replacement
    )
    .select(
        F.concat(F.lit("ORD-"), F.lpad("id", 7, "0")).alias("order_id"),
        F.col("customer_id"),
        # ... more columns
    )
)
```

**IMPORTANT:** Never use `.cache()` or `.persist()` with serverless
compute — write to Delta first, then read back for FK joins.

## Domain Templates

### E-Commerce

| Table | Key Columns | Rows |
|-------|-------------|------|
| customers | customer_id, name, email, tier, region | 5K–50K |
| products | product_id, name, category, price | 500–5K |
| orders | order_id, customer_id (FK), product_id (FK), amount, status, order_date | 50K–500K |

### IoT / Telemetry

| Table | Key Columns | Rows |
|-------|-------------|------|
| devices | device_id, device_type, location, firmware_version | 1K–10K |
| readings | reading_id, device_id (FK), timestamp, metric, value | 100K–10M |
| alerts | alert_id, device_id (FK), severity, message | 5K–50K |

### Support / CRM

| Table | Key Columns | Rows |
|-------|-------------|------|
| agents | agent_id, name, team, skill_level | 50–500 |
| tickets | ticket_id, customer_id (FK), agent_id (FK), category, priority, status | 10K–100K |

## Quality Gates

| Gate | Type | How to Verify |
|------|------|---------------|
| FK references valid master keys | HARD | Join check — zero orphans |
| Row counts match specification | SOFT | Count after generation |
| Distribution matches plan | SOFT | Sample and verify percentages |
| No PII in synthetic data | HARD | Faker generates fake data only |

## References

- Faker: https://faker.readthedocs.io/
- PySpark Pandas UDFs: https://spark.apache.org/docs/latest/api/python/user_guide/sql/arrow_pandas.html
