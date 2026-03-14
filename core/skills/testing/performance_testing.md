---
category: testing
applies_to: [api, web, microservice]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [monitoring_observability, e2e_testing]
---
# Performance Testing

## Purpose

Performance testing validates that a system meets its non-functional requirements under expected and peak load conditions. It answers: "How fast is it?", "How much can it handle?", and "When does it break?" Invoke this skill when the project has latency SLOs, throughput requirements, or must handle concurrent users at scale.

## Principles

- **Measure, don't guess:** Every performance claim must be backed by reproducible benchmark data.
- **Test early, test often:** Performance regressions are cheaper to fix when caught early. Integrate performance checks into CI, not just pre-release.
- **Production-like conditions:** Performance tests must run against environments that closely resemble production in hardware, data volume, and configuration.
- **Verifiability (AAIG L1):** SLO compliance must be programmatically verified -- pass/fail, not "looks fine."

## Techniques & Patterns

### Types of Performance Tests

| Type | Objective | Duration | Load Profile |
|------|-----------|----------|-------------- |
| **Load test** | Validate behavior under expected peak load | 10-60 min | Ramp up to target, sustain, ramp down |
| **Stress test** | Find the breaking point | 15-30 min | Ramp up until failure |
| **Soak / endurance test** | Detect memory leaks and degradation over time | 2-24 hours | Sustained moderate load |
| **Spike test** | Validate behavior under sudden load bursts | 5-15 min | Sudden spike, return to baseline |
| **Breakpoint test** | Identify maximum capacity | Variable | Incremental ramp until SLO breach |
| **Configuration test** | Compare performance across configs | Variable | Same load, different configurations |

### Key Metrics

| Metric | Description | Typical SLO |
|--------|-------------|-------------|
| **Response time (p50, p95, p99)** | Latency percentiles. p99 is more important than average. | p95 < 200ms, p99 < 500ms |
| **Throughput (RPS)** | Requests per second the system handles. | Depends on expected load |
| **Error rate** | Percentage of requests returning errors under load. | < 0.1% at target load |
| **Concurrency** | Number of simultaneous connections/users. | Depends on architecture |
| **Resource utilization** | CPU, memory, disk I/O, network at various load levels. | CPU < 70% at target load |
| **Apdex score** | Application Performance Index (satisfied/tolerating/frustrated). | >= 0.9 |

### Tooling

#### k6 (Recommended Default)
Modern, developer-friendly, scriptable in JavaScript. Excellent for CI integration.
```javascript
// k6 example: load test
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 100 },  // ramp up to 100 VUs
    { duration: '5m', target: 100 },  // sustain
    { duration: '2m', target: 0 },    // ramp down
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

#### Other Tools

| Tool | Language | Best For |
|------|----------|----------|
| **Locust** | Python | Python-native teams, complex user behavior modeling |
| **Gatling** | Scala/Java | JVM projects, detailed HTML reports |
| **Artillery** | JS/YAML | Quick YAML-based tests, serverless workloads |
| **JMeter** | Java | GUI-based test design, protocol variety (not recommended for new projects) |
| **wrk / wrk2** | C | Raw HTTP benchmarking, maximum throughput testing |
| **hey** | Go | Quick ad-hoc HTTP benchmarking |

### Test Design Principles

1. **Model realistic user behavior:** Don't just hammer one endpoint. Model user journeys with think time, multiple endpoints, and realistic data.
2. **Use representative data:** Test with production-scale data volumes, not empty databases.
3. **Ramp gradually:** Start from zero and ramp up. This reveals the load level where degradation begins.
4. **Isolate the environment:** Performance tests on shared environments produce meaningless results.
5. **Establish baselines:** Run performance tests on the current version before changes. Compare after.

### Profiling & Root Cause Analysis

When performance tests reveal problems, profile to find the bottleneck:

| Layer | Tools |
|-------|-------|
| **Application** | Profilers: `py-spy` (Python), `async-profiler` (Java), Chrome DevTools (JS), `pprof` (Go) |
| **Database** | Query analyzers: `EXPLAIN ANALYZE` (SQL), slow query logs, index usage stats |
| **Network** | `tcpdump`, Wireshark, CDN analytics |
| **Infrastructure** | `top`/`htop`, `vmstat`, `iostat`, Prometheus + Grafana |

### CI Integration

- **Lightweight performance gates:** Run a short (1-2 min) load test on every PR to catch gross regressions.
- **Full performance suite:** Run comprehensive tests nightly or weekly.
- **Trend tracking:** Store results over time and alert on performance regression trends, not just single-run thresholds.
- **Budget:** Set a "performance budget" for key metrics and fail CI if exceeded.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **p95 response time** | < 200ms (API), < 1s (page load) | Under target load. Tighten at Level 4. |
| **p99 response time** | < 500ms (API), < 3s (page load) | Under target load. |
| **Error rate under load** | < 0.1% | At target load level. |
| **No memory leaks** | Stable RSS over 1-hour soak | Memory must not grow unbounded under sustained load. |
| **Throughput meets target** | >= X RPS as defined at Level 4 | Must sustain without degradation. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Testing on localhost** | Local results don't reflect production (network, shared resources, etc.). | Use a production-like environment with representative hardware. |
| **Averages instead of percentiles** | Average hides tail latency. p99 can be 10x the average. | Always measure and report p50, p95, p99. |
| **No baseline** | Can't tell if results are good or bad without a reference point. | Establish baselines before making changes; compare deltas. |
| **Ignoring think time** | Hammering at max rate doesn't model real users. | Add realistic delays between requests. |
| **Testing once before release** | Performance regressions accumulate unnoticed. | Run lightweight performance checks in CI continuously. |


## See Also

- [Monitoring and Observability](../devops/monitoring_observability.md)
- [E2E Testing](../testing/e2e_testing.md)

## References

- k6 documentation: https://k6.io/docs/
- Locust documentation: https://locust.io/
- Gatling documentation: https://gatling.io/docs/
- Brendan Gregg, *Systems Performance* (2020) -- comprehensive guide to systems performance analysis.
- Google SRE Book, Ch. 4 "Service Level Objectives" -- https://sre.google/sre-book/service-level-objectives/
