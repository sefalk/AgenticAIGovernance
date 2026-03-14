---
name: hexagonal-architecture
description: Guidelines for implementing Ports and Adapters to isolate core business logic from frameworks and infrastructure. Domain isolation, dependency inversion, and testability by design.
argument-hint: '[component or module] — ask for architecture guidance'
---

# Hexagonal Architecture (Ports and Adapters)

## When to Use

- When structuring a new application or module
- When refactoring to isolate business logic from infrastructure
- When designing testable domain cores
- When the coordinator or planner needs to verify architecture compliance

## Principles

1. **Domain Isolation** — The core business logic must not depend on any
   external frameworks, databases, or UI details. It must be pure,
   testable code. *(Separation of Concern)*
2. **Dependency Inversion** — Outer layers (Adapters) depend on inner
   layers (Ports and Domain). Inner layers never depend on outer layers.
   *(Fail-Safe)*
3. **Testability by Design** — Because the domain is isolated, it can be
   exhaustively tested with fast, deterministic unit tests without
   requiring a running database or web server. *(Verifiability)*

## Techniques & Patterns

### 1. The Core (Domain)

- **Entities & Value Objects:** Pure business models. No ORM decorators
  or framework annotations in this layer.
- **Use Cases (Interactors):** Application-specific business rules. They
  orchestrate the flow of data to and from the entities.

### 2. The Ports (Interfaces)

- **Primary Ports (Inbound/Driving):** Interfaces defining how the outside
  world can interact with the core application. Implemented by the
  Use Cases.
- **Secondary Ports (Outbound/Driven):** Interfaces defining what the core
  application needs from the outside world (e.g., `UserRepository`).
  Declared in the core layer but implemented by Adapters.

### 3. The Adapters (Infrastructure/Delivery)

- **Primary Adapters:** REST Controllers, CLI handlers, GraphQL resolvers
  that map external requests into calls to Primary Ports.
- **Secondary Adapters:** Concrete implementations of Secondary Ports
  (e.g., `PostgresUserRepository`, `SparkTableReader`).

### 4. Dependency Injection

The application composition root binds the concrete Secondary Adapters
to the Secondary Ports required by the Use Cases.

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| **Dependency Check** | 0 violations | Static analysis must fail if `domain/` imports from `infrastructure/` or any framework. |
| **Domain Coverage** | ≈ 100% unit test coverage | Domain has zero I/O reliance — fast, deterministic tests. |

## Anti-Patterns

| Anti-Pattern | Why It's Harmful | Better Approach |
|---|---|---|
| **Leaking ORM into Domain** | Database-specific types inside core logic shatter isolation. | Map external types to pure domain types inside the Adapter. |
| **"God" Interfaces** | Monolithic `IDatabase` port makes the domain infra-dependent. | Define atomic, role-specific ports based on what the Use Case needs. |
| **Logic in Adapters** | Business rules in an HTTP Controller can't be tested without a web server. | Controllers strictly map HTTP to DTOs and delegate to Use Cases. |
| **Skipping Ports** | Injecting a concrete Postgres class into a Use Case prevents mocking. | Always rely on abstractions (Secondary Ports). |

## References

- Alistair Cockburn, [Hexagonal Architecture](https://alistair.cockburn.us/hexagonal-architecture/)
- Robert C. Martin, [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
