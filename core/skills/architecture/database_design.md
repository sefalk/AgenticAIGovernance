---
category: architecture
applies_to: [api, web, data]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [data_modeling, system_design]
---
# Database Design

## Purpose

Database design determines how data is stored, organized, queried, and maintained. Good design ensures data integrity, query performance, and maintainability. Invoke this skill when designing schemas, planning migrations, optimizing queries, or defining Level-3 data modeling workflows.

## Principles

- **Data integrity first:** The database is the last line of defense. Enforce constraints (NOT NULL, UNIQUE, FK, CHECK) in the schema, not just the application.
- **Query-driven design:** Design the schema around the queries you need to run, not around abstract data models.
- **Evolvability:** Schemas change. Design for safe, reversible migrations from day one.
- **Verifiability (AAIG L1):** Schema changes must be tested (migration correctness, query performance, constraint enforcement).

## Techniques & Patterns

### Relational Database Design

#### Normalization

| Normal Form | Rule | Purpose |
|-------------|------|---------|
| **1NF** | Atomic values, no repeating groups | Eliminate nested/repeated data |
| **2NF** | 1NF + no partial dependencies on composite keys | Eliminate redundancy in composite key tables |
| **3NF** | 2NF + no transitive dependencies | Eliminate redundancy from indirect dependencies |

**Guideline:** Normalize to 3NF by default. Denormalize deliberately for performance with documented justification.

#### Denormalization Techniques

| Technique | When to Use |
|-----------|-------------|
| **Computed columns** | Frequently queried derived values (e.g., `total_amount`) |
| **Materialized views** | Complex aggregation queries that run frequently |
| **Redundant columns** | Avoiding expensive JOINs on hot paths |
| **Summary tables** | Reporting/analytics on large datasets |

**Rule:** Every denormalization must document: what was denormalized, why, and how consistency is maintained.

#### Naming Conventions

```
Tables:       plural, snake_case         (users, order_items)
Columns:      snake_case                 (first_name, created_at)
Primary keys: id (or table_id)           (user_id)
Foreign keys: referenced_table_id        (order.user_id)
Indexes:      idx_table_columns          (idx_users_email)
Constraints:  type_table_columns         (uq_users_email, fk_orders_user_id)
```

#### Indexing Strategy

| Index Type | When to Use |
|-----------|-------------|
| **B-tree** (default) | Equality and range queries, ORDER BY |
| **Hash** | Equality-only lookups (PostgreSQL) |
| **GIN** | Full-text search, JSONB, arrays |
| **GiST** | Geospatial, range types |
| **Partial index** | `WHERE active = true` -- index only relevant rows |
| **Composite index** | Multi-column queries (`WHERE a = X AND b = Y`) |
| **Covering index** | INCLUDE non-key columns to avoid table lookups |

**Rules:**
- Index columns used in WHERE, JOIN, and ORDER BY.
- Composite index column order matters: most selective column first.
- Don't over-index: every index slows writes and consumes storage.
- Monitor unused indexes and remove them.

#### Query Optimization

```sql
-- Always use EXPLAIN ANALYZE to understand query plans
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 42;
```

| Problem | Solution |
|---------|----------|
| Full table scan on large table | Add appropriate index |
| N+1 query problem | Use JOINs or batch queries |
| Slow COUNT on large table | Use approximate counts or materialized counters |
| Expensive sort | Add index matching ORDER BY |
| Lock contention | Reduce transaction scope, use optimistic locking |

### Schema Migration

#### Migration Best Practices

```
migrations/
  001_create_users.sql         # up and down
  002_add_email_to_users.sql
  003_create_orders.sql
```

**Rules:**
- Every schema change is a versioned migration file.
- Migrations are idempotent (can be run multiple times safely).
- Every migration has a rollback (`down`) script.
- Test migrations on production-scale data before deploying.
- Never modify a migration that has been applied to any environment.

#### Zero-Downtime Migration Pattern

For adding a NOT NULL column to a live table:
```
Step 1: Add column as NULL (no lock)
Step 2: Backfill existing rows (batched)
Step 3: Add NOT NULL constraint (after backfill completes)
Step 4: Update application to write to new column
```

**Tools:** Flyway (Java), Alembic (Python), Knex/Prisma (JS/TS), golang-migrate (Go), EF Migrations (.NET).

### NoSQL Design Patterns

#### When to Use NoSQL

| Use Case | Database Type | Examples |
|----------|--------------|---------|
| Flexible schema, document storage | Document store | MongoDB, CouchDB |
| High-throughput key-value lookups | Key-value store | Redis, DynamoDB |
| Relationships and graph traversal | Graph database | Neo4j, Amazon Neptune |
| Time-series data | Time-series DB | InfluxDB, TimescaleDB |
| Wide-column analytics | Column-family | Cassandra, ScyllaDB |

#### Document Database Design

- **Embed when:** Data is read together, belongs together, and doesn't change independently.
- **Reference when:** Data is shared across documents, changes independently, or is unbounded.
- **Avoid unbounded arrays:** Arrays that grow indefinitely degrade performance.

#### Key-Value Design

- Key design is critical: use structured keys (`user:{id}:profile`, `session:{token}`).
- Set TTLs for ephemeral data (sessions, caches).
- Use atomic operations (INCR, SETNX) for counters and locks.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Constraints enforced** | All columns | NOT NULL, UNIQUE, FK, CHECK where appropriate. |
| **Migrations tested** | Up and down | Both apply and rollback must work on production-scale data. |
| **No unindexed queries on large tables** | 0 | All queries on tables > 10K rows must use indexes. |
| **Query performance** | p95 < 50ms | For application queries (not analytics). |
| **Naming conventions** | 100% compliant | Consistent naming across all tables and columns. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **EAV (Entity-Attribute-Value)** | Flexible but un-queryable, un-indexable, un-constrainable. | Use JSONB columns (PostgreSQL) or a document database if flexibility is needed. |
| **No foreign keys** | "We enforce it in the app." Data integrity eventually breaks. | Add FK constraints. The database outlives every application version. |
| **God table** | One table with 80 columns for everything. | Normalize. Split by domain concern. |
| **Premature denormalization** | Denormalizing before measuring performance. | Normalize first. Denormalize only when benchmarks show a need. |
| **No migrations** | Schema changes applied manually. | Use migration tooling. Always. |


## See Also

- [Data Modeling](../data_engineering/data_modeling.md)
- [System Design](../architecture/system_design.md)

## References

- Joe Celko, *SQL for Smarties* (2010) -- advanced SQL design patterns.
- Markus Winand, *SQL Performance Explained* (2012) -- indexing and query optimization.
- Use The Index, Luke: https://use-the-index-luke.com/
- Martin Kleppmann, *Designing Data-Intensive Applications* (2017) -- comprehensive data systems design.
