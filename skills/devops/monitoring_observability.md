---
title: Monitoring & Observability
description: Instrumenting systems with metrics, distributed traces, and SLOs using concrete standards like OpenTelemetry
applies_to: [api, web, microservice, cloud]
complexity: intermediate
maturity: draft
version: "1.1"
last_reviewed: 2026-02-26
related: [performance_testing, ci_cd, infrastructure_as_code, configuration_management, containerization, data_pipeline_design, error_handling, event_driven_architecture, ml_pipeline_design, system_design, structured_logging]
---
# Monitoring & Observability

## Purpose
To move beyond generic "system is up/down" ping checks, providing deep, actionable visibility into the internal state of distributed systems using standardized telemetry data (Logs, Metrics, Traces) so anomalies can be root-caused immediately.

## Principles
1. **The Three Pillars are Standardized:** Emit telemetry using vendor-agnostic standards like OpenTelemetry (OTel), avoiding lock-in to specific SaaS providers.
2. **Measure at the Boundary (RED/USE):** Focus metrics on user-facing symptoms (Rate, Errors, Duration) and resource saturation (Utilization, Saturation, Errors).
3. **Alert on Symptoms, not Causes:** Alert when a user-facing Service Level Objective (SLO) is breached (e.g., "Checkout latency > 2s"), not when CPU hits 80%. CPU spikes are for dashboards, breached SLOs are for pagers. *(AAIG L1: Fail-Safe)*
4. **Contextual Tracing:** Every log and metric must be decorated with trace context (`trace_id`, `span_id`) to correlate events across microservices. *(AAIG L1: Transparency/Traceability)*

## Techniques & Patterns

### 1. Instrumentation (OpenTelemetry)
*   **Auto-Instrumentation:** Use OpenTelemetry language agents (e.g., `opentelemetry-javaagent`, Python `opentelemetry-instrument`) to automatically wrap HTTP servers, database drivers, and message queues to emit traces without manual code changes.
*   **Manual Spans:** Create custom `Span`s around complex, CPU-bound business logic, attaching attributes like `tenant_id` or `order_value` to enable faceted slicing in the backend.

### 2. Metric Collection (Prometheus Format)
*   Expose a `/metrics` endpoint in the Prometheus text format.
*   **Counters:** Monotonically increasing values (e.g., `http_requests_total`).
*   **Histograms:** For measuring distributions like latency (`http_request_duration_seconds`). Always define explicit buckets (e.g., `[0.1, 0.5, 1.0, 5.0]`) to calculate p95 and p99 percentiles accurately. Do not use generic averages.

### 3. Log Aggregation and Correlation
*   *See also: [Structured Logging](../devops/structured_logging.md)*
*   Ensure that the current `trace_id` from the OpenTelemetry context is automatically injected into the structured JSON log payload. This allows tools like Datadog, Grafana/Loki, or Kibana to instantly pivot from a slow trace directly to the logs for that exact request.

### 4. Dashboards & SLAs/SLOs
*   **Code your Dashboards:** Keep Grafana dashboard JSON models in version control alongside the application code using tools like Grizzly or Terraform, ensuring dashboards evolve with the application.

## Quality Gates
*   **SLO Definition:** The service repository contains an `slos.yaml` defining at least one Availability SLO (e.g., > 99.9% 200/300 status codes) and one Latency SLO (e.g., p95 < 200ms).
*   **Trace Context Propagation:** Integration tests intercept outbound HTTP requests to downstream mocks and verify that the `traceparent` (W3C standard) HTTP header is correctly injected.
*   **Metric Endpoint Test:** The CI build curls the `/metrics` endpoint and uses `promtool` to validate the endpoint syntax.

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **Alert Fatigue** | Paging engineers for CPU > 80% when no users are impacted trains teams to ignore alarms. | Map pagers strictly to SLO (Symptom) breaches. Use CPU usage only for dashboard investigations. |
| **Vendor SDK Lock-in** | Tightly coupling millions of lines of code to the `datadog-api-client` makes switching aggregators impossible. | Instrument code universally with OpenTelemetry APIs; let the OTel Collector handle vendor-specific export. |
| **Average Latency Metrics** | "Average latency is 50ms" hides the reality that 5% of users (often the largest customers) are experiencing 5000ms timeouts. | Always measure and alert on percentiles (p95, p99) using Histograms. |
| **Black Box Monitoring** | Relying purely on an external ping to `/healthz` provides zero context when the app starts throwing 500s. | Instrument internal code boundaries (DB queries, Redis cache hits) using Traces. |

## See Also
*   [Structured Logging](../devops/structured_logging.md)
*   [System Design](../architecture/system_design.md)

## References
*   [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
*   [Google SRE Book - Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)
