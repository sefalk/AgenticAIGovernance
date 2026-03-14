---
name: performance-testing
description: Validate that systems meet latency, throughput, and resource usage requirements under load — load/stress/soak/spike tests, tooling (k6, Locust), metrics, and CI integration.
argument-hint: '[system or API] [test type: load|stress|soak|spike]'
---

# Performance Testing

## When to Use

- When the project has latency SLOs or throughput requirements
- When validating capacity under expected or peak load
- When detecting memory leaks or degradation over time
- When establishing performance budgets in CI

## Principles

1. **Measure, Don't Guess** — Every performance claim must be backed by
   reproducible benchmark data.
2. **Test Early, Test Often** — Integrate performance checks into CI,
   not just pre-release.
3. **Production-Like Conditions** — Tests must run against environments
   resembling production in hardware, data volume, and configuration.
4. **Verifiability** — SLO compliance is programmatically verified —
   pass/fail, not "looks fine."

## Techniques & Patterns

### Types of Performance Tests

| Type | Objective | Duration | Load Profile |
|------|-----------|----------|--------------|
| **Load test** | Validate at expected peak | 10–60 min | Ramp up, sustain, ramp down |
| **Stress test** | Find the breaking point | 15–30 min | Ramp until failure |
| **Soak / endurance** | Detect leaks over time | 2–24 hours | Sustained moderate load |
| **Spike test** | Sudden load bursts | 5–15 min | Sudden spike, back to baseline |
| **Breakpoint test** | Max capacity | Variable | Incremental ramp until SLO breach |

### Key Metrics

| Metric | Description | Typical SLO |
|--------|-------------|-------------|
| **Response time p50/p95/p99** | Latency percentiles | p95 < 200ms, p99 < 500ms |
| **Throughput (RPS)** | Requests per second | Depends on expected load |
| **Error rate** | % of errors under load | < 0.1% at target load |
| **Resource utilization** | CPU, memory, disk, network | CPU < 70% at target |

### Tooling

| Tool | Language | Best For |
|------|----------|----------|
| **k6** (recommended) | JavaScript | CI integration, developer-friendly |
| **Locust** | Python | Python teams, complex user modeling |
| **Gatling** | Scala/Java | JVM projects, HTML reports |
| **Artillery** | JS/YAML | Quick YAML tests, serverless |
| **wrk / wrk2** | C | Raw HTTP benchmarking |

#### k6 Example

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 100 },
    { duration: '2m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<200', 'p(99)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const res = http.get('https://api.example.com/endpoint');
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(1);
}
```

### Test Design Principles

1. Model realistic user behavior with think time and multiple endpoints.
2. Use production-scale data volumes.
3. Ramp gradually to reveal degradation thresholds.
4. Isolate the environment — shared environments give meaningless results.
5. Establish baselines before changes; compare deltas.

### Profiling & Root Cause Analysis

| Layer | Tools |
|-------|-------|
| Application | `py-spy`, `async-profiler`, Chrome DevTools, `pprof` |
| Database | `EXPLAIN ANALYZE`, slow query logs |
| Infrastructure | `top`/`htop`, Prometheus + Grafana |

### CI Integration

- **Lightweight gates:** 1–2 min load test on every PR for gross regressions.
- **Full suite:** Comprehensive tests nightly or weekly.
- **Trend tracking:** Store results over time. Alert on regression trends.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **p95 response time** | < 200ms (API) | Under target load |
| **p99 response time** | < 500ms (API) | Under target load |
| **Error rate under load** | < 0.1% | At target load level |
| **No memory leaks** | Stable RSS over 1h soak | No unbounded growth |
| **Throughput meets target** | ≥ X RPS | Must sustain without degradation |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Testing on localhost** | Local ≠ production. | Production-like environment. |
| **Averages over percentiles** | Hides tail latency. | Always report p50, p95, p99. |
| **No baseline** | Can't tell if results are good. | Establish baselines first. |
| **Ignoring think time** | Max-rate hammering ≠ real users. | Realistic delays between requests. |
| **Testing once before release** | Regressions accumulate. | CI performance checks continuously. |

## References

- k6: https://k6.io/docs/
- Locust: https://locust.io/
- Brendan Gregg, *Systems Performance* (2020)
- Google SRE Book, Ch. 4 "Service Level Objectives"
