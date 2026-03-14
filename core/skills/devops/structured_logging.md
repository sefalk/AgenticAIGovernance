---
title: Structured Logging
description: Patterns for generating, aggregating, and analyzing logs across distributed systems
applies_to: [all]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [monitoring_observability, error_handling, compliance_regulatory]
---
# Structured Logging

## Purpose
To ensure system logs are machine-readable, searchable, and rich with context, transforming text streams into a queryable dataset essential for debugging distributed systems and satisfying audit requirements.

## Principles
1. **Logs are Data, not Text:** Logs must be emitted as structured data (JSON) rather than human-readable text strings. Machines read logs far more often than humans do. *(AAIG L1: Transparency/Traceability)*
2. **Context is King:** A log message isolated from its context is useless. Every log entry must include contextual metadata (who, where, what request) implicitly.
3. **Traceability Across Boundaries:** Distributed systems require correlation IDs passed between services to trace a single user request through multiple microservices.
4. **Security & Redaction:** Sensitive data (PII, credentials, tokens) must never be written to logs. *(AAIG L1: Safety & Security)*

## Techniques & Patterns

### 1. JSON Formulation
*   **The Payload:** Every log event is a JSON object.
    *   *Bad:* `INFO [Auth] User 123 logged in from 192.168.1.1`
    *   *Good:* `{"level":"info", "module":"auth", "msg":"User logged in", "user_id":123, "ip":"192.168.1.1", "timestamp":"2026-02-26T12:00:00Z"}`
*   **Standardized Schema:** Agree on standard keys across the entire organization (e.g., use `user_id` consistently, never `userId` in one service and `uid` in another). Elastic Common Schema (ECS) is a good default.

### 2. Contextual Loggers
*   **Bound Contexts:** Instead of passing `user_id` to every function just to log it, create a "child logger" bound with the request context at the middleware layer. Any subsequent log call using that child logger automatically includes the `user_id` and `request_id`.

### 3. Correlation IDs
*   **Ingress to Egress:** Generate a unique UUID (`X-Correlation-ID`) at the API Gateway or edge proxy. Include this ID in every log entry for that request. Most importantly, inject this ID into the HTTP headers for all outbound calls to downstream microservices so they can include it in their logs.

### 4. Log Levels & Aggregation
*   **Level Discipline:**
    *   `FATAL`: System cannot continue (requires paging).
    *   `ERROR`: Action failed, but system continues. Investigate soon.
    *   `WARN`: Potentially harmful situation, or a gracefully handled failure (e.g., retry succeeded).
    *   `INFO`: Normal lifecycle events (startup, shutdown, significant state change).
    *   `DEBUG`: Developer-only diagnostic info. Disabled in production.
*   **Standard Out:** Services should log to `stdout`/`stderr` only. Let the container runtime (Docker/Kubernetes) or host agent (Fluentbit/Vector) handle log shipping and rotation to the aggregator (Elasticsearch, Datadog).

## Quality Gates
*   **Log Parsing Validation:** CI tests run the application, capture the `stdout` stream, and assert that every line is strictly valid JSON matching the agreed schema.
*   **PII Scanning:** Security pipeline sweeps the development log outputs looking for regex patterns matching credit cards, secrets, or SSNs to catch redaction failures early.

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **String Interpolation Logging** | `logger.info(f"Query took {ms}")` forces log aggregators to use regex to extract the `ms` value, which breaks if the message changes. | Log the metric: `logger.info("Query completed", extra={"duration_ms": ms})`. |
| **Exception Swallowing** | `except Exception: logger.error("Failed")` loses the stack trace, making debugging impossible. | Pass the exception object to the logger so the trace is automatically serialized. |
| **Logging Passwords/Tokens** | Dumping an entire HTTP Request object to the log often captures Authorization headers or password fields. | Explicitly pick fields to log, or use a robust redaction middleware that strips known sensitive keys. |
| **Info Spam** | Logging every single HTTP request at `INFO` level overwhelms the log aggregator, inflating costs and hiding real errors. | Sample successful requests, or log access logs separately from application lifecycle logs. |

## See Also
*   [Monitoring & Observability](../devops/monitoring_observability.md)
*   [Compliance & Regulatory](../security/compliance_regulatory.md)

## References
*   [12-Factor App: Logs](https://12factor.net/logs)
*   [Elastic Common Schema](https://www.elastic.co/guide/en/ecs/current/index.html)
