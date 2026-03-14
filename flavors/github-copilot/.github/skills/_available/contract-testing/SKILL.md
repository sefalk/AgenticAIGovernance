---
name: contract-testing
description: Verify that integrated services agree on communication structure — consumer-driven contracts, Pact framework, schema-based validation, and can-i-deploy gates.
argument-hint: '[consumer service] [provider service] [protocol: REST|gRPC|events]'
---

# Contract Testing

## When to Use

- When multiple services communicate via APIs or messaging
- When deployment independence is required (deploy without full E2E tests)
- When OpenAPI specs or message schemas must be validated
- When setting up can-i-deploy gates in CI/CD

## Principles

1. **Independent Deployability** — Each service is deployable without
   running E2E tests with every dependent service.
2. **Consumer-Driven** — The consumer defines what it needs; the provider
   verifies it satisfies all consumers' needs.
3. **Separation of Concern** — Contract tests validate the *interface*,
   not internal logic. Internals are covered by unit/integration tests.
4. **Verifiability** — Contracts are machine-verifiable specifications,
   not informal agreements.

## Techniques & Patterns

### Consumer-Driven Contract Testing (CDC)

```
Consumer side:
  1. Write test describing expected provider interactions.
  2. Generate a contract file (Pact file, OpenAPI spec).
  3. Publish to a broker.

Provider side:
  1. Fetch all consumer contracts from the broker.
  2. Replay each interaction against the real provider.
  3. Verify all interactions pass.
```

### Pact Framework (Recommended)

**Consumer test (JavaScript):**
```javascript
const { PactV3 } = require('@pact-foundation/pact');

const provider = new PactV3({
  consumer: 'OrderService',
  provider: 'InventoryService',
});

describe('Inventory API contract', () => {
  it('returns stock level', async () => {
    provider
      .given('product 123 has 50 items')
      .uponReceiving('stock level request')
      .withRequest({ method: 'GET', path: '/products/123/stock' })
      .willRespondWith({
        status: 200,
        body: { productId: '123', quantity: 50 },
      });

    await provider.executeTest(async (mockServer) => {
      const client = new InventoryClient(mockServer.url);
      const result = await client.getStock('123');
      expect(result.quantity).toBe(50);
    });
  });
});
```

Language support: JavaScript, Java, Python, Go, Ruby, .NET, Rust, Swift.

### Schema-Based Contract Testing

| Approach | Tool | When to Use |
|----------|------|-------------|
| OpenAPI validation | Spectral, Schemathesis | REST APIs with OpenAPI specs |
| JSON Schema | `ajv`, `jsonschema` | Simple request/response validation |
| Protocol Buffers | `buf breaking` | gRPC services |
| GraphQL | GraphQL Inspector | GraphQL APIs |
| AsyncAPI | AsyncAPI tools | Event-driven systems |

### Event / Message Contracts

For async communication (Kafka, RabbitMQ, SNS): consumer defines expected
message structure, generates contract, provider verifies it produces
matching messages. Pact supports message contracts natively.

### CI/CD Integration

```
Consumer pipeline: test → generate contract → publish to broker
Provider pipeline: fetch contracts → verify → can-i-deploy → deploy
```

**Rule:** Never deploy without `can-i-deploy` passing.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **All consumer contracts verified** | 100% | Provider passes all published contracts. |
| **can-i-deploy** | Pass | Mandatory before any deployment. |
| **No breaking changes** | 0 | Additive only. Breaking changes require consumer migration. |
| **Contract coverage** | All critical endpoints | Every production API endpoint has a contract. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Provider-driven contracts** | Provider defines without consumer input. Breaks silently. | Consumer-driven: consumers specify needs. |
| **Contract as integration test** | Testing business logic in contracts. Slow, brittle. | Contracts verify structure only. |
| **Skipping can-i-deploy** | Deploy without compatibility check. Outages. | Make it a mandatory CI gate. |
| **No versioning** | No rollback, no compatibility history. | Version everything via Pact Broker. |

## References

- Pact: https://docs.pact.io/
- PactFlow: https://pactflow.io/
- Martin Fowler, ["ContractTest"](https://martinfowler.com/bliki/ContractTest.html)
- Sam Newman, *Building Microservices* (2021), Ch. 7
