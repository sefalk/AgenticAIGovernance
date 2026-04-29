---
name: idempotent-operations
description: Design operations that can be safely retried by autonomous agents without causing unintended side effects — idempotency keys, UPSERTs, guard clauses, and retry-safe patterns.
argument-hint: '[domain: api|database|workflow|scripts] [focus: design|testing|debugging]'
metadata:
  activation:
    signals:
      python_packages: [fastapi, celery, sqlalchemy, sqlmodel]
    agents: [implementer, refactorer]
    priority: recommended
---

# Idempotent Operations

## When to Use

- When designing APIs or database operations that may be retried
- When writing agent scripts or shell commands that must be re-runnable
- When building data pipelines with safe replay semantics

## Principles

1. **Safety in Repetition:** Executing an operation once must have the exact same system state outcome as executing it 100 times. (Fail-Safe)
2. **Explicit State Verification:** Before mutating state, agents and their code must verify if the desired state has already been achieved. (Verifiability)

## Techniques & Patterns

### 1. API Design
- **Idempotency Keys:** All state-mutating requests (POST, PATCH) must require an `Idempotency-Key` header. The server guarantees that multiple requests with the same key within a window will only execute once.
- **PUT over POST:** When defining resource creation, prefer `PUT /resource/{id}` (which is naturally idempotent) over `POST /resource` if the client can determine the ID.

### 2. Database Operations
- **UPSERTs:** Instead of writing `INSERT` (which fails on retry due to unique constraints) or `SELECT then INSERT` (which suffers from race conditions), use native `INSERT ... ON CONFLICT DO UPDATE` (Postgres) or `MERGE` statements.
- **Soft Deletes:** `DELETE` operations should be implemented as soft deletes (`deleted_at = NOW()`) so subsequent retries return a 200/204 rather than a 404.

### 3. Workflow Design (Agent Actions)
- **Guard Clauses:** Shell scripts or bash commands written by the agent must begin with a state check. Rather than running `mkdir output`, write `mkdir -p output` or `if [ ! -d "output" ]; then mkdir output; fi`.

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| **API linter** | Enforced | OpenAPI specs must enforce `Idempotency-Key` header for non-idempotent HTTP methods (POST, PATCH) on critical endpoints. |
| **Retry testing** | Required | Integration tests must explicitly call state-mutating endpoints twice with the same payload to assert the database state remains unchanged on the second attempt. |

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
|---|---|---|
| **Blind Retries** | An agent retries a failed payment API call without passing a transaction ID, charging the customer twice. | Always generate an Idempotency Key (UUID) before the first attempt and reuse it. |
| **Check-Then-Act Race Conditions** | `if (!exists) { insert }` relies on application-level locks, which fail under concurrency. | Use database-level constraints and atomic `UPSERT` operations. |
| **Non-Retryable Shell Commands** | An agent script runs `echo "config" >> file.conf`. Run twice, the config is duplicated. | Make scripts idempotent (e.g., use `sed` or check if the string exists before appending). |
