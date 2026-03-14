---
name: 'Architecture Map'
description: 'Architecture layers and dependency rules. Customise for your project.'
applyTo: 'src/**/*.py'
---

# Architecture Map

> **TODO:** Customise this file for your project. Replace the example modules
> with your actual modules and update the `applyTo` glob pattern.

## Layer Definitions

```
┌───────────────────────────────────────────────────────────┐
│                   Orchestrators                           │
│   Wire adapters to domain core. Manage pipeline flow.     │
│   May import from ALL layers.                             │
├───────────────────────────────────────────────────────────┤
│                   Adapters (I/O)                          │
│   External system implementations of port interfaces.     │
│   May import from Ports and Domain Core only.             │
├───────────────────────────────────────────────────────────┤
│                   Ports (Interfaces)                      │
│   Python Protocol classes defining contracts.             │
│   May import from Domain Core only.                       │
├───────────────────────────────────────────────────────────┤
│                   Domain Core                             │
│   Pure business logic. No I/O at runtime.                 │
│   Imports NOTHING from other layers.                      │
└───────────────────────────────────────────────────────────┘
```

## The Dependency Rule

Dependencies point **inward** only:

- **Domain Core** → imports nothing from project layers (only stdlib, numpy, etc.)
- **Ports** → may import from Domain Core (types, exceptions)
- **Adapters** → may import from Ports and Domain Core
- **Orchestrators** → may import from all layers

**Forbidden:**

- Domain Core importing from any adapter, port, or orchestrator
- Port importing from an adapter
- Domain Core performing I/O (file, network, database)

## Module Classification

<!-- TODO: Fill in your actual modules -->

### Domain Core (pure logic, no I/O)

| Module | Purpose | Status |
|---|---|---|
| `src/domain/models.py` | Pydantic domain models and value objects | TODO |
| `src/domain/logic.py` | Business rules and transformations | TODO |
| `src/domain/exceptions.py` | Domain-specific exceptions | TODO |

**Rules for Domain Core:**

- No I/O imports at runtime (use `TYPE_CHECKING` block for type annotations)
- All functions are pure: output depends only on inputs
- Fully testable without external dependencies

### Ports (interfaces)

| Port | Purpose | Methods |
|---|---|---|
| `src/ports/reader.py` | Read data from storage | `read(source) -> Data` |
| `src/ports/writer.py` | Write data to storage | `write(data, target)` |

**Rules for Ports:**

- Define interfaces using `typing.Protocol`
- Method signatures with docstrings only
- May reference Domain Core types

```python
from __future__ import annotations
from typing import Protocol

class DataReader(Protocol):
    """Port for reading data from storage."""

    def read(self, source: str) -> dict:
        """Read data from the given source."""
        ...
```

### Adapters (I/O implementations)

| Adapter | Implements Port | Purpose |
|---|---|---|
| `src/adapters/file_reader.py` | `DataReader` | Read from filesystem |
| `src/adapters/db_writer.py` | `DataWriter` | Write to database |

**Rules for Adapters:**

- Implement port Protocol interfaces
- Catch infrastructure exceptions → wrap in domain exceptions
- Receive configuration via constructor, not global imports

### Orchestrators (pipeline wiring)

| Module | Purpose |
|---|---|
| `src/pipeline.py` | Main data processing pipeline |

**Rules for Orchestrators:**

- Wire adapters to domain functions via dependency injection
- Contain no business logic
- Accept adapter instances as parameters

```python
def run_pipeline(reader: DataReader, writer: DataWriter) -> None:
    """Orchestrate the processing pipeline."""
    raw = reader.read("source")
    result = transform(raw)  # domain core function
    writer.write(result, "target")
```

## Refactoring Strategy

When refactoring existing code toward this architecture:

1. **Extract pure functions first** — identify transforms with no I/O
2. **Create ports second** — define Protocol interfaces for I/O operations
3. **Create adapters third** — wrap I/O calls in adapter classes
4. **Refactor orchestrators last** — accept adapters as parameters

Do NOT refactor everything at once. Each module independently with tests.

## Import Dependency Validation

```
# ALLOWED
domain_core → stdlib, third-party-libs (no I/O)
ports       → domain_core, stdlib
adapters    → ports, domain_core, I/O libraries
orchestrators → everything

# FORBIDDEN
domain_core → adapters, ports, orchestrators, I/O libraries
ports       → adapters, I/O libraries
adapters    → orchestrators
```

## Hexagonal Architecture (Ports & Adapters)

This project follows the **Hexagonal Architecture** pattern. Domain core
exposes ports (interfaces); adapters implement them.

```
         Driving Adapters                     Driven Adapters
    (who calls the application)         (what the application calls)

    ┌──────────────┐                    ┌──────────────┐
    │  CLI / API    │──╮           ╭──▶│  Database     │
    └──────────────┘  │           │    └──────────────┘
    ┌──────────────┐  │  ┌─────┐  │    ┌──────────────┐
    │  Pipeline     │──┼─▶│Domain│──┼──▶│  File Store   │
    └──────────────┘  │  │ Core │  │    └──────────────┘
    ┌──────────────┐  │  └─────┘  │    ┌──────────────┐
    │  Notebook     │──╯           ╰──▶│  External API  │
    └──────────────┘                    └──────────────┘
             │                                    │
         (via input ports)                 (via output ports)
```

**The dependency rule:** Domain core depends on nothing. Adapters depend on
the core. Never the reverse.

## SOLID Quick Reference

| Principle | Check |
|---|---|
| **S** Single Responsibility | Does each module have one reason to change? |
| **O** Open/Closed | Can you add types without editing existing if/elif chains? |
| **L** Liskov Substitution | Can adapters substitute for ports without surprises? |
| **I** Interface Segregation | Are ports focused (not one fat Protocol with 10 methods)? |
| **D** Dependency Inversion | Do orchestrators accept abstractions, not concrete classes? |

## See Also

- `design-patterns` skill — full pattern catalog with Python examples
- `refactoring` skill — code smells and refactoring moves
