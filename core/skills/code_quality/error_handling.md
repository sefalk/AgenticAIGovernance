---
category: code_quality
applies_to: [all]
complexity: intermediate
maturity: reviewed
version: "1.0"
last_reviewed: 2026-02-26
related: [design_patterns, monitoring_observability, code_review, static_analysis, structured_logging]
---
# Error Handling & Resilience

## Purpose

Error handling and resilience patterns ensure systems fail gracefully, recover automatically, and communicate failures clearly. This skill covers error hierarchies, retry strategies, circuit breakers, fallbacks, and graceful degradation. Invoke this skill when designing error handling strategies, defining Level-3 resilience workflows, or establishing Level-4 error handling standards.

## Principles

- **Fail-Safe (AAIG L1):** When uncertain or when errors occur, agents must halt safely and communicate clearly. Systems should fail into a safe state, never into an unsafe one.
- **Transparency (AAIG L1):** Errors must be logged with sufficient context for diagnosis. Silent failures are the worst failures.
- **Verifiability (AAIG L1):** Error handling paths must be tested. Untested error handlers are likely broken.
- **Separation of concerns:** Error handling logic must be separated from business logic. Don't let exception handling obscure the happy path.

## Techniques & Patterns

### Error Classification

| Category | Retryable | Example | Handling |
|----------|-----------|---------|----------|
| **Transient** | Yes | Network timeout, 503, rate limit | Retry with backoff |
| **Permanent** | No | 404 Not Found, validation error, auth failure | Return error, don't retry |
| **Intermittent** | Maybe | Database deadlock, connection pool exhausted | Retry with limit, then escalate |
| **Fatal** | No | Out of memory, disk full, config missing | Crash fast, alert, human intervention |

### Error Hierarchy Design

```
ApplicationError (base)
  |-- ValidationError       (input validation failures)
  |   |-- MissingFieldError
  |   |-- InvalidFormatError
  |-- BusinessRuleError     (domain logic violations)
  |   |-- InsufficientFundsError
  |   |-- DuplicateOrderError
  |-- InfrastructureError   (external dependency failures)
  |   |-- DatabaseError
  |   |-- ExternalServiceError
  |   |-- MessageBrokerError
  |-- AuthenticationError   (identity failures)
  |-- AuthorizationError    (permission failures)
```

**Rules:**
- Each error type maps to an HTTP status code (API) or action (internal).
- Include machine-readable error code, human-readable message, and context.
- Never expose internal details (stack traces, SQL queries) to end users.

### Retry Strategies

| Strategy | Formula | Use Case |
|----------|---------|----------|
| **Exponential backoff** | `delay = base * 2^attempt` | Default for transient errors |
| **Exponential + jitter** | `delay = random(0, base * 2^attempt)` | High-concurrency systems (prevents thundering herd) |
| **Linear backoff** | `delay = base * attempt` | Rate-limited APIs |
| **Immediate retry** | `delay = 0` (once) | Idempotent operations, brief glitches |

```python
# Exponential backoff with jitter
import random, time

def retry(fn, max_attempts=3, base_delay=1.0):
    for attempt in range(max_attempts):
        try:
            return fn()
        except TransientError:
            if attempt == max_attempts - 1:
                raise
            delay = base_delay * (2 ** attempt)
            jitter = random.uniform(0, delay)
            time.sleep(jitter)
```

