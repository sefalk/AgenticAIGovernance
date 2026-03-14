---
category: testing
applies_to: [all, api, microservice]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [unit_testing, contract_testing, e2e_testing]
---
# Integration Testing

## Purpose

Integration testing verifies that multiple components, modules, or services work correctly together. Unlike unit tests (which isolate a single unit), integration tests exercise real interactions: database queries, HTTP calls, message queues, file systems, and inter-service communication. Invoke this skill when the system has boundaries between components that must be validated together.

## Principles

- **Real interactions:** Integration tests use real (or realistically simulated) dependencies. They validate that units integrate correctly -- that the "glue" works.
- **Bounded scope:** Each integration test should exercise one integration boundary (e.g., "service A calls database B"), not the entire system.
- **Reproducibility:** Tests must be deterministic despite using external systems. Achieve this through containerized dependencies, seeded data, and transactional rollback.
- **Verifiability (AAIG L1):** Results must be programmatically verifiable with clear pass/fail.
- **Efficiency (AAIG L1):** Integration tests are slower than unit tests. Minimize the number needed by maximizing unit test coverage first.

## Techniques & Patterns

### Test Containers

The modern standard for integration testing with external dependencies. Spin up real databases, message brokers, and services as ephemeral containers.

```
Test setup  -->  Start container (PostgreSQL, Redis, Kafka, etc.)
            -->  Apply migrations / seed data
Test run    -->  Exercise real queries / API calls against the container
Test teardown -> Destroy container (clean slate for next test)
```

**Benefits:** Real behavior (no mocking the DB), deterministic (fresh container each run), CI-friendly (no shared infrastructure).

#### Language Support

| Language | Library | Example |
|----------|---------|---------|
| Java/Kotlin | Testcontainers | `@Container PostgreSQLContainer<?> pg = new PostgreSQLContainer<>("postgres:16")` |
| Python | `testcontainers-python` | `PostgresContainer("postgres:16")` as context manager |
| JS/TS | `testcontainers` (npm) | `const container = await new PostgreSqlContainer().start()` |
| Go | `testcontainers-go` | `postgres.RunContainer(ctx, testcontainers.WithImage("postgres:16"))` |
| .NET | `Testcontainers.NET` | `new PostgreSqlBuilder().WithImage("postgres:16").Build()` |
| Rust | `testcontainers` crate | `let node = docker.run(postgres::Postgres::default())` |

### Data Management Strategies

| Strategy | Description | When to Use |
|----------|-------------|-------------|
| **Transaction rollback** | Wrap each test in a transaction and roll back after assertion. | Database tests where you want isolation without container restart. |
| **Fixtures / seed scripts** | Load predefined data before each test or test suite. | When tests need a known baseline state. |
| **Factory / builder pattern** | Programmatically create test entities with sensible defaults. | When different tests need different data shapes. |
| **Snapshot / dump restore** | Restore a database snapshot before each test suite. | Large, complex data sets that are expensive to generate. |

**Rules:**
- Each test must be independent. Test A must not depend on state left by Test B.
- Clean up after tests (or use transactional rollback / per-test containers).
- Never test against shared development or staging databases.

### Service Integration Patterns

#### HTTP/API Integration
```
1. Start the service under test (or use a test server).
2. Make real HTTP calls to its endpoints.
3. Assert on response status, headers, body.
4. Verify side effects (database state, events published, etc.).
```

**Tools:** `httpx`/`requests` (Python), `supertest` (Node.js), `RestAssured` (Java), `HttpClient` (.NET).

#### Message Queue Integration
```
1. Start a real or containerized broker (RabbitMQ, Kafka, etc.).
2. Publish a message.
3. Wait for the consumer to process it (with timeout).
4. Assert on the resulting state change or output message.
```

**Key challenge:** Asynchronous assertions. Use polling with timeout, not `Thread.sleep()`.

#### File System Integration
```
1. Create a temporary directory for the test.
2. Write input files.
3. Run the file-processing code.
4. Assert on output files.
5. Delete the temporary directory in teardown.
```

**Tools:** `tmp_path` fixture (pytest), `@TempDir` (JUnit 5), `os.tmpdir()` (Node.js).

### Test Organization

```
tests/
  unit/           <-- fast, isolated
  integration/    <-- slower, real dependencies
    test_db_repository.py
    test_api_client.py
    test_message_consumer.py
  e2e/            <-- slowest, full system
```

- Separate integration tests from unit tests so they can be run independently.
- Use markers/tags to control which tests run in CI: `pytest -m integration`, `@Tag("integration")`.
- Integration tests run after unit tests in the CI pipeline.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **All integration tests pass** | 100% | No integration test may be skipped without documented justification. |
| **Execution time** | < 5 min (full suite) | Use parallel execution and container reuse to stay under budget. |
| **No shared state** | 0 shared-state violations | Each test must be runnable in isolation and in any order. |
| **Container cleanup** | All cleaned up | No orphaned containers after test suite completion. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Testing against shared infra** | Tests are flaky because multiple developers/CI jobs share the same DB. | Use test containers or per-run ephemeral instances. |
| **The integration test that tests everything** | One giant test that sets up the entire system and tests 20 scenarios. | Break into focused tests, one integration boundary each. |
| **Sleeping instead of polling** | `Thread.sleep(5000)` to wait for async operations. Slow and flaky. | Use polling with exponential backoff and timeout. |
| **Not cleaning up** | Tests leave data in the database that breaks subsequent tests. | Use transactional rollback or per-test container. |
| **Mocking in integration tests** | Using mocks for the dependency you're supposed to be integrating with. | That's a unit test, not an integration test. Use the real dep. |


## See Also

- [Unit Testing](../testing/unit_testing.md)
- [Contract Testing](../testing/contract_testing.md)
- [E2E Testing](../testing/e2e_testing.md)

## References

- Testcontainers: https://testcontainers.com/
- Sam Newman, *Building Microservices* (2021), Ch. 7 "Testing" -- integration testing strategies.
- Martin Fowler, ["IntegrationTest"](https://martinfowler.com/bliki/IntegrationTest.html) -- definition and taxonomy.
