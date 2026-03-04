**Version: 1.0 | Date: 2026-03-04**
**Level: 3 | Domain: Data Engineering**
**Derived from:** [L2_Data_Engineering.md](../domains/L2_Data_Engineering.md) (Level 2)
**Operationalizes:** R-DE-01, R-DE-02, R-DE-04, R-DE-05, R-DE-10, R-DE-12, R-DE-13, R-DE-15

---

# L3 Workflow — Data Pipeline Development

## Purpose

This workflow defines the standard procedure for developing, testing, and deploying a data pipeline (ETL/ELT job, dbt model, Spark job, or streaming consumer). It ensures that data quality, idempotency, and lineage are validated before any pipeline reaches production.

> **Adaptation Note:** Bind `[L4-DEFINED]` placeholders during L4 Project Instantiation.

---

## Phases

### Phase 1: Design & Schema
**Entry Criteria:** A data requirement exists (new source integration, new mart/table, schema change).

1. **Check for an existing WIP contract:** If a `WIP.md` file exists on the current branch, read it first and resume from the last completed step.
2. Define the **source-to-target mapping:** which source tables/APIs feed which target tables.
3. Document the **expected schema** of the output (column names, types, nullability, uniqueness constraints) (R-DE-04).
4. Declare the **pipeline dependency graph** explicitly (R-DE-15). No implicit timing-based dependencies.
5. If the pipeline touches PII, classify the fields and document the masking/anonymization strategy (R-DE-08).

**Exit Criteria:** Schema design and dependency graph are documented.

---

### Phase 2: Develop & Unit Test
**Entry Criteria:** Phase 1 is complete.

1. Implement the transformation logic in the appropriate layer:
   - **Raw → Staging:** Schema normalization, type casting, deduplication.
   - **Staging → Mart:** Business logic, aggregations, joins.
2. Transformation logic MUST be separated from orchestration logic (R-DE-13).
3. Write unit tests with representative sample data covering (R-DE-02):
   - Happy path (valid data).
   - Null/missing values.
   - Duplicate records.
   - Schema drift (unexpected columns or type changes).
4. Verify idempotency: running the pipeline twice with the same input produces the same output without duplication (R-DE-10).

**Exit Criteria:** Transformation code and unit tests are complete.

---

### Phase 3: Schema & Quality Validation
**Entry Criteria:** Phase 2 passes.

1. Run the pipeline against a test/staging dataset.
2. Validate the output against the expected schema (R-DE-04). Mismatches are blocking failures.
3. Execute data quality checks (R-DE-01):
   - Row count within expected range.
   - No unexpected nulls in required columns.
   - Uniqueness constraints hold.
   - Referential integrity with related tables.
4. Verify that data lineage metadata is captured (R-DE-05).

**Exit Criteria:** Schema matches, all quality checks pass, lineage is recorded.

---

### Phase 4: Review & Merge
**Entry Criteria:** Phase 3 passes.

1. Create a PR linking to the data requirement ticket.
2. The PR must include:
   - Source-to-target mapping documentation.
   - Sample output (first N rows) from the test run.
   - Quality check results.
3. Review and merge per standard review process.

**Exit Criteria:** PR is approved and merged.

---

### Phase 5: Deploy & Monitor
**Entry Criteria:** Phase 4 is complete.

1. Deploy the pipeline/DAG to the production scheduler: `[L4-DEFINED: deployment command]`.
2. Trigger an initial production run (or wait for the next scheduled execution).
3. Verify data freshness SLA is met after the first production run (R-DE-03).
4. Confirm pipeline monitoring and alerting are active:
   - **Failure alerts:** Pipeline run failures trigger notifications.
   - **Freshness alerts:** SLA breaches trigger notifications.

**Exit Criteria:** Pipeline is deployed, first run succeeds, monitoring is active.

---

## Layer Separation Reference (R-DE-12)

```
[Source Systems]
       ↓
┌─────────────┐
│   Raw Layer  │  ← Exact copies of source data, append-only
└─────────────┘
       ↓
┌─────────────┐
│ Staging Layer│  ← Cleaned, typed, deduplicated
└─────────────┘
       ↓
┌─────────────┐
│ Mart / Serve │  ← Business logic applied, ready for consumption
└─────────────┘
```

---

## Mid-Task Interruption Protocol

If the agent must end a session before completing all phases, commit a `WIP.md` to the current branch:

```markdown
# Work In Progress
**Last Phase Completed:** [Phase N]
**Last Step Completed:** [exact step]
**Next Step:** [exact next step]
**Open Decisions:** [unresolved choices]
**Blockers:** [blockers preventing progress]
```

A resuming agent reads `WIP.md` in Phase 1 Step 1. The file is deleted when the PR is merged.
