---
category: testing
applies_to: [microservice, api]
complexity: advanced
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [integration_testing, api_design]
---
# Contract Testing

## Purpose

Contract testing verifies that integrated services agree on the structure and semantics of their communication (APIs, messages, events). Unlike integration tests that require both services running, contract tests verify each side independently against a shared contract. Invoke this skill when the project has multiple services that communicate via APIs or messaging, and deployment independence is required.

## Principles

- **Independent deployability:** Each service should be deployable without requiring end-to-end tests with every dependent service.
- **Consumer-driven:** The consumer defines what it needs from the provider. The provider verifies it satisfies all consumers' needs.
- **Separation of Concern (AAIG L1):** Contract tests validate the *interface*, not the internal logic. Internal behavior is covered by unit and integration tests.
- **Verifiability (AAIG L1):** Contracts are machine-verifiable specifications, not informal agreements.

## Techniques & Patterns

### Consumer-Driven Contract Testing (CDC)

The gold-standard approach. The consumer defines the contract; the provider verifies it.

```
Consumer side:
1. Write a test that describes the interactions you expect from the provider.
2. Generate a contract file (Pact file, OpenAPI spec, etc.).
3. Publish the contract to a broker.

Provider side:
1. Fetch all consumer contracts from the broker.
2. Replay each interaction against the real provider.
3. Verify all interactions pass.
```

**Why consumer-driven?** The provider doesn't know how consumers use its API. The consumer does. This ensures the provider doesn't break what consumers actually depend on.

### Pact Framework (Recommended)

The most widely adopted contract testing framework. Available for all major languages.

**Consumer test example (JavaScript):**
```javascript
const { PactV3 } = require('@pact-foundation/pact');

const provider = new PactV3({
  consumer: 'OrderService',
  provider: 'InventoryService',
});

describe('Inventory API contract', () => {
  it('returns stock level for a product', async () => {
    provider
      .given('product 123 has 50 items in stock')
      .uponReceiving('a request for stock level')
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

**Provider verification (JavaScript):**
```javascript
const { Verifier } = require('@pact-foundation/pact');

new Verifier({
  providerBaseUrl: 'http://localhost:3000',
  pactBrokerUrl: 'https://your-broker.pactflow.io',
  provider: 'InventoryService',
  providerStatesSetupUrl: 'http://localhost:3000/_pact/setup',
}).verifyProvider();
```

**Language support:** JavaScript, Java, Python, Go, Ruby, .NET, Rust, Swift, PHP -- via Pact FFI.

### Pact Broker

Central repository for contracts. Enables:
- **can-i-deploy:** Before deploying a service, check if the current version is compatible with all deployed consumers/providers.
- **Versioning:** Each contract is versioned. Track which versions are compatible.
- **Webhooks:** Trigger provider verification automatically when a new consumer contract is published.

### Schema-Based Contract Testing

For simpler needs or when Pact is too heavyweight.

| Approach | Tool | When to Use |
|----------|------|-------------|
| **OpenAPI validation** | Spectral, Schemathesis, `openapi-diff` | REST APIs with OpenAPI specs |
| **JSON Schema validation** | `ajv`, `jsonschema` | Simple request/response validation |
| **Protocol Buffers** | `buf breaking` | gRPC services |
| **GraphQL** | GraphQL Inspector | GraphQL APIs, schema diff |
| **AsyncAPI** | AsyncAPI tools | Event-driven / message-based systems |

### Event / Message Contracts

For asynchronous communication (Kafka, RabbitMQ, SNS, etc.):

```
1. Consumer defines the expected message structure.
2. Generate a contract for the message schema.
3. Provider verifies it produces messages matching the contract.
```

Pact supports message contracts natively: `MessageConsumerPact` / `MessageProviderPact`.

### CI/CD Integration

```
Consumer pipeline:
  test --> generate contract --> publish to broker

Provider pipeline:
  fetch contracts --> verify --> can-i-deploy --> deploy

Deployment check:
  pact-broker can-i-deploy --pacticipant InventoryService
                           --version $(git rev-parse HEAD)
                           --to-environment production
```

**Rules:**
- Never deploy without `can-i-deploy` passing.
- Consumer publishes first; provider verifies against it.
- Use tagged environments (`dev`, `staging`, `production`) to track compatibility per environment.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **All consumer contracts verified** | 100% | Provider must pass all published consumer contracts. |
| **can-i-deploy** | Pass | Must pass before any deployment to any environment. |
| **No breaking changes** | 0 | Additive changes only (new fields optional). Breaking changes require consumer migration. |
| **Contract coverage** | All critical endpoints | Every API endpoint used in production must have at least one contract. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Provider-driven contracts** | Provider defines the contract without consumer input. Breaks consumers silently. | Use consumer-driven: consumers specify what they need. |
| **Contract test as integration test** | Testing business logic in contract tests. Slow, brittle. | Contract tests verify structure/schema only. Logic goes in unit tests. |
| **Sharing a database between tests** | Contract test setup modifies shared state. | Use provider states (`given()`) with isolated setup per interaction. |
| **Skipping can-i-deploy** | Deploying without checking compatibility. Outages. | Make `can-i-deploy` a mandatory CI gate before any deploy. |
| **No versioning** | Contracts without version tracking. No rollback, no compatibility history. | Version everything. Use Pact Broker's built-in versioning. |


## See Also

- [Integration Testing](../testing/integration_testing.md)
- [API Design](../architecture/api_design.md)

## References

- Pact documentation: https://docs.pact.io/
- PactFlow (managed broker): https://pactflow.io/
- Martin Fowler, ["ContractTest"](https://martinfowler.com/bliki/ContractTest.html) -- concept definition.
- Sam Newman, *Building Microservices* (2021), Ch. 7 -- contract testing in microservice architectures.
