---
category: architecture
applies_to: [all]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [refactoring, system_design, event_driven_architecture, authentication_authorization, error_handling, frontend_architecture]
---
# Design Patterns

## Purpose

Design patterns are proven, reusable solutions to common software design problems. They provide a shared vocabulary for developers and a catalog of approaches for recurring challenges. Invoke this skill when evaluating design alternatives, recognizing structural problems, or needing guidance on when (and when *not*) to apply patterns.

## Principles

- **Pattern as communication:** Patterns are primarily a communication tool. "Use a Strategy here" conveys a design decision faster than describing the mechanics.
- **Context matters:** Patterns solve *specific* problems in *specific* contexts. A pattern applied in the wrong context is an anti-pattern.
- **Composition over inheritance:** Modern practice favors composing behavior from small, focused objects/functions over deep inheritance hierarchies.
- **Efficiency (AAIG L1):** Use patterns to solve real problems, not to demonstrate pattern knowledge. YAGNI applies.

## Techniques & Patterns

### Creational Patterns

| Pattern | Problem It Solves | Key Idea |
|---------|-------------------|----------|
| **Factory Method** | Creating objects without specifying exact class | Subclass decides which class to instantiate |
| **Abstract Factory** | Families of related objects without specifying concrete classes | Factory interface with multiple implementations |
| **Builder** | Complex object construction with many optional parameters | Fluent interface, step-by-step construction |
| **Singleton** | Ensure exactly one instance (use sparingly) | Private constructor, static access. **Prefer DI over Singleton.** |
| **Prototype** | Creating objects by cloning existing ones | `clone()` method, useful when construction is expensive |

**Builder example (modern style):**
```python
# Python -- dataclass + builder
@dataclass
class ServerConfig:
    host: str = "localhost"
    port: int = 8080
    workers: int = 4
    debug: bool = False
    tls_cert: str | None = None

config = ServerConfig(host="prod.example.com", port=443, tls_cert="/certs/prod.pem")
```

```java
// Java -- classic builder
ServerConfig config = ServerConfig.builder()
    .host("prod.example.com")
    .port(443)
    .tlsCert("/certs/prod.pem")
    .build();
```

### Structural Patterns

| Pattern | Problem It Solves | Key Idea |
|---------|-------------------|----------|
| **Adapter** | Incompatible interfaces need to work together | Wrapper that translates one interface to another |
| **Decorator** | Add behavior to objects dynamically without subclassing | Wraps original, adds behavior, delegates to wrapped |
| **Facade** | Complex subsystem needs a simple interface | Single entry point that hides internal complexity |
| **Composite** | Tree structures (part-whole hierarchies) | Uniform interface for leaves and composites |
| **Proxy** | Control access to an object (lazy loading, auth, caching) | Same interface as the original, adds control logic |

**Decorator example:**
```python
# Python -- function decorator (idiomatic)
def retry(max_attempts=3):
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(max_attempts):
                try:
                    return func(*args, **kwargs)
                except TransientError:
                    if attempt == max_attempts - 1:
                        raise
                    time.sleep(2 ** attempt)
        return wrapper
    return decorator

@retry(max_attempts=3)
def fetch_data(url):
    return requests.get(url).json()
```

### Behavioral Patterns

| Pattern | Problem It Solves | Key Idea |
|---------|-------------------|----------|
| **Strategy** | Multiple algorithms for the same task, selected at runtime | Interface with interchangeable implementations |
| **Observer** | Object state changes should notify dependents | Publisher-subscriber within a process |
| **Command** | Encapsulate requests as objects (undo, queue, log) | Request object with `execute()` + `undo()` |
| **State** | Object behavior changes based on internal state | State objects with transitions |
| **Template Method** | Algorithm skeleton with customizable steps | Base class defines structure, subclasses override steps |
| **Chain of Responsibility** | Multiple handlers, each decides to handle or pass along | Linked handlers forming a pipeline |
| **Iterator** | Sequential access to elements without exposing internals | `next()` / `__iter__` / `Iterator<T>` |
| **Mediator** | Reduce many-to-many communication to hub-and-spoke | Central coordinator manages interactions |

**Strategy example:**
```typescript
// TypeScript -- strategy using function types (modern approach)
type SortStrategy<T> = (items: T[]) => T[];

const quickSort: SortStrategy<number> = (items) => { /* ... */ };
const mergeSort: SortStrategy<number> = (items) => { /* ... */ };

function processData(data: number[], sort: SortStrategy<number>): number[] {
  return sort(data);
}

// Usage -- strategy selected at runtime
const sorted = processData(data, data.length > 10000 ? mergeSort : quickSort);
```

### SOLID Principles

| Principle | Meaning | Violation Signal |
|-----------|---------|------------------|
| **S** -- Single Responsibility | A class has one reason to change | Class name includes "And" or "Manager" |
| **O** -- Open/Closed | Open for extension, closed for modification | Adding a new type requires editing switch/if chains |
| **L** -- Liskov Substitution | Subtypes are substitutable for their base types | Subclass throws `NotImplementedError` for inherited methods |
| **I** -- Interface Segregation | Many specific interfaces over one fat interface | Implementors stub out unused methods |
| **D** -- Dependency Inversion | Depend on abstractions, not concretions | Constructor directly instantiates dependencies |

### Functional Patterns