**Libraries:** `tenacity` (Python), `resilience4j` (Java), `polly` (C#), `retry` (Go).

### Circuit Breaker

```
States:
  CLOSED  --> normal operation, counting failures
  OPEN    --> requests immediately fail (fast fail)
  HALF-OPEN --> allow one probe request to test recovery

Transitions:
  CLOSED -> OPEN:      failure count > threshold within window
  OPEN -> HALF-OPEN:   after timeout period
  HALF-OPEN -> CLOSED: probe succeeds
  HALF-OPEN -> OPEN:   probe fails
```

**Parameters:**
- Failure threshold: 5 failures in 60 seconds
- Open duration: 30 seconds
- Half-open probe: 1 request
- Monitored exceptions: only transient errors count

### Fallback & Degradation Patterns

| Pattern | Behavior | Example |
|---------|----------|---------|
| **Default value** | Return a cached or default response | Recommendation service down -> show popular items |
| **Feature toggle** | Disable non-critical feature | Payment analytics down -> disable dashboard, keep payments |
| **Read-only mode** | Disable writes, keep reads | Database writes failing -> serve cached reads |
| **Queue and retry** | Accept request, process later | Email service down -> queue emails for later delivery |
| **Bulkhead** | Isolate failure to one component | Thread pool per dependency, preventing cascade |

### Structured Error Responses (API)

```json
{
  "error": {
    "code": "INSUFFICIENT_FUNDS",
    "message": "Account balance is insufficient for this transaction.",
    "details": [
      { "field": "amount", "issue": "Requested 500.00, available 123.45" }
    ],
    "request_id": "req-abc-123",
    "documentation_url": "https://api.example.com/docs/errors#INSUFFICIENT_FUNDS"
  }
}
```

**Mapping:**
| Error Type | HTTP Status |
|-----------|-------------|
| Validation | 400 Bad Request |
| Authentication | 401 Unauthorized |
| Authorization | 403 Forbidden |
| Not Found | 404 Not Found |
| Conflict | 409 Conflict |
| Rate Limit | 429 Too Many Requests |
| Internal | 500 Internal Server Error |
| Dependency | 502 Bad Gateway / 503 Service Unavailable |

### Language-Specific Guidance

| Language | Pattern | Notes |
|----------|---------|-------|
| **Python** | Custom exception hierarchy, `try/except/finally` | Use specific exception types, never bare `except:` |
| **Java** | Checked vs unchecked, custom exceptions | Prefer unchecked for unrecoverable. Use `try-with-resources`. |
| **TypeScript** | `Result<T, E>` pattern, discriminated unions | Avoid `throw` for expected errors. Use `Result`/`Either`. |
| **Go** | `(value, error)` return pattern | Always check errors. Use `errors.Is()` and `errors.As()` for wrapping. |
| **Rust** | `Result<T, E>`, `?` operator | Type system enforces error handling. Use `thiserror` for libraries. |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Error hierarchy defined** | Before implementation | Documented error types, codes, and HTTP mappings |
| **Error paths tested** | Code coverage for catch blocks | Un-tested error handlers are assumed broken |
| **No silent failures** | Zero `catch {}` blocks | Every catch must log or re-throw |
| **Retry configured** | For all external calls | Max attempts, backoff strategy, timeout documented |
| **Circuit breaker** | For critical dependencies | Threshold, timeout, fallback defined |
| **Error monitoring** | Alerting on error rate | Error rate dashboard + alerts in monitoring |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Pokemon exception handling** | `catch (Exception e) {}` -- catches everything, handles nothing. | Catch specific exceptions. Let unknown errors propagate. |
| **Log and throw** | Logging the error AND re-throwing. Double-logged, cluttered. | Log at the handler level, not at every rethrow. |
| **String-based errors** | `throw new Error("something went wrong")`. No structure, no code. | Typed error hierarchy with machine-readable codes. |
| **Retry without backoff** | Hammering a failed service in a tight loop. Makes outages worse. | Exponential backoff + jitter. Always. |
| **Swallowed errors** | `catch { return null; }`. Silent failure. Hours of debugging later. | Always log. Always. If you return a default, log that you did so. |
| **Error code guessing** | Client checks `if (error.message.includes("not found"))`. Fragile. | Structured error codes. Document the contract. |

## See Also

- [Design Patterns](../architecture/design_patterns.md)
- [Monitoring & Observability](../devops/monitoring_observability.md)
- [Code Review](../code_quality/code_review.md)
- [Static Analysis](../code_quality/static_analysis.md)

## References

- Release It! (Nygard): Circuit breaker, bulkhead, timeout patterns
- resilience4j: https://resilience4j.readme.io/
- tenacity (Python): https://github.com/jd/tenacity
- Microsoft Transient Fault Handling: https://learn.microsoft.com/en-us/azure/architecture/best-practices/transient-faults
