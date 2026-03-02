---
category: architecture
applies_to: [microservice, cloud, web]
complexity: advanced
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [api_design, design_patterns, monitoring_observability, database_design, event_driven_architecture, embedded_systems]
---
# System Design

## Purpose

System design is the process of defining the architecture, components, interfaces, and infrastructure of a software system to satisfy functional and non-functional requirements. Invoke this skill when designing new systems, evaluating architectural alternatives, or defining Level-3 system design workflows.

## Principles

- **Requirements-driven:** Architecture emerges from requirements (functional + non-functional), not from technology preferences.
- **Trade-off awareness:** Every architectural decision involves trade-offs. Document them explicitly (see ADRs in documentation.md).
- **Separation of Concern (AAIG L1):** Components must have clear, bounded responsibilities.
- **Efficiency (AAIG L1):** Start with the simplest architecture that meets requirements. Evolve when evidence demands it.

## Techniques & Patterns

### Design Process

```
1. Clarify requirements (functional + non-functional)
2. Estimate scale (users, data volume, throughput, latency)
3. Define high-level architecture (components, data flow)
4. Deep-dive into critical components
5. Address non-functional concerns (scaling, availability, security)
6. Identify trade-offs and document decisions
```

### Architectural Styles

| Style | When to Use | Key Trade-off |
|-------|-------------|---------------|
| **Monolith** | Small teams, early stage, low complexity | Simple to deploy, hard to scale independently |
| **Modular monolith** | Medium complexity, need clean boundaries without distributed overhead | Best of both worlds, but requires discipline |
| **Microservices** | Large teams, independent deployment needs, polyglot | Operational complexity for deployment independence |
| **Event-driven** | Async processing, decoupled services, event sourcing | Eventual consistency, debugging complexity |
| **Serverless** | Variable/bursty workloads, minimal ops team | Cold starts, vendor lock-in, limited execution time |
| **CQRS** | Separate read/write scaling, complex query requirements | Complexity, eventual consistency between models |

### Scalability Patterns

#### Horizontal Scaling
| Pattern | Description |
|---------|-------------|
| **Load balancer** | Distribute requests across multiple instances (round-robin, least connections, consistent hashing) |
| **Stateless services** | Store state externally (database, cache, session store) so any instance can handle any request |
| **Database sharding** | Partition data across multiple database instances by key (user_id, region, etc.) |
| **Read replicas** | Scale reads independently using database replication |

#### Caching
| Layer | Tool Examples | Use Case |
|-------|---------------|----------|
| **CDN** | CloudFront, Cloudflare, Fastly | Static assets, edge caching |
| **Application cache** | Redis, Memcached | Hot data, session, rate-limit counters |
| **Query cache** | Materialized views, pre-computed results | Expensive queries run frequently |
| **Client cache** | HTTP Cache-Control headers, localStorage | Reduce requests |

**Cache invalidation strategies:**
- **TTL (Time-to-Live):** Simplest. Cache expires after fixed time.
- **Write-through:** Update cache on every write.
- **Write-behind:** Update cache immediately, persist asynchronously.
- **Cache-aside (Lazy loading):** Load into cache on first read. Most common.

### Reliability Patterns

| Pattern | Purpose |
|---------|---------|
| **Circuit breaker** | Stop calling a failing service. Fail fast, recover gracefully. |
| **Retry with backoff** | Retry transient failures with exponential backoff + jitter. |
| **Bulkhead** | Isolate failures. One failing component doesn't take down the system. |
| **Timeout** | Bound wait time for external calls. Prevent cascade blocking. |
| **Health checks** | Expose liveness and readiness endpoints for orchestrators. |
| **Graceful degradation** | Return partial results or cached data when a subsystem is down. |

### Data Flow Patterns

| Pattern | Description | Use Case |
|---------|-------------|----------|
| **Request-response** | Synchronous call-and-wait | API calls, user interactions |
| **Message queue** | Async producer-consumer via broker | Task processing, order fulfillment |
| **Pub/sub** | Broadcast events to multiple subscribers | Notifications, event-driven architecture |
| **Stream processing** | Continuous processing of event streams | Real-time analytics, log processing |
| **Batch processing** | Process large volumes on schedule | ETL, report generation |

### Non-Functional Requirements Checklist

| Concern | Questions to Answer |
|---------|--------------------|
| **Scalability** | Peak users? Data growth rate? Read/write ratio? |
| **Availability** | Required uptime (99.9%? 99.99%)? RPO/RTO? |
| **Latency** | p95 latency target? Geographic distribution? |
| **Durability** | Can data be lost? Backup/restore strategy? |
| **Security** | Authentication? Authorization? Data encryption? Compliance? |
| **Observability** | What metrics, logs, traces are needed? Alerting? |
| **Cost** | Budget constraints? Cost per request/user? |
| **Compliance** | GDPR? HIPAA? SOC2? Data residency? |

### System Design Documentation

Every system design should produce:
1. **Context diagram:** System boundaries and external interfaces.
2. **Component diagram:** Internal services, databases, caches, queues, and their interactions.
3. **Data flow diagram:** How data moves through the system for key use cases.
4. **Non-functional requirements table:** Concrete targets for scalability, availability, latency.
5. **ADRs:** Key architectural decisions with trade-off analysis (see documentation.md).

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Requirements coverage** | All functional + non-functional addressed | Every requirement maps to an architectural component. |
| **Trade-offs documented** | All major decisions | ADR for each architectural choice. |
| **Single point of failure** | 0 | Every critical component has redundancy or failover. |
| **Disaster recovery plan** | Defined | RTO/RPO targets met. Backup/restore tested. |
| **Capacity plan** | Defined | Scaling strategy for 10x current load. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Resume-driven development** | Choosing Kubernetes/microservices for a TODO app. | Start simple. Evolve when evidence demands it. |
| **Distributed monolith** | Microservices that must deploy together. Worst of both worlds. | If services can't deploy independently, they're one service. |
| **No backpressure** | Producer overwhelms consumer. Out of memory. | Use bounded queues, rate limiting, circuit breakers. |
| **Synchronous everything** | Long chains of synchronous calls. One slow service blocks all. | Use async messaging for non-time-critical operations. |
| **No observability** | System is a black box in production. | Build in metrics, logs, traces from day one. |


## See Also

- [API Design](../architecture/api_design.md)
- [Design Patterns](../architecture/design_patterns.md)
- [Monitoring and Observability](../devops/monitoring_observability.md)

## References

- Martin Kleppmann, *Designing Data-Intensive Applications* (2017) -- the essential system design book.
- Alex Xu, *System Design Interview* (2020) -- practical system design examples.
- Google SRE Book: https://sre.google/sre-book/table-of-contents/
- Microsoft Azure Architecture Center: https://learn.microsoft.com/en-us/azure/architecture/
