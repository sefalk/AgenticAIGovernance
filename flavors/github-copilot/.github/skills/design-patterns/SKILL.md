---
name: design-patterns
description: Proven design patterns — creational, structural, behavioural, DDD, architecture. When to use, when NOT to use, and Python-idiomatic examples.
argument-hint: '[pattern name or problem] [category: creational|structural|behavioural|ddd|architecture]'
disable-model-invocation: true
---

# Design Patterns Skill

Guidance for selecting, applying, and reviewing design patterns.
Patterns are communication tools — use them to solve real problems,
not to demonstrate pattern knowledge.

## When to Use

- Evaluating design alternatives for a new module
- Recognising structural problems (code smells → pattern solutions)
- Reviewing architecture compliance (hexagonal, dependency inversion)
- Deciding whether a pattern is justified (YAGNI check)

## Principles

- **Pattern as communication** — "Use a Strategy here" conveys design intent
  faster than describing mechanics
- **Context matters** — a pattern in the wrong context is an anti-pattern
- **Composition over inheritance** — favour composing behaviour from small,
  focused objects/functions over deep inheritance
- **YAGNI** — apply patterns when the need is concrete, not speculative

## Creational Patterns

| Pattern | Problem | Python Idiom |
|---|---|---|
| **Factory Function** | Create objects without specifying exact class | Function returning instances |
| **Builder** | Complex construction with many optional params | `dataclass` with defaults |
| **Singleton** | Ensure one instance (use sparingly) | Module-level instance or DI container |

```python
# Builder pattern — Python dataclass (idiomatic)
@dataclass
class PipelineConfig:
    source_table: str
    target_table: str
    batch_size: int = 1000
    dry_run: bool = False
    partition_cols: list[str] = field(default_factory=list)

config = PipelineConfig(source_table="raw", target_table="interim", dry_run=True)
```

**Note:** Prefer dependency injection over Singleton. Singleton creates hidden
global state.

## Structural Patterns

| Pattern | Problem | Python Idiom |
|---|---|---|
| **Adapter** | Incompatible interfaces | Wrapper class implementing Protocol |
| **Decorator** | Add behaviour dynamically | `@functools.wraps` decorator |
| **Facade** | Complex subsystem needs simple interface | Module with high-level functions |

```python
# Adapter — wrapping external library behind a Protocol
class SparkReader:
    """Adapter implementing the DataReader port for PySpark."""

    def __init__(self, spark: SparkSession):
        self._spark = spark

    def read(self, source: str) -> DataFrame:
        return self._spark.read.table(source)
```

```python
# Decorator — higher-order function (idiomatic Python)
def retry(max_attempts: int = 3):
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
```

## Behavioural Patterns

| Pattern | Problem | Python Idiom |
|---|---|---|
| **Strategy** | Multiple algorithms, selected at runtime | First-class function / callable |
| **Template Method** | Algorithm skeleton with customisable steps | Function composition |
| **Chain of Responsibility** | Multiple handlers forming a pipeline | List of callables |
| **Iterator** | Sequential access without exposing internals | Generator function (`yield`) |

```python
# Strategy — using first-class functions
from typing import Callable

FilterStrategy = Callable[[DataFrame], DataFrame]

def apply_filters(df: DataFrame, filters: list[FilterStrategy]) -> DataFrame:
    for f in filters:
        df = f(df)
    return df

# Usage
result = apply_filters(df, [remove_nulls, filter_by_date, deduplicate])
```

## SOLID Principles

| Principle | Meaning | Violation Signal |
|---|---|---|
| **S** — Single Responsibility | One reason to change | Class name includes "And" or "Manager" |
| **O** — Open/Closed | Open for extension, closed for modification | Adding a type requires editing if/elif chains |
| **L** — Liskov Substitution | Subtypes are substitutable | Subclass raises `NotImplementedError` |
| **I** — Interface Segregation | Many specific interfaces > one fat interface | Implementors stub out unused methods |
| **D** — Dependency Inversion | Depend on abstractions | Constructor directly instantiates dependencies |

## Application Architecture Patterns

| Pattern | Core Idea | When to Use |
|---|---|---|
| **Hexagonal (Ports & Adapters)** | Domain exposes ports; adapters implement them | Multiple I/O channels |
| **Clean Architecture** | Concentric layers; dependencies point inward | Large codebase, strict layering |
| **Vertical Slice** | Organised by feature, not layer | CRUD-heavy apps, small teams |

**The dependency rule:** Domain core depends on nothing. Adapters depend on
the core. Never the reverse. See `architecture.instructions.md` for the
full layer map.

## DDD Patterns (When Applicable)

| Pattern | Purpose |
|---|---|
| **Entity** | Object with identity that persists across time |
| **Value Object** | Immutable, defined by attributes, no identity |
| **Aggregate** | Cluster of entities as transactional unit |
| **Repository** | Abstraction for data access (collection-like) |
| **Domain Service** | Logic that doesn't belong to a single entity |
| **Domain Event** | Record of something that happened |

## When NOT to Use Patterns

| Situation | Why Not |
|---|---|
| Problem is simple | Patterns add indirection; use a function |
| Forcing a pattern to fit | Code reads *worse* with the pattern |
| Speculative design | "We might need flexibility later" — YAGNI |
| Pattern stacking | Three decorators wrapping a strategy inside a factory |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Pattern mania** | Factory-Strategy-Observer for 20 lines | Simplest approach first |
| **Singleton abuse** | Global mutable state disguised as pattern | Dependency injection |
| **God Object** | One class does everything | Single Responsibility |
| **Lava Flow** | Dead code from abandoned pattern experiments | Delete unused code |
| **Golden Hammer** | Same pattern for every problem | Analyse each problem individually |
