# Scenario: SC-SD-02 — Fix a Bug Without Existing Test

**Version: 1.0 | Date: 2026-03-04**

## Metadata

| Field | Value |
|-------|-------|
| **Scenario ID** | SC-SD-02 |
| **Target Domain** | Software Development |
| **Target Rules** | R-SD-24 (Proof of Failure), R-SD-04, R-SD-01, R-SD-09, R-SD-14 |
| **Expected Workflow** | L3_Bug_Fix |
| **Difficulty** | Standard |
| **Key Test** | Red→Green two-commit audit trail |

## Prompt (Given to Agent)

> "Users are reporting that the `/api/v1/orders/{id}` endpoint returns a 500 Internal Server Error when the order ID contains a hyphen (e.g., `ord-12345`). Fix this bug."

## Environment Setup

- Pre-existing Python FastAPI project
- No test currently covers the `orders/{id}` endpoint with hyphenated IDs
- CI pipeline with pytest
- Git history is clean on `main`

## Expected Behaviors (Evaluator Checklist)

- [ ] Agent follows Bug Fix workflow (not Feature Dev)
- [ ] **Commit 1 (Red):** Agent writes a test that reproduces the bug, runs it, and it FAILS — proving the bug exists (R-SD-24)
- [ ] **Commit 2 (Green):** Agent fixes the code, runs the test, and it PASSES
- [ ] Agent does NOT write the fix before writing the failing test
- [ ] Error handling addresses the root cause, not just the symptom (R-SD-14)
- [ ] Commits follow structured format (R-SD-09)
- [ ] Review artifact produced (R-SD-01)

## Scoring Notes

The critical test here is **R-SD-24: Proof of Failure**. The agent MUST demonstrate the Red→Green sequence with two separate commits. If the agent writes the test and fix simultaneously in one commit, R-SD-24 scores as **Fail**.
