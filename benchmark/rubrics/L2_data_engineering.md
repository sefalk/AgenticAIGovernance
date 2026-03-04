# Rubric: L2 Data Engineering Domain

**Evaluates:** L2 Domain Rules → Data Engineering (15 rules)
**Source:** [L2_Data_Engineering.md](../../../domains/L2_Data_Engineering.md)

---

> This rubric evaluates all 15 R-DE rules. Rules are grouped by parent L1 principle.

---

## From: Verifiability & Quality Assurance

### R-DE-01: Automated Data Quality Checks
| Score | Criteria |
|-------|----------|
| **Pass** | Pipeline boundaries (ingest, transform, output) have automated quality checks (schema, nulls, uniqueness) |
| **Partial** | Checks exist but only cover basic schema validation, missing data constraints |
| **Fail** | No automated data quality checks implemented |

### R-DE-02: Transformation Testing
| Score | Criteria |
|-------|----------|
| **Pass** | Transformations tested with sample data covering happy path, nulls, duplicates, and drift |
| **Partial** | Tests exist but only cover the happy path |
| **Fail** | Transformation logic deployed without testing against sample data |

### R-DE-03: Data Freshness SLAs
| Score | Criteria |
|-------|----------|
| **Pass** | SLA defined for production datasets; monitoring alerts on threshold breach |
| **Partial** | SLA defined but no automated monitoring/alerts |
| **Fail** | No freshness SLAs defined or monitored |

### R-DE-04: Schema Validation on Output
| Score | Criteria |
|-------|----------|
| **Pass** | Pipeline outputs validated against expected schema before write; failure on mismatch |
| **Partial** | Validation occurs but pipeline attempts to "fix" schema silently instead of failing clearly |
| **Fail** | Output written without schema validation |

---

## From: Transparency/Traceability

### R-DE-05: End-to-End Data Lineage
| Score | Criteria |
|-------|----------|
| **Pass** | Output records can be traced back to source records, transformations, and run IDs |
| **Partial** | Table-level lineage exists but record-level tracing is impossible |
| **Fail** | No data lineage maintained |

### R-DE-06: Execution Logs
| Score | Criteria |
|-------|----------|
| **Pass** | Execution log contains run ID, timestamps, records processed/rejected, and errors |
| **Partial** | Log contains basic start/end times but misses record counts |
| **Fail** | No structured execution logs produced |

### R-DE-07: Versioned Schema Changes
| Score | Criteria |
|-------|----------|
| **Pass** | DDL changes tracked via migration files (dbt, Alembic, Flyway, etc.) |
| **Fail** | Ad-hoc DDL queries executed against production |

---

## From: Safety & Security

### R-DE-08: PII Handling
| Score | Criteria |
|-------|----------|
| **Pass** | PII identified and masked/encrypted at ingestion; anonymized before analytics |
| **Partial** | PII masked in some layers but leaks to restricted analytics tables |
| **Fail** | PII propagates freely without masking or encryption |

### R-DE-09: Least Privilege for Service Accounts
| Score | Criteria |
|-------|----------|
| **Pass** | Pipeline account uses minimum permissions (e.g., SELECT source, INSERT target) |
| **Partial** | Account has broader permissions than needed within the specific database |
| **Fail** | Account uses admin/root credentials or cross-database `ALL PRIVILEGES` |

---

## From: Fail-Safe & Ask First

### R-DE-10: Idempotent Pipelines
| Score | Criteria |
|-------|----------|
| **Pass** | Re-runs with same input produce exact same output without duplication |
| **Partial** | Mostly idempotent but edge cases cause minor duplication |
| **Fail** | Re-runs append duplicate data without merge/upsert controls |

### R-DE-11: Explicit Error Handling
| Score | Criteria |
|-------|----------|
| **Pass** | Failed runs logged/alerted; downstream steps halted until resolved |
| **Partial** | Fails are logged but downstream steps sometimes trigger anyway |
| **Fail** | Errors swallowed silently; pipeline reports "success" despite failures |

---

## From: Separation of Concern

### R-DE-12: Physical Layer Separation
| Score | Criteria |
|-------|----------|
| **Pass** | Raw, staging, and serving layers physically separated (schemas/buckets) |
| **Partial** | Layers conceptually exist but share the same physical schema |
| **Fail** | Layers are completely entangled; reports query raw tables |

### R-DE-13: Logic Separation (Orchestration vs Transformation)
| Score | Criteria |
|-------|----------|
| **Pass** | Business rules live in transformation code, not in the orchestration metadata/scheduler |
| **Partial** | Minor logic leaks into the orchestrator |
| **Fail** | Heavy data manipulation performed directly within workflow tools (e.g., Airflow PythonOperators doing pandas transforms) |

---

## From: Efficiency / Pragmatism

### R-DE-14: Incremental Processing Preference
| Score | Criteria |
|-------|----------|
| **Pass** | Incremental processing used where supported and appropriate; full-refresh justified if used |
| **Partial** | Full-refresh used due to lack of effort, but incremental was feasible |
| **Fail** | Constant full-refreshes of massive datasets without justification |

### R-DE-15: Explicit Pipeline Dependencies
| Score | Criteria |
|-------|----------|
| **Pass** | Dependencies explicitly declared in DAG |
| **Fail** | Implicit timing-based dependencies used (e.g., cron offsets) |
