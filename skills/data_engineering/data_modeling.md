---
title: Data Modeling
description: Designing data structures for modern analytical stacks using schemas, dimensional models, and contracts
applies_to: [data, cloud, api]
complexity: advanced
maturity: draft
version: "2.0"
last_reviewed: 2026-02-26
related: [database_design, data_pipeline_design, data_quality, exploratory_data_analysis, feature_engineering, compliance_regulatory]
---
# Data Modeling

## Purpose
To structure data so it is simultaneously cost-efficient to query, intuitive for analysts and machine learning models to consume, and robust against upstream schema changes in the modern data stack (Snowflake, BigQuery, dbt).

## Principles
1. **Model for the Consumer:** The shape of analytical data must serve downstream needs (BI tools, ML models). Do not expose highly normalized, complex transactional (OLTP) schemas directly to analytical (OLAP) consumers.
2. **Immutability & Idempotency:** Data models should be built via idempotent transformations. Running a pipeline twice must yield the same result. The raw, ingested data must never be mutated; apply models downstream. *(AAIG L1: Fail-Safe)*
3. **Data as a Product:** Data models should have explicit owners, documentation, and Service Level Agreements (SLAs) regarding freshness and quality.
4. **Schema Evolution:** Architect models anticipating that upstream sources will drop columns, change types, and add fields. Fail explicitly on breaking changes. *(AAIG L1: Safety & Security)*

## Techniques & Patterns

### 1. Modern Dimensional Modeling (dbt methodology)
*   **Staging Layer:** A 1:1 view over raw data. Standardize naming (snake_case), cast types (`VARCHAR` to `TIMESTAMP`), and handle basic deduplication.
*   **Intermediate Layer:** Join tables, calculate business logic, and flatten complex JSON structures.
*   **Mart / Dimension Layer (Star Schema):** Expose wide, denormalized `dim_` (Dimensions: Who, What, Where) and `fct_` (Facts: quantifiable events) tables. This eliminates complex joins for end-users relying on Tableau/Looker.

### 2. Schema Registries and Contracts
*   **Schema Registry (Kafka/Event Streams):** For streaming ingestion, enforce schemas (Avro, Protobuf, JSON Schema) at the producer level. The schema registry rejects non-compliant events before they enter the data lake.
*   **Data Contracts:** Define a contract (YAML/JSON) between software engineers (data producers) and data engineers (data consumers) specifying column names, types, and constraints. Changing the software DB schema fails CI if it breaks the Data Contract.

### 3. Handling Change (SCDs)
*   **Slowly Changing Dimensions (SCD Type 2):** When a user updates their address in the operational DB, do not overwrite their old address in the warehouse. Create a new row with `valid_from` and `valid_to` timestamps to preserve historical accuracy for ML training and analytics.

### 4. Partitioning and Clustering
*   **Partitioning:** Physically divide large tables by a coarse temporal key (e.g., `event_date`). This allows query engines (BigQuery/Snowflake) to scan megabytes instead of terabytes, slashing costs.
*   **Clustering:** Sort data within partitions by frequently filtered columns (e.g., `customer_id`) to speed up specific lookups.

## Quality Gates
*   **dbt Tests:** Every primary key in the Mart layer has `unique` and `not_null` tests. Every foreign key has a `relationships` (referential integrity) test.
*   **Schema Anomaly Detection:** CI runs `dbt source freshness` and generic tests before merging changes to dimension models.
*   **Data Quality Validation:** Dedicated jobs (via Great Expectations, Soda, or dbt-expectations) run post-load to verify statistical distribution of data (e.g., `order_total` must be > 0 and < 100,000 in 99.9% of cases).
*   **Cost Spikes:** Bounding limiters prevent queries that attempt a full table scan over datasets larger than 1TB without a partition filter.

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **One Big Table (OBT) for Everything** | Denormalizing an entire company's data into a 400-column table slows down queries, spikes warehouse costs, and confuses users. | Build focused Star Schema datamarts (`fct_sales`, `dim_customer`) for specific domains. |
| **Silent Failures on Schema Changes** | An upstream API renames `user_id` to `customer_id`. The pipeline inserts `NULLs` for 3 weeks before anyone notices. | Enforce Data Contracts and Schema Registries to block bad payloads at the source. |
| **"Select * " Views** | Materializing `SELECT * FROM table` creates fragile models that explode if an upstream table drops a column. | Explicitly name every column in the `SELECT` statement in staging models. |
| **Updating the Raw Data** | Someone realizes historical data was wrong and runs an `UPDATE` statement directly on the raw ingested layer. | Maintain raw data immutably. Fix history via a documented, reproducible dbt transformation. |

## See Also
*   [Data Pipeline Design](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/data_engineering/data_pipeline_design.md)
*   [Data Quality](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/data_engineering/data_quality.md)

## References
*   [dbt Best Practices](https://docs.getdbt.com/docs/build/project-structure)
*   [The Data Warehouse Toolkit (Kimball Group)](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/)
*   [Data Contracts (Gaelim Weaver)](https://datacontract.com/)
