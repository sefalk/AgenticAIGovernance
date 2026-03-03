---
title: Agentic Hexagonal Architecture
description: Guidelines for implementing Ports and Adapters to isolate core business logic from frameworks and infrastructure.
applies_to: [api, microservice, web]
complexity: advanced
maturity: draft
version: "1.0"
last_reviewed: 2026-03-04
related: [api_design, system_design, unit_testing]
---
# Agentic Hexagonal Architecture (Ports and Adapters)

## Purpose
This skill teaches agents how to structure applications using Hexagonal Architecture. The primary goal is to isolate the core business logic (the "Domain") from external delivery mechanisms (UI, REST APIs) and infrastructure (Databases, External APIs). For Autonomous AI Agents, this architecture is critical because it mathematically enforces boundaries, making the codebase highly testable and resistant to cascading failures.

## Principles
1. **Domain Isolation:** The core business logic must not depend on any external frameworks, databases, or UI details. It must be pure, testable code. *(AAIG L1: Separation of Concern)*
2. **Dependency Inversion:** Outer layers (Adapters) depend on inner layers (Ports and Domain). Inner layers never depend on outer layers. *(AAIG L1: Fail-Safe)*
3. **Testability by Design:** Because the domain is isolated, it can be exhausted with fast, deterministic unit tests without requiring a running database or web server. *(AAIG L1: Verifiability & Quality Assurance)*

## Techniques & Patterns

### 1. The Core (Domain)
*   **Entities & Value Objects:** Define the pure business models here. No ORM decorators (like `@Entity` or `[Table]`) should exist in this layer.
*   **Use Cases (Interactors):** Define the application-specific business rules. They orchestrate the flow of data to and from the entities.

### 2. The Ports (Interfaces)
*   **Primary Ports (Inbound/Driving):** Interfaces defining how the outside world (e.g., a REST Controller) can interact with the core application. Implemented by the Use Cases.
*   **Secondary Ports (Outbound/Driven):** Interfaces defining what the core application needs from the outside world (e.g., `UserRepository`). Declared in the core layer, but implemented by the Adapters outside the core.

### 3. The Adapters (Infrastructure/Delivery)
*   **Primary Adapters:** REST Controllers, CLI handlers, or GraphQL resolvers that map external requests into calls to Primary Ports.
*   **Secondary Adapters:** Concrete implementations of the Secondary Ports (e.g., `PostgresUserRepository`, `StripePaymentService`).

### 4. Dependency Injection
*   The application composition root binds the concrete Secondary Adapters to the Secondary Ports required by the Use Cases.

## Quality Gates
*   **Dependency Check:** Static analysis MUST fail if any code in the `domain/` or `core/` directory imports from `infrastructure/`, `delivery/`, or any external ORM/Framework package.
*   **Domain Coverage:** The core domain logic must achieve near 100% unit test coverage, as it has zero reliance on slow I/O or external systems.

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **Leaking ORM into Domain** | Using database-specific types (e.g., MongoDB `ObjectId`) inside the core business logic shatters the isolation boundary. | Map external types to pure domain types inside the Secondary Adapter before passing to the core. |
| **"God" Interfaces** | A monolithic `IDatabase` port makes the domain dependent on infrastructure details. | Define atomic, role-specific ports based on what the Use Case actually needs (e.g., `IFindUser`). |
| **Logic in Adapters** | Putting business rules inside an HTTP Controller means those rules cannot be tested without a web server. | Controllers should strictly map HTTP to DTOs and immediately delegate to a Use Case. |
| **Skipping Ports for "Simplicity"** | Injecting a concrete Postgres class directly into a Use Case prevents test mocking and locks the application to that database. | Always rely on abstractions (Secondary Ports). |

## See Also
*   [API Design](../architecture/api_design.md)
*   [System Design](../architecture/system_design.md)
*   [Unit Testing](../testing/unit_testing.md)

## References
*   [Hexagonal Architecture by Alistair Cockburn](https://alistair.cockburn.us/hexagonal-architecture/)
*   [Clean Architecture by Robert C. Martin](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