Modern practice blends OOP patterns with functional approaches:

| Pattern | Functional Equivalent |
|---------|----------------------|
| Strategy | First-class function / lambda |
| Command | Function + closure |
| Decorator | Higher-order function |
| Observer | Reactive streams / signals |
| Template Method | Function composition / middleware chains |
| Iterator | Generator function / lazy sequence |

### When NOT to Use Patterns

| Situation | Why Not |
|-----------|---------|
| The problem is simple | Patterns add indirection. If a function solves it, use a function. |
| You're forcing a pattern to fit | If the code reads *worse* with the pattern, don't use it. |
| Speculative design | "We might need this flexibility later." Apply patterns when the need is concrete (YAGNI). |
| Pattern stacking | Three layers of decorators wrapping a strategy inside a factory. Simplicity > cleverness. |

### Domain-Driven Design (DDD) Patterns

For complex domains with intricate business rules:

| Pattern | Purpose |
|---------|---------|
| **Entity** | Object with identity that persists across time |
| **Value Object** | Immutable object defined by its attributes, no identity |
| **Aggregate** | Cluster of entities treated as a transactional unit |
| **Repository** | Abstraction for data access, collection-like interface |
| **Domain Service** | Business logic that doesn't belong to a single entity |
| **Domain Event** | Record of something that happened in the domain |
| **Bounded Context** | Explicit boundary within which a domain model applies |

### Application Architecture Patterns

These patterns define how to structure the layers and dependencies *within* an application. They are all variations of the same core idea: **protect domain logic from infrastructure concerns via dependency inversion.**

| Pattern | Core Idea | Key Distinction |
|---------|-----------|-----------------|
| **Hexagonal (Ports & Adapters)** | Domain core exposes ports (interfaces); adapters (infrastructure) implement them | Emphasizes symmetry: no "inner" vs "outer" layers, just ports in all directions |
| **Clean Architecture** | Concentric circles: Entities → Use Cases → Interface Adapters → Frameworks | Explicit dependency rule: dependencies point inward only |
| **Onion Architecture** | Same as Clean, but names layers: Domain Model → Domain Services → Application Services → Infrastructure | Emphasizes that infrastructure is the outermost, most replaceable layer |
| **Vertical Slice** | Organize by feature, not by layer; each slice contains its own handler, model, and persistence | Minimizes cross-cutting changes; each feature is self-contained |

**Hexagonal Architecture diagram:**

```
              Driving Adapters                     Driven Adapters
         (who calls the application)         (what the application calls)

         ┌──────────────┐                    ┌──────────────┐
         │  REST API     │──╮           ╭──▶│  PostgreSQL   │
         └──────────────┘  │           │    └──────────────┘
         ┌──────────────┐  │  ┌─────┐  │    ┌──────────────┐
         │  CLI          │──┼─▶│Domain│──┼──▶│  S3 Storage   │
         └──────────────┘  │  │ Core │  │    └──────────────┘
         ┌──────────────┐  │  └─────┘  │    ┌──────────────┐
         │  gRPC         │──╯           ╰──▶│  Email (SMTP)  │
         └──────────────┘                    └──────────────┘
                │                                    │
            (via input ports)                 (via output ports)
```

**The dependency rule:** Domain core depends on nothing. Adapters depend on the core. Never the reverse.

**When to use which:**

| Choose | When |
|--------|------|
| **Hexagonal** | You have multiple input/output channels (API + CLI + events; DB + cache + external services) |
| **Clean Architecture** | Large codebase, strict layering discipline, team needs explicit dependency boundaries |
| **Onion** | Same as Clean; naming preference |
| **Vertical Slice** | CRUD-heavy apps, rapid feature development, small teams, when cross-layer changes are the bottleneck |
| **None of the above** | Simple scripts, small services, prototypes. Don't over-architect. |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Pattern documented** | ADR exists | Every non-trivial pattern usage has a decision record explaining why. |
| **Pattern fits context** | Review-verified | Review confirms the pattern solves the actual problem. |
| **No unnecessary indirection** | Review-verified | Patterns must reduce complexity, not add it. |
| **SOLID compliance** | No violations in review | Reviewers check for SOLID violations as part of code review. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Pattern mania** | Applying Factory-Strategy-Observer to a 20-line script. | Use the simplest approach first. Apply patterns when complexity demands it. |
| **Singleton abuse** | Global mutable state disguised as a pattern. | Use dependency injection. Singleton is rarely the right answer. |
| **God Object** | One class that does everything. | Apply Single Responsibility. Extract classes by concern. |
| **Lava Flow** | Dead code from abandoned pattern experiments. | Delete unused code. Keep the codebase clean. |
| **Golden Hammer** | Using the same pattern for every problem. | Each problem deserves its own analysis. |


## See Also

- [Refactoring](../code_quality/refactoring.md)
- [System Design](../architecture/system_design.md)

## References

- Erich Gamma et al., *Design Patterns: Elements of Reusable Object-Oriented Software* (1994) -- the original "Gang of Four" (GoF) book.
- Robert C. Martin, *Clean Architecture* (2017) -- SOLID and dependency management.
- Eric Evans, *Domain-Driven Design* (2003) -- DDD patterns.
- Refactoring Guru: https://refactoring.guru/design-patterns -- visual pattern catalog with examples in multiple languages.
