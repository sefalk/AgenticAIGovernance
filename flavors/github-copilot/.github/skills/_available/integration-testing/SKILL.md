---
name: integration-testing
description: Verify that multiple components work correctly together — test containers, data management, service integration patterns, and CI organization.
argument-hint: '[integration boundary to test] [language]'
activation:
  signals:
    python_packages: [fastapi, flask, django, sqlalchemy, sqlmodel, httpx]
    js_packages: [express, nestjs, next]
    file_patterns: ["**/test_integration_*.py", "**/tests/integration/**"]
  agents: [test-writer, test-critic, implementer]
  priority: recommended
---

# Integration Testing

## When to Use

- When the system has boundaries between components that must be validated
- When testing database queries, HTTP calls, message queues, or file systems
- When establishing test infrastructure with containers
- When separating integration tests from unit tests in CI

## Principles

1. **Real Interactions** — Use real (or realistically simulated)
   dependencies. Validate that the "glue" works.
2. **Bounded Scope** — Each test exercises one integration boundary, not
   the entire system.
3. **Reproducibility** — Tests must be deterministic despite external
   dependencies. Use containerized deps, seeded data, transactional
   rollback.
4. **Efficiency** — Integration tests are slower. Minimize by maximizing
   unit test coverage first.

## Techniques & Patterns

### Test Containers

Spin up real databases, brokers, and services as ephemeral containers.

```
Setup    → Start container (PostgreSQL, Redis, Kafka, etc.)
         → Apply migrations / seed data
Run      → Exercise real queries / API calls
Teardown → Destroy container (clean slate)
```

| Language | Library |
|----------|---------|
| Java/Kotlin | Testcontainers |
| Python | `testcontainers-python` |
| JS/TS | `testcontainers` (npm) |
| Go | `testcontainers-go` |
| .NET | `Testcontainers.NET` |
| Rust | `testcontainers` crate |

### Data Management Strategies

| Strategy | When to Use |
|----------|-------------|
| **Transaction rollback** | DB tests needing isolation without container restart |
| **Fixtures / seed scripts** | Tests needing a known baseline state |
| **Factory / builder pattern** | Different tests need different data shapes |
| **Snapshot restore** | Large, complex seed data |

**Rules:**
- Each test must be independent — Test A must not depend on state from Test B.
- Clean up after tests (rollback / per-test containers).
- Never test against shared development databases.

### Service Integration Patterns

**HTTP/API:** Start test server → make real HTTP calls → assert response +
side effects.

**Message Queue:** Start containerized broker → publish → poll for consumer
result with timeout (never `Thread.sleep()`).

**File System:** Create temp directory → write inputs → run code → assert
outputs → clean up.

### Test Organization

```
tests/
  unit/           ← fast, isolated
  integration/    ← slower, real dependencies
  e2e/            ← slowest, full system
```

Use markers/tags to control runs: `pytest -m integration`, `@Tag("integration")`.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **All integration tests pass** | 100% | No skip without documented justification. |
| **Execution time** | < 5 min (full suite) | Parallel execution and container reuse. |
| **No shared state** | 0 violations | Each test runnable in isolation, any order. |
| **Container cleanup** | All cleaned up | No orphaned containers. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Shared infra** | Multiple CI jobs share the same DB. Flaky. | Per-run ephemeral containers. |
| **Tests everything** | One giant test, 20 scenarios. | Focused tests, one boundary each. |
| **Sleep instead of poll** | `Thread.sleep(5000)` — slow and flaky. | Polling with exponential backoff + timeout. |
| **Not cleaning up** | Leftover data breaks subsequent tests. | Transactional rollback or per-test container. |
| **Mocking in integration tests** | Mocking the dependency you're integrating with. | Use the real dependency — that's the point. |

## References

- Testcontainers: https://testcontainers.com/
- Sam Newman, *Building Microservices* (2021), Ch. 7
- Martin Fowler, ["IntegrationTest"](https://martinfowler.com/bliki/IntegrationTest.html)
