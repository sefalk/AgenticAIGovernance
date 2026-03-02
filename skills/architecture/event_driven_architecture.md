---
category: architecture
applies_to: [microservice, cloud, api]
complexity: advanced
maturity: reviewed
version: "1.0"
last_reviewed: 2026-02-26
related: [system_design, api_design, monitoring_observability, design_patterns, embedded_systems]
---
# Event-Driven Architecture

## Purpose

Event-driven architecture (EDA) organizes systems around the production, detection, and reaction to events -- significant changes in state. This skill covers messaging patterns, event sourcing, CQRS, and saga orchestration. Invoke this skill when designing systems with asynchronous workflows, decoupled services, or real-time data flows.

## Principles

- **Separation of Concern (AAIG L1):** Producers and consumers must be decoupled. A producer publishes events without knowing who consumes them.
- **Transparency (AAIG L1):** Event flows must be traceable. Every event must carry a correlation ID enabling end-to-end tracing.
- **Verifiability (AAIG L1):** Event schemas must be versioned and validated. Invalid events must be routed to dead-letter queues, not silently dropped.
- **Eventual consistency:** Accept that distributed systems are eventually consistent. Design compensation mechanisms, not distributed transactions.

## Techniques & Patterns

### Core Messaging Patterns

| Pattern | Description | Use Case |
|---------|-------------|----------|
| **Publish/Subscribe** | Producers emit events; multiple independent consumers react | Notifications, analytics, cross-service sync |
| **Event Streaming** | Ordered, durable event log | Real-time analytics, audit trail, replay |
| **Point-to-Point (Queue)** | One producer, one consumer per message | Task distribution, work queues |
| **Request/Reply** | Async request with correlation-based response | Async API calls, saga steps |

### Message Brokers

| Broker | Type | Strengths | Best For |
|--------|------|-----------|----------|
| **Apache Kafka** | Event streaming | Durable, ordered, high throughput, replay | Event sourcing, stream processing, audit logs |
| **RabbitMQ** | Message queue | Flexible routing, protocols (AMQP), mature | Task queues, RPC, complex routing |
| **AWS SQS/SNS** | Managed queue + pub/sub | Zero ops, scalable, pay-per-use | AWS-native, simple decoupling |
| **Google Pub/Sub** | Managed pub/sub | Global, ordered, exactly-once | GCP-native, global event distribution |
| **NATS** | Lightweight messaging | Extremely fast, simple, cloud-native | Microservice communication, IoT |
| **Redis Streams** | In-memory streaming | Low latency, consumer groups | Real-time events, lightweight streaming |

### Event Sourcing

Store state as a sequence of events, not as current state:

```
Traditional:  Account { balance: 150 }
Event-sourced: [
  AccountCreated { amount: 0 },
  Deposited { amount: 200 },
  Withdrawn { amount: 50 }
]
Current state = replay(events) = 150
```

**Benefits:** Full audit trail, temporal queries ("what was the balance on Jan 1?"), replay/rebuild.
**Cost:** Complexity, eventual consistency, snapshot management for performance.

### CQRS (Command Query Responsibility Segregation)

Separate the write model (commands) from the read model (queries):

```
Command side --> Events --> Event Store
                   |
                   v
              Projection --> Read Database --> Query side
```

**When to use:** Different read/write patterns, complex domains, high read scalability needs.
**When NOT to use:** Simple CRUD applications. CQRS adds significant complexity.

### Saga Pattern (Distributed Transactions)

| Type | Coordination | Rollback | Use Case |
|------|-------------|----------|----------|
| **Choreography** | Events between services | Compensating events | Simple flows, few services |
| **Orchestration** | Central saga coordinator | Coordinator triggers compensation | Complex flows, many services |

```
Choreography saga:
  OrderService --> OrderCreated
  PaymentService <-- (reacts) --> PaymentCompleted
  InventoryService <-- (reacts) --> InventoryReserved
  ShippingService <-- (reacts) --> ShipmentScheduled

  If PaymentFailed --> OrderService emits OrderCancelled
                   --> InventoryService releases reservation
```

### Event Schema Design

```json
{
  "event_id": "uuid",
  "event_type": "OrderPlaced",
  "event_version": "1.2",
  "timestamp": "2026-02-26T22:00:00Z",
  "correlation_id": "uuid",
  "causation_id": "uuid",
  "source": "order-service",
  "data": { ... },
  "metadata": { "user_id": "...", "trace_id": "..." }
}
```

**Schema evolution rules:**
- Adding fields is backward-compatible.
- Removing or renaming fields requires a new event version.
- Use a schema registry (Confluent, AWS Glue) to enforce contracts.

### Dead-Letter Queue (DLQ) Strategy

1. Consumer fails to process event.
2. Retry with exponential backoff (3 attempts default).
3. After max retries, route to DLQ.
4. Alert on DLQ depth.
5. Manual investigation + replay from DLQ after fix.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Schema registry** | All events registered | Schema validation on produce and consume |
| **Idempotent consumers** | Verified | Consumers must handle duplicate events safely |
| **DLQ configured** | Every consumer | Alert on DLQ depth > 0 |
| **Correlation ID present** | 100% of events | Enables end-to-end tracing |
| **Event ordering verified** | Where required | Partition-key strategy documented |
| **Consumer lag monitored** | SLA defined | Alert when consumer falls behind |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Event as command** | Publishing events that tell consumers what to do. Tight coupling disguised as events. | Events describe what happened, not what should happen. |
| **Missing idempotency** | Consumer processes duplicate events, causing double charges or double writes. | Idempotency key (event_id) + deduplication check. |
| **Event spaghetti** | Dozens of microservices reacting to each other's events with no clear flow. Impossible to debug. | Document event flows. Use choreography for simple flows, orchestration for complex ones. |
| **Synchronous over async** | Using request/reply pattern for everything over a message broker. Worse than HTTP. | Use messaging for async. Use HTTP/gRPC for synchronous calls. |
| **Fat events** | Putting entire entity state in every event. Bandwidth waste, coupling. | Include only changed fields + entity ID. Consumers fetch full state if needed. |
| **Ignoring ordering** | Assuming events arrive in order without partition keys. | Use entity ID as partition key in Kafka. Design consumers to handle out-of-order delivery. |

## See Also

- [System Design](../architecture/system_design.md)
- [API Design](../architecture/api_design.md)
- [Monitoring & Observability](../devops/monitoring_observability.md)

## References

- Designing Event-Driven Systems (Stopford): https://www.confluent.io/designing-event-driven-systems/
- Kafka: https://kafka.apache.org/
- Saga pattern (microservices.io): https://microservices.io/patterns/data/saga.html
