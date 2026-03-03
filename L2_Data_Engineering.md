**Version: 1.0 | Date: 2026-03-04**
**Level: 2 | Domain: Data Engineering**
**Derived from:** [L1_Core_Principles.md](L1_Core_Principles.md) (Level 1, v3.8)

---

# Level 2 — Data Engineering Domain Rules

## Purpose

This artifact derives domain-specific rules for data engineering from the Level-1 Core Principles. These rules apply to all data pipeline, ETL/ELT, data warehouse, and analytics projects regardless of tooling (dbt, Airflow, Spark, etc.). They are declarative constraints (SHALL/SHALL NOT) that Level-3 workflows must operationalize.

> **Note:** Rule IDs are grouped by their parent L1 principle, not assigned sequentially. Gaps in numbering are intentional.

---

## Derived Rules

### From: Verifiability & Quality Assurance (L1)

**R-DE-01:** All data pipelines SHALL have automated data quality checks (schema validation, null checks, uniqueness constraints, referential integrity) enforced at pipeline boundaries (ingestion, transformation, output).

**R-DE-02:** All transformations SHALL be tested with representative sample data before deployment. Tests must cover happy path, null/missing data, duplicate records, and schema drift scenarios.

**R-DE-03:** Data freshness SLAs SHALL be defined for every production dataset. Pipeline monitoring SHALL alert when freshness thresholds are breached.

**R-DE-04:** All pipeline outputs SHALL be validated against an expected schema before writing to the target. Schema mismatches SHALL cause the pipeline to fail rather than silently corrupt downstream tables.

### From: Transparency/Traceability (L1)

**R-DE-05:** All data pipelines SHALL maintain end-to-end data lineage. For any output record, it must be possible to trace which source records, transformations, and pipeline runs produced it.

**R-DE-06:** Every pipeline run SHALL produce an execution log containing: run ID, start/end timestamps, records processed, records rejected, and error summaries.

**R-DE-07:** Schema changes to production tables SHALL be versioned and tracked through migration files (e.g., dbt migrations, Alembic, Flyway). Ad-hoc DDL changes SHALL NOT be applied directly to production.

### From: Safety & Security (L1)

**R-DE-08:** PII (Personally Identifiable Information) SHALL be identified, classified, and masked or encrypted at the point of ingestion. PII SHALL NOT propagate to analytics/reporting layers without explicit anonymization or pseudonymization.

**R-DE-09:** Access to production data stores SHALL follow the Principle of Least Privilege. Pipeline service accounts SHALL have only the minimum permissions required (e.g., `SELECT` on source, `INSERT` on target).

### From: Fail-Safe & Ask First (L1)

**R-DE-10:** All data pipelines SHALL be idempotent. Re-running a pipeline with the same inputs SHALL produce the same outputs without data duplication. This typically requires a merge/upsert strategy or partition-based overwrite.

**R-DE-11:** Pipeline failures SHALL NOT silently swallow errors. Failed runs SHALL be logged, alerted, and the pipeline SHALL NOT proceed to downstream steps until the failure is resolved or explicitly acknowledged.

### From: Separation of Concern (L1)

**R-DE-12:** Raw, staging, and serving/mart layers SHALL be physically separated (separate schemas, databases, or storage buckets). Direct queries from reporting tools against raw ingestion tables SHALL NOT be permitted.

**R-DE-13:** Transformation logic SHALL be separated from orchestration logic. Business rules live in transformation code (e.g., dbt models, Spark jobs), not in the scheduler/DAG definition.

### From: Efficiency / Pragmatism (L1)

**R-DE-14:** Incremental processing SHALL be preferred over full-refresh when the data volume and source system support it. Full-refresh SHALL only be used when incremental logic would be unreliable or more complex than the dataset justifies.

**R-DE-15:** Pipeline dependencies SHALL be explicitly declared in the DAG. Implicit timing-based dependencies ("this job runs after that one because it's scheduled 30 minutes later") SHALL NOT be used.

---

## Applicability

These rules apply to all data engineering projects governed by the AAIG framework, including ETL/ELT pipelines, data warehouses, lakehouses, and streaming systems. They are refined at Level 3 (workflows) and Level 4 (project bindings).

## Relationship to Skills Toolbox

- R-DE-01, R-DE-02, R-DE-04 → `data_quality.md`
- R-DE-05, R-DE-07 → `data_modeling.md`
- R-DE-10, R-DE-13, R-DE-15 → `data_pipeline_design.md`
- R-DE-08, R-DE-09 → `secrets_management.md`, `secure_coding.md`
- R-DE-06 → `monitoring_observability.md`, `structured_logging.md`
