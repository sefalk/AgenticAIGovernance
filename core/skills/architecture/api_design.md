---
category: architecture
applies_to: [api, web, microservice]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [system_design, contract_testing, documentation, authentication_authorization, event_driven_architecture, frontend_architecture]
---
# API Design

## Purpose

API design defines how software components communicate. A well-designed API is intuitive, consistent, evolvable, and secure. Invoke this skill when designing new APIs, reviewing existing API contracts, or defining Level-3 API design workflows.

## Principles

- **Contract-first:** Design the API before implementing it. The API is a product; consumers shouldn't have to read the source to use it.
- **Consistency:** Naming, error formats, pagination, and authentication must follow a single convention throughout the API.
- **Evolvability:** APIs should be designed for change. Breaking changes must be versioned and communicated.
- **Separation of Concern (AAIG L1):** APIs define clear boundaries between components. Each endpoint has one responsibility.

## Techniques & Patterns

### REST API Design

#### Resource Naming
```
GET    /users              # List users
POST   /users              # Create user
GET    /users/{id}         # Get user
PUT    /users/{id}         # Replace user
PATCH  /users/{id}         # Partially update user
DELETE /users/{id}         # Delete user

GET    /users/{id}/orders  # List user's orders (sub-resource)
```

**Rules:**
- Nouns, not verbs. `GET /users`, not `GET /getUsers`.
- Plural nouns. `/users`, not `/user`.
- Lowercase, hyphen-separated. `/order-items`, not `/orderItems`.
- Nest sub-resources max 2 levels deep. Beyond that, use top-level with filters.

#### HTTP Methods and Status Codes

| Method | Semantics | Idempotent | Request Body |
|--------|-----------|------------|-------------|
| GET | Read | Yes | No |
| POST | Create | No | Yes |
| PUT | Replace | Yes | Yes |
| PATCH | Partial update | Yes (should be) | Yes |
| DELETE | Remove | Yes | No |

| Status Code | Meaning | When to Use |
|-------------|---------|-------------|
| 200 | OK | Successful GET, PUT, PATCH |
| 201 | Created | Successful POST (include Location header) |
| 204 | No Content | Successful DELETE |
| 400 | Bad Request | Invalid input |
| 401 | Unauthorized | Missing or invalid authentication |
| 403 | Forbidden | Authenticated but not authorized |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | State conflict (duplicate, concurrent edit) |
| 422 | Unprocessable Entity | Validation failure |
| 429 | Too Many Requests | Rate limit exceeded (include Retry-After header) |
| 500 | Internal Server Error | Unhandled server error |

#### Error Response Format
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request body contains invalid fields.",
    "details": [
      {
        "field": "email",
        "message": "Must be a valid email address.",
        "code": "INVALID_FORMAT"
      }
    ],
    "requestId": "req_abc123"
  }
}
```

**Rules:** Consistent error format across all endpoints. Include a machine-readable code, human-readable message, field-level details, and a request ID for tracing.

#### Pagination

```
# Offset-based (simple, but inefficient for large datasets)
GET /users?offset=20&limit=10

# Cursor-based (recommended for large/real-time datasets)
GET /users?cursor=eyJpZCI6MTAwfQ&limit=10

# Response
{
  "data": [...],
  "pagination": {
    "nextCursor": "eyJpZCI6MTEwfQ",
    "hasMore": true,
    "totalCount": 1500    // optional, can be expensive
  }
}
```

#### Versioning

| Strategy | Example | Pros | Cons |
|----------|---------|------|------|
| **URL path** | `/v1/users` | Simple, visible, cacheable | URL changes on version bump |
| **Header** | `Accept: application/vnd.api+json;version=2` | Clean URLs | Hidden, harder to test |
| **Query param** | `/users?version=2` | Simple | Can be missed, pollutes caching |

**Recommendation:** URL path versioning for external APIs (simplicity). Header versioning for internal APIs (cleaner).

#### Filtering, Sorting, Field Selection
```
GET /users?status=active&role=admin          # Filtering
GET /users?sort=-created_at,name             # Sorting (- = descending)
GET /users?fields=id,name,email              # Sparse fields
```

### GraphQL API Design

**When to use:** When clients need flexible queries, have varied data needs, or the API serves multiple frontends with different requirements.

**Key patterns:**
- Schema-first design: define the schema before resolving.
- Use connections (Relay-style) for pagination: `edges`, `nodes`, `pageInfo`.
- Limit query depth and complexity to prevent abuse.
- Use input types for mutations: `input CreateUserInput { ... }`.
- Follow naming conventions: `Query.users`, `Mutation.createUser`, `Subscription.onUserCreated`.

### gRPC API Design

**When to use:** Internal service-to-service communication where performance, streaming, or strong typing matter.

**Key patterns:**
- Use Protocol Buffers for schema definition.
- Follow Google's API design guide for proto naming.
- Use `google.protobuf.FieldMask` for partial updates.
- Use streaming RPCs for real-time data or large datasets.
- Define error details using `google.rpc.Status`.

### API Security

- **Authentication:** Use industry standards (OAuth 2.0, JWT, API keys). Never roll your own auth.
- **Authorization:** Enforce at the API layer, not just the frontend. Use RBAC or ABAC.
- **Rate limiting:** Protect against abuse. Return `429` with `Retry-After`.
- **Input validation:** Validate all inputs. Reject unexpected fields (strict parsing).
- **CORS:** Configure explicitly for browser-facing APIs. No wildcard in production.
- **HTTPS only:** No HTTP in production. Ever.

### API Documentation

- **OpenAPI / Swagger:** The standard for REST APIs. Generate from code or write spec-first.
- **AsyncAPI:** For event-driven APIs (WebSocket, Kafka, AMQP).
- **GraphQL introspection:** Built-in schema documentation. Supplement with descriptions.
- Always include: authentication instructions, example requests/responses, error codes, rate limits.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Consistent naming** | 100% | All endpoints follow the naming convention. |
| **Error format standardized** | 100% | All errors use the same structure. |
| **Documentation complete** | All endpoints documented | OpenAPI spec or equivalent, with examples. |
| **No breaking changes** | 0 unversioned | Breaking changes increment API version. |
| **Security headers** | CORS, rate-limit, auth | Enforced on all endpoints. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Verb URLs** | `POST /createUser`, `GET /getAllUsers` | Use nouns with HTTP methods: `POST /users`, `GET /users` |
| **Inconsistent errors** | Each endpoint returns errors differently | Standardize error format API-wide |
| **No pagination** | `GET /users` returns 50,000 records | Always paginate list endpoints. Default limit 20-50. |
| **Exposing internals** | Database column names, internal IDs, stack traces in errors | Use DTOs. Never expose internal structure. |
| **Ignoring HATEOAS** | Clients hardcode URL structures | Include `links` or `_links` for discoverability (when appropriate). |


## See Also

- [System Design](../architecture/system_design.md)
- [Contract Testing](../testing/contract_testing.md)
- [Documentation](../code_quality/documentation.md)

## References

- Microsoft REST API Guidelines: https://github.com/microsoft/api-guidelines
- Google API Design Guide: https://cloud.google.com/apis/design
- JSON:API Specification: https://jsonapi.org/
- OpenAPI Specification: https://spec.openapis.org/oas/latest.html
