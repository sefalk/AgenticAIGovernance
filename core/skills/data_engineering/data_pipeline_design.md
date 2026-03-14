---
category: data_engineering
applies_to: [data]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [data_quality, data_modeling, monitoring_observability]
---
# Data Pipeline Design

## Purpose

Data pipeline design covers the architecture, patterns, and practices for building reliable systems that move and transform data between storage and processing systems. Invoke this skill when designing ETL/ELT pipelines, selecting orchestration tools, or defining Level-3 data engineering workflows.

## Principles

- **Idempotency:** Running a pipeline multiple times with the same input must produce the same result. This enables safe retries.
- **Observability:** Every pipeline must be monitorable: throughput, latency, error rates, data freshness.
- **Data integrity:** No silent data loss. Every record is accounted for -- processed, skipped (with reason), or failed (with error).
- **Verifiability (AAIG L1):** Pipeline correctness must be programmatically verifiable via data quality checks.

## Techniques & Patterns

### ETL vs ELT

| Pattern | Process | When to Use |
|---------|---------|-------------|
| **ETL** (Extract, Transform, Load) | Transform before loading into the destination | Limited destination compute, complex transformations |
| **ELT** (Extract, Load, Transform) | Load raw data, then transform in destination | Modern cloud warehouses (BigQuery, Snowflake, Redshift) |

**Modern default:** ELT. Cloud warehouses are optimized for transformation at scale. Load raw data, transform with SQL.

### Orchestration Tools

| Tool | Language | Key Features |
|------|----------|-------------|
| **Airflow** | Python | DAG-based, extensive operator library, most widely adopted |
| **Dagster** | Python | Software-defined assets, type checking, built-in testing |
| **Prefect** | Python | Pythonic, dynamic workflows, cloud-native |
| **dbt** | SQL/YAML | Transform-only (the T in ELT), testing built-in, lineage |
| **Mage** | Python | Modern UI, data-aware, integrated notebooks |

### Pipeline Architecture Patterns

#### Batch Processing
```
Source --> Extract --> Stage (raw) --> Transform --> Load (final) --> Quality Check
                                         |
                                    Data Quality
                                     Validation
```

**Best practices:**
- Process data in bounded time windows (daily, hourly).
- Use staging/raw layer to preserve source data before transformation.
- Implement checkpoint/restart for long-running pipelines.

#### Stream Processing
```
Source --> Message Broker --> Stream Processor --> Sink
(events)  (Kafka, Kinesis)   (Flink, Spark      (DB, warehouse,
                              Streaming, ksqlDB)  another topic)
```

**When to use:** Real-time analytics, event-driven architectures, sub-second latency requirements.

**Tools:** Apache Kafka + Flink, Spark Structured Streaming, ksqlDB, Amazon Kinesis.

#### Lambda Architecture
```
Batch Layer:  Source --> Batch Processing --> Serving Layer
Speed Layer:  Source --> Stream Processing --> Serving Layer (real-time view)
```

**When to use:** When you need both accurate historical analytics and real-time views. Complex to maintain -- prefer Kappa architecture (stream-only) when possible.

### Idempotency Patterns

| Pattern | Description |
|---------|-------------|
| **Upsert / Merge** | Insert or update based on a natural key. Same input = same result. |
| **Partition overwrite** | Delete and recreate an entire partition (date, region). Atomic replacement. |
| **Deduplication** | Assign unique IDs to records. Ignore duplicates on re-processing. |
| **Checkpointing** | Record progress. On restart, resume from last checkpoint. |

### Error Handling

| Strategy | Description |
|----------|-------------|
| **Dead letter queue (DLQ)** | Route failed records to a separate queue for inspection and replay. |
| **Retry with backoff** | Retry transient failures (network, throttling) with exponential backoff. |
| **Skip and log** | For non-critical records, log the failure and continue. |
| **Circuit breaker** | Stop processing if error rate exceeds threshold. Alert and await intervention. |

**Rule:** Never silently drop records. Every record must be accounted for: processed, retried, or sent to DLQ.

### Testing Pipelines

| Level | What to Test | How |
|-------|-------------|-----|
| **Unit** | Individual transformations | Test functions with sample data (pytest, unittest) |
| **Integration** | Source/sink connectivity | Test containers with real databases |
| **Data quality** | Output correctness | Great Expectations, dbt tests, custom assertions |
| **E2E** | Full pipeline run | Run pipeline on test data, validate output |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Zero data loss** | All records accounted for | Input count = output count + DLQ count + skipped count. |
| **Idempotent** | Verified | Running the pipeline twice produces the same result. |
| **Data freshness** | SLA-defined | Data arrives within the agreed time window. |
| **Quality checks pass** | 100% | All data quality assertions pass post-load. |
| **Monitoring active** | All pipelines | Throughput, latency, error rate dashboards. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Silent failures** | Pipeline "succeeds" but drops records. Nobody notices for weeks. | Count records at every stage. DLQ for failures. Quality checks. |
| **Non-idempotent writes** | Re-running duplicates data. | Use upsert, partition overwrite, or deduplication. |
| **Monolithic pipeline** | One 10,000-line DAG that does everything. | Break into composable, testable stages. |
| **No staging layer** | Raw source data is immediately transformed. Can't debug or replay. | Always land raw data first, then transform. |
| **Manual scheduling** | "I run the pipeline every Monday morning." | Use an orchestrator with scheduling, retries, and alerting. |


## See Also

- [Data Quality](../data_engineering/data_quality.md)
- [Data Modeling](../data_engineering/data_modeling.md)
- [Monitoring and Observability](../devops/monitoring_observability.md)

## References

- Maxime Beauchemin, *The Rise of the Data Engineer* (2017) -- foundational essay.
- Martin Kleppmann, *Designing Data-Intensive Applications* (2017), Ch. 10-11 -- batch and stream processing.
- Apache Airflow: https://airflow.apache.org/
- Dagster: https://dagster.io/
- dbt: https://www.getdbt.com/
