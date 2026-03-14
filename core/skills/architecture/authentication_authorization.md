---
category: architecture
applies_to: [web, api, mobile, microservice]
complexity: intermediate
maturity: reviewed
version: "1.0"
last_reviewed: 2026-02-26
related: [secure_coding, threat_modeling, api_design, secrets_management, design_patterns, compliance_regulatory]
---
# Authentication & Authorization

## Purpose

Authentication (authn) verifies identity; authorization (authz) controls access. This skill covers OAuth 2.0, OIDC, RBAC/ABAC, JWT handling, session management, and API security. Invoke this skill when designing auth flows, defining Level-3 security workflows, or setting up Level-4 identity provider configurations.

## Principles

- **Safety & Security (AAIG L1):** Authentication and authorization are the first line of defense. Failures here expose everything.
- **Verifiability (AAIG L1):** Auth decisions must be auditable. Every access grant or denial must be traceable with user identity, resource, action, and decision reason.
- **Defense in depth:** Never rely on a single auth layer. Combine authentication, authorization, input validation, and monitoring.
- **Least privilege:** Grant the minimum permissions needed. Default deny. Explicit allow.

## Techniques & Patterns

### Authentication Methods

| Method | Use Case | Security Level |
|--------|----------|---------------|
| **OAuth 2.0 + OIDC** | Web/mobile apps, third-party login | High (with PKCE) |
| **API keys** | Server-to-server, low-sensitivity | Low-Medium |
| **JWT (bearer tokens)** | Stateless API auth | Medium-High |
| **mTLS (mutual TLS)** | Service-to-service, zero-trust | Very High |
| **Session cookies** | Traditional web apps | Medium (with proper config) |
| **FIDO2 / WebAuthn** | Passwordless, passkeys | Very High |

### OAuth 2.0 Flows

| Flow | Use Case | Client Type |
|------|----------|-------------|
| **Authorization Code + PKCE** | Web/mobile apps, SPAs | Public clients |
| **Client Credentials** | Server-to-server, machine-to-machine | Confidential clients |
| **Device Authorization** | Smart TVs, CLI tools, IoT | Input-constrained devices |
| ~~Implicit~~ | DEPRECATED. Do not use. | - |
| ~~Resource Owner Password~~ | DEPRECATED. Do not use. | - |

### JWT Best Practices

```
Header:  { "alg": "RS256", "typ": "JWT", "kid": "key-id" }
Payload: { "sub": "user-id", "iss": "auth-server",
           "aud": "api-server", "exp": 1708900000,
           "iat": 1708896400, "scope": "read:orders" }
Signature: RS256(header + payload, private_key)
```

**DO:**
- Use RS256 (asymmetric) for distributed systems. Verify with public key only.
- Set short expiration (5-15 minutes for access tokens).
- Include `iss`, `aud`, `exp`, `iat`, `sub` claims.
- Validate ALL claims on every request.
- Use `kid` (key ID) for key rotation support.

**DON'T:**
- Use HS256 with shared secrets across services.
- Put sensitive data in the payload (it's base64, not encrypted).
- Use JWTs as session tokens (they can't be revoked without a blocklist).
- Accept "alg": "none". Ever.

### Authorization Models

| Model | Description | Best For |
|-------|-------------|----------|
| **RBAC** (Role-Based) | Users have roles; roles have permissions | Simple apps, well-defined roles |
| **ABAC** (Attribute-Based) | Policies based on user/resource/context attributes | Complex, dynamic access rules |
| **ReBAC** (Relationship-Based) | Access based on entity relationships (Zanzibar model) | Social, collaborative, document sharing |
| **ACL** (Access Control List) | Per-resource permission lists | File systems, simple resource protection |

### Session Management

| Aspect | Recommendation |
|--------|---------------|
| **Storage** | Server-side (Redis/DB). Cookie holds session ID only. |
| **Cookie flags** | `HttpOnly`, `Secure`, `SameSite=Lax` (or `Strict`) |
| **Expiration** | Idle timeout: 15-30 min. Absolute timeout: 8-24 hours. |
| **Rotation** | Regenerate session ID after login (prevent fixation). |
| **Revocation** | Invalidate on logout, password change, and suspicious activity. |

### Multi-Tenancy Isolation

| Strategy | Isolation | Complexity | Use Case |
|----------|-----------|-----------|----------|
| **Database per tenant** | Strongest | High | Regulated industries, enterprise |
| **Schema per tenant** | Strong | Medium | SaaS with moderate tenant count |
| **Row-level security** | Moderate | Low | SaaS with many tenants |
| **Token claims** | Weakest (app-level enforcement) | Low | Simple multi-tenant apps |

**Critical:** Always enforce tenant isolation at the data layer, not just the application layer. Application bugs should not leak data across tenants.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **No hardcoded credentials** | Zero | Automated secret scanning in CI |
| **HTTPS everywhere** | 100% | No plaintext auth traffic |
| **Token validation** | All claims checked | `iss`, `aud`, `exp`, signature verified on every request |
| **Least privilege enforced** | Review-verified | Default deny. Permissions explicitly granted. |
| **Session management** | Secure cookie flags | HttpOnly, Secure, SameSite set |
| **Auth audit logging** | All login/logout/failures | Shipped to SIEM or monitoring |
| **Rate limiting on auth** | Login: 5/min, Token: 100/min | Brute-force protection |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Rolling your own auth** | Custom auth systems have more bugs than battle-tested solutions. | Use established IdPs (Auth0, Keycloak, Cognito, Firebase Auth). |
| **JWT as session** | JWTs can't be revoked. A leaked token is valid until expiry. | Use short-lived JWTs + refresh tokens. Or use server-side sessions. |
| **Implicit flow** | Tokens exposed in URL fragment. Deprecated by OAuth 2.1. | Use Authorization Code + PKCE for all public clients. |
| **Mixed auth and authz** | Checking "is this user admin?" in every controller. Scattered, inconsistent. | Centralized authorization middleware or policy engine (OPA, Cedar). |
| **Tenant leakage** | Application-level tenant filtering without database enforcement. One bug = data leak. | Row-level security or schema isolation at the database level. |
| **No account lockout** | Unlimited login attempts. Brute-forceable. | Progressive lockout + CAPTCHA after failed attempts. |

## See Also

- [Secure Coding](../security/secure_coding.md)
- [Threat Modeling](../security/threat_modeling.md)
- [API Design](../architecture/api_design.md)
- [Secrets Management](../security/secrets_management.md)

## References

- OAuth 2.0: https://oauth.net/2/
- OpenID Connect: https://openid.net/connect/
- OWASP Auth Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html
- Google Zanzibar (ReBAC): https://research.google/pubs/pub48190/
- Open Policy Agent: https://www.openpolicyagent.org/
