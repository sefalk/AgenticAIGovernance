---
name: error-handling
description: Error hierarchies, retry strategies, resilience patterns, and structured error responses. Use when designing error handling or reviewing error paths.
argument-hint: '[module or function] [pattern: hierarchy|retry|circuit-breaker|fallback]'
disable-model-invocation: true
activation:
  agents: [test-writer, implementer, code-critic]
  priority: required
---

# Error Handling & Resilience Skill

Guidance for designing error handling strategies, implementing retry logic,
and building resilient systems.

## When to Use

- Designing error hierarchies for a new module or domain
- Implementing retry logic for external service calls
- Reviewing error handling paths in code review
- Adding resilience to adapter code

## Principles

- **Fail-safe** — when errors occur, halt safely and communicate clearly
- **Transparency** — errors are logged with sufficient context for diagnosis
- **Tested error paths** — untested error handlers are assumed broken
- **Separation** — error handling logic is separate from business logic

## Error Classification

| Category | Retryable | Example | Handling |
|---|---|---|---|
| **Transient** | Yes | Network timeout, 503, rate limit | Retry with backoff |
| **Permanent** | No | 404, validation error, auth failure | Return error, don't retry |
| **Intermittent** | Maybe | Deadlock, connection pool exhausted | Retry with limit, then escalate |
| **Fatal** | No | Out of memory, config missing | Crash fast, alert |

## Error Hierarchy Pattern

```
DomainError (base)
  ├── ValidationError       (input validation failures)
  │   ├── MissingFieldError
  │   └── InvalidFormatError
  ├── BusinessRuleError     (domain logic violations)
  └── InfrastructureError   (external dependency failures)
      ├── DatabaseError
      └── ExternalServiceError
```

**Rules:**
- Domain core raises domain-specific exceptions only
- Adapters catch infrastructure exceptions and translate to domain exceptions
- Never bare `except:` — always catch specific exceptions
- Include context in the exception message

```python
# Domain exception hierarchy
class DomainError(Exception):
    """Base exception for domain errors."""

class ValidationError(DomainError):
    """Input validation failure."""

class BusinessRuleError(DomainError):
    """Domain logic violation."""

# Adapter translation
class SparkAdapter:
    def read(self, table: str) -> DataFrame:
        try:
            return self._spark.read.table(table)
        except AnalysisException as e:
            raise InfrastructureError(f"Table not found: {table}") from e
```

## Retry Strategies

| Strategy | Formula | Use Case |
|---|---|---|
| **Exponential backoff** | `delay = base * 2^attempt` | Default for transient errors |
| **Exponential + jitter** | `delay = random(0, base * 2^attempt)` | High-concurrency (prevents thundering herd) |
| **Linear backoff** | `delay = base * attempt` | Rate-limited APIs |

```python
import random
import time

def retry(fn, max_attempts=3, base_delay=1.0):
    """Retry with exponential backoff and jitter."""
    for attempt in range(max_attempts):
        try:
            return fn()
        except TransientError:
            if attempt == max_attempts - 1:
                raise
            delay = base_delay * (2 ** attempt)
            time.sleep(random.uniform(0, delay))
```

**Library:** `tenacity` (Python) for production-grade retry logic.

**Agent retry limit:** Agents are limited to **2 attempts** per task before
escalating to the coordinator (see MANIFEST §5 Retry & Escalation).

## Fallback Patterns

| Pattern | Behaviour | Example |
|---|---|---|
| **Default value** | Return cached or default response | Service down → return last known result |
| **Feature toggle** | Disable non-critical feature | Analytics down → disable dashboard |
| **Queue and retry** | Accept request, process later | External API down → queue for retry |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Pokemon handling** | `except Exception: pass` — catches everything, handles nothing | Catch specific exceptions |
| **Log and throw** | Logging AND re-throwing — double-logged | Log at the handler, not at every rethrow |
| **Swallowed errors** | `except: return None` — silent failure | Always log; if returning default, log that |
| **Retry without backoff** | Hammering a failed service | Exponential backoff + jitter |
| **String-based errors** | `raise Exception("something wrong")` — no structure | Typed exception hierarchy |
| **Bare except** | `except:` catches KeyboardInterrupt, SystemExit | Always `except SpecificError` |

## Quality Gates

| Gate | Threshold |
|---|---|
| Error hierarchy defined | Before implementation |
| Error paths tested | Coverage for catch blocks |
| No silent failures | Zero empty `except` blocks |
| Retry configured | For all external calls in adapters |

## Governance References

- **R-SD-25** — Retry limits and escalation for agent tasks
- **R-SD-26** — Human escalation when automated resolution fails
