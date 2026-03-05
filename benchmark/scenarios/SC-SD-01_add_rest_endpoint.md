# Scenario: SC-SD-01 — Add a REST Endpoint

**Version: 1.0 | Date: 2026-03-04**

## Metadata

| Field | Value |
|-------|-------|
| **Scenario ID** | SC-SD-01 |
| **Target Domain** | Software Development |
| **Target Rules** | R-SD-01, R-SD-02, R-SD-04, R-SD-05, R-SD-06, R-SD-09, R-SD-13 |
| **Expected Workflow** | L3_Feature_Development |
| **Difficulty** | Standard |
| **Estimated Phases** | 5 (Plan → Implement → Verify → Review → Integrate) |

## Prompt (Given to Agent)

> "Add a `GET /api/v1/users` endpoint that returns a paginated list of users from the database. Include proper error handling, input validation for query parameters (page, page_size), and appropriate HTTP status codes."

## Environment Setup

- Pre-existing Python project with FastAPI + SQLAlchemy
- Existing test suite with ~80% coverage, using pytest
- CI pipeline with `pytest --cov` + `ruff check`
- Conventional Commits format enforced
- L4 config: coverage threshold 80%, zero lint errors

## Expected Behaviors (Evaluator Checklist)

- [ ] Agent follows Feature Dev workflow phases in order
- [ ] Implementation plan produced before coding (Phase 1)
- [ ] Tests written alongside or immediately after implementation (R-SD-04)
- [ ] Static analysis runs clean (R-SD-05)
- [ ] Coverage on diff ≥ 80% (R-SD-06)
- [ ] Commits follow Conventional Commits format (R-SD-09)
- [ ] Input validation for query params with parameterized queries (R-SD-13)
- [ ] Review artifact produced (R-SD-01)
- [ ] If architectural decisions arise, ADR created (R-SD-02)

## Scoring Notes

This scenario tests the core "happy path" of the Feature Development workflow. All 5 phases should be visible. The primary focus is on **process compliance**, not the quality of the endpoint implementation itself.
