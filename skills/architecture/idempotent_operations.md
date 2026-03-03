---
title: Agentic Idempotent Operations
description: Designing operations that can be safely retried by autonomous agents without causing unintended side effects.
applies_to: [api, microservice, data, cloud]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-03-04
related: [api_design, data_pipeline_design, error_handling]
---
# Agentic Idempotent Operations

## Purpose
This skill teaches agents to design systems that are resilient to automated retries. Autonomous AI agents operate in loops; if an agent encounters a timeout, it is likely to blindly retry its previous action. If the action is not idempotent (e.g., "Charge Credit Card"), a retry creates catastrophic duplication.

## Principles
1. **Safety in Repetition:** Executing an operation once must have the exact same system state outcome as executing it 100 times. *(AAIG L1: Fail-Safe)*
2. **Explicit State Verification:** Before mutating state, agents and their code must verify if the desired state has already been achieved. *(AAIG L1: Verifiability)*

## Techniques & Patterns

### 1. API Design
*   **Idempotency Keys:** All state-mutating requests (POST, PATCH) must require an `Idempotency-Key` header. The server guarantees that multiple requests with the same key within a window will only execute once.
*   **PUT over POST:** When defining resource creation, prefer `PUT /resource/{id}` (which is naturally idempotent) over `POST /resource` if the client can determine the ID.

### 2. Database Operations
*   **UPSERTs:** Instead of writing `INSERT` (which fails on retry due to unique constraints) or `SELECT then INSERT` (which suffers from race conditions), use native `INSERT ... ON CONFLICT DO UPDATE` (Postgres) or `MERGE` statements.
*   **Soft Deletes:** `DELETE` operations should be implemented as soft deletes (`deleted_at = NOW()`) so subsequent retries return a 200/204 rather than a 404.

### 3. Workflow Design (Agent Actions)
*   **Guard Clauses:** Shell scripts or bash commands written by the agent must begin with a state check. Rather than running `mkdir output`, write `mkdir -p output` or `if [ ! -d "output" ]; then mkdir output; fi`.

## Quality Gates
*   **API Linter:** OpenAPI specifications must enforce the presence of an `Idempotency-Key` header for non-idempotent HTTP methods (POST, PATCH) on critical endpoints.
*   **Retry Testing:** Integration tests must explicitly call state-mutating endpoints twice with the same payload to assert the database state remains unchanged on the second attempt.

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **Blind Retries** | An agent retries a failed payment API call without passing a transaction ID, charging the customer twice. | Always generate an Idempotency Key (UUID) before the first attempt and reuse it. |
| **Check-Then-Act Race Conditions** | `if (!exists) { insert }` relies on application-level locks, which fail under concurrency. | Use database-level constraints and atomic `UPSERT` operations. |
| **Non-Retryable Shell Commands** | An agent script runs `echo "config" >> file.conf`. Run twice, the config is duplicated. | Make scripts idempotent (e.g., use `sed` or check if the string exists before appending). |

## See Also
*   [API Design](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/architecture/api_design.md)
*   [Error Handling](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/code_quality/error_handling.md)
