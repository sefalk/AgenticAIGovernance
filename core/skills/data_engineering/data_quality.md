---
category: data_engineering
applies_to: [data]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [data_pipeline_design, data_modeling, exploratory_data_analysis, feature_engineering, compliance_regulatory]
---
# Data Quality

## Purpose

Data quality ensures that data is accurate, complete, consistent, timely, and fit for its intended use. Poor data quality leads to wrong decisions, failed pipelines, and eroded trust. Invoke this skill when building data validation into pipelines, defining quality SLAs, or creating Level-3 data quality workflows.

## Principles

- **Quality at the source:** Validate data as close to the source as possible. Don't propagate bad data downstream.
- **Quantitative, not qualitative:** Data quality must be measured with specific, automated checks -- not "looks good."
- **Verifiability (AAIG L1):** Every data quality assertion must be programmatically verifiable.
- **Transparency (AAIG L1):** Quality check results must be documented and accessible.

## Techniques & Patterns

### Data Quality Dimensions

| Dimension | Definition | Example Check |
|-----------|-----------|---------------|
| **Completeness** | No unexpected missing values | `NOT NULL` checks, missing rate < 1% |
| **Accuracy** | Values reflect reality | Values within valid ranges, regex patterns match |
| **Consistency** | Same data tells the same story across systems | Cross-source reconciliation |
| **Timeliness** | Data is fresh enough for its use case | Data loaded within SLA window |
| **Uniqueness** | No unintended duplicates | Primary key uniqueness, dedup checks |
| **Validity** | Values conform to expected formats/domains | Email format, ISO date format, enum membership |
| **Referential integrity** | Foreign keys point to existing records | No orphaned references |

### Validation Framework

```
Source Data
    |
    v
[Schema Validation]  -->  Reject malformed records
    |
    v
[Business Rules]     -->  Flag/reject rule violations
    |
    v
[Statistical Checks] -->  Alert on distribution anomalies
    |
    v
[Cross-Source Recon]  -->  Reconcile counts/sums across systems
    |
    v
Validated Data
```

### Tooling

| Tool | Approach | Best For |
|------|----------|----------|
| **Great Expectations** | Python, declarative expectations, data docs | Comprehensive validation framework |
| **dbt tests** | SQL-based, built into dbt | Transform-layer testing (ELT) |
| **Soda** | YAML-based checks, cloud SaaS option | Simple declarative checks |
| **Pandera** | Python, pandas/polars schema validation | DataFrame validation |
| **Deequ** | Spark, Amazon-backed | Large-scale Spark pipelines |
| **Elementary** | dbt-native monitoring | Anomaly detection for dbt projects |

### Great Expectations Example

```python
import great_expectations as gx

context = gx.get_context()
datasource = context.sources.add_pandas("my_source")
asset = datasource.add_dataframe_asset("orders")

# Define expectations
batch = asset.get_batch(dataframe=df)
batch.expect_column_values_to_not_be_null("order_id")
batch.expect_column_values_to_be_between("amount", min_value=0, max_value=1_000_000)
batch.expect_column_values_to_match_regex("email", r"^[^@]+@[^@]+\.[^@]+$")
batch.expect_column_values_to_be_in_set("status", ["pending", "paid", "shipped", "cancelled"])
batch.expect_compound_columns_to_be_unique(["order_id", "line_item_id"])

# Validate
results = batch.validate()
assert results.success, f"Data quality check failed: {results}"
```

### dbt Tests Example

```yaml
# schema.yml
models:
  - name: orders
    columns:
      - name: order_id
        tests:
          - not_null
          - unique
      - name: amount
        tests:
          - not_null
          - dbt_utils.accepted_range:
              min_value: 0
              max_value: 1000000
      - name: status
        tests:
          - accepted_values:
              values: ['pending', 'paid', 'shipped', 'cancelled']
      - name: customer_id
        tests:
          - relationships:
              to: ref('customers')
              field: customer_id
```

### Anomaly Detection

Beyond static rules, monitor data for anomalies over time:

| Check | Description |
|-------|-------------|
| **Volume anomaly** | Row count deviates significantly from historical pattern |
| **Freshness check** | Data hasn't been updated within expected window |
| **Distribution shift** | Column value distribution changes unexpectedly |
| **Null rate spike** | Null percentage suddenly increases |
| **Schema drift** | New columns appear or existing columns change type |

**Tools:** Elementary, Monte Carlo, Great Expectations with profiling, Soda anomaly checks.

### Data Quality SLA

| Metric | Example SLA |
|--------|-------------|
| **Completeness** | < 0.5% null rate for required fields |
| **Freshness** | Data available within 2 hours of source update |
| **Accuracy** | > 99.5% of records pass all validation rules |
| **Uniqueness** | 0 duplicate primary keys |
| **Reconciliation** | Source vs. destination counts match within 0.1% |

### Data Contracts

Formal agreements between data producers and consumers:

```yaml
# data_contract.yml
name: orders
owner: team-checkout
version: 2.0
schema:
  - name: order_id
    type: string
    required: true
    unique: true
  - name: amount
    type: decimal
    required: true
    constraints: { min: 0 }
quality:
  freshness: 2h
  completeness: 99.5%
  volume: { min_rows_per_day: 1000 }
```

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Schema validation** | 100% pass | All records conform to expected schema. |
| **Business rule checks** | 100% pass | All defined rules pass. Failures block pipeline. |
| **Anomaly detection** | No critical anomalies | Volume, freshness, distribution within bounds. |
| **Reconciliation** | Counts match within 0.1% | Source vs. destination record counts. |
| **Freshness** | Within SLA | Data loaded within defined time window. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **No validation** | Bad data flows downstream. Garbage in, garbage out. | Add validation at every pipeline stage. |
| **Validate only at the end** | Debugging requires tracing back through the entire pipeline. | Validate at source, after transform, and at load. |
| **Static thresholds only** | "Amount < 1M" catches outliers but misses distribution shifts. | Combine static rules with anomaly detection. |
| **Quality checks that never fail** | Checks are too lenient to catch real issues. | Review and tighten thresholds quarterly. |
| **No data contracts** | Producer changes schema without telling consumers. Pipeline breaks. | Formalize data contracts between teams. |


## See Also

- [Data Pipeline Design](../data_engineering/data_pipeline_design.md)
- [Data Modeling](../data_engineering/data_modeling.md)

## References

- Great Expectations: https://greatexpectations.io/
- dbt tests: https://docs.getdbt.com/docs/build/data-tests
- Soda: https://www.soda.io/
- Chad Sanderson, ["Data Contracts"](https://dataproducts.substack.com/) -- data contracts methodology.
