---
name: secure-coding
description: Prevent vulnerabilities during development — input validation, injection prevention, authentication, authorization, cryptography, and error handling best practices.
argument-hint: '[code or module] [focus: input|injection|auth|crypto|errors]'
---

# Secure Coding

## When to Use

- When writing code that handles user input or external data
- When implementing authentication or authorization
- When reviewing code for security vulnerabilities
- When establishing secure coding standards for a project

## Principles

1. **Defense in Depth** — Layer validation, authentication, authorization,
   and encryption. No single control is sufficient.
2. **Least Privilege** — Code should have only the permissions it needs.
3. **Secure by Default** — Default configurations must be secure. Users
   opt *into* less security, not *out of* it.
4. **Trust No Input** — All external input is untrusted until validated.

## Techniques & Patterns

### Input Validation

| Technique | Description |
|-----------|-------------|
| **Allowlist validation** | Accept only known-good patterns. Reject everything else. |
| **Type coercion** | Parse into typed values early (int, date, enum). |
| **Length limits** | Enforce max lengths on all string inputs. |
| **Encoding normalization** | Normalize to UTF-8 before processing. |

```python
from pydantic import BaseModel, validator, constr

class CreateUserRequest(BaseModel):
    email: constr(max_length=254, regex=r'^[^@]+@[^@]+\.[^@]+$')
    name: constr(min_length=1, max_length=100)
    age: int

    @validator('age')
    def age_must_be_valid(cls, v):
        if v < 0 or v > 150:
            raise ValueError('Age must be between 0 and 150')
        return v
```

### Injection Prevention

| Attack | Defense |
|--------|---------|
| **SQL injection** | Parameterized queries. Never concatenate user input into SQL. |
| **XSS** | Output encoding. Framework auto-escaping. CSP headers. |
| **Command injection** | Avoid `os.system()`, `eval()`. Use subprocess with array args. |
| **Path traversal** | Canonicalize paths. Reject `../`. Use allowlisted base dirs. |
| **Template injection** | Sandboxed engines. Never pass user input as template code. |

### Authentication

| Practice | Details |
|----------|---------|
| **Password hashing** | bcrypt, scrypt, or Argon2id. Never MD5/SHA-1. |
| **MFA** | TOTP or WebAuthn for sensitive accounts. |
| **Session management** | Random high-entropy IDs. Regenerate on privilege change. |
| **Rate limiting** | 5 login attempts/min per account. CAPTCHA after threshold. |

### Authorization Patterns

| Pattern | When to Use |
|---------|-------------|
| **RBAC** | Most applications. Roles → permissions. |
| **ABAC** | Complex, fine-grained needs. Attribute-based policies. |
| **ReBAC** | Social graphs, document sharing. Relationship-based. |

**Rules:** Enforce server-side. Check at every endpoint. Default deny.

### Cryptography

| Do | Don't |
|----|-------|
| TLS 1.3 (min 1.2) | TLS 1.0/1.1, SSL |
| AES-256-GCM | DES, 3DES, RC4 |
| RSA-2048+ or Ed25519 | RSA-1024, DSA |
| Established libraries | Roll your own crypto |
| CSPRNG for keys | `random()` / `Math.random()` |

### Error Handling

```python
# BAD: Exposes internals
except Exception as e:
    return {"error": str(e)}

# GOOD: Generic message, log details
except Exception:
    logger.exception("Failed to fetch user", extra={"user_id": user_id})
    return {"error": "An internal error occurred.", "requestId": request_id}
```

### Secure Defaults Checklist

- [ ] HTTPS enforced (HSTS)
- [ ] CORS explicitly configured (no wildcard in production)
- [ ] Security headers (CSP, X-Content-Type-Options, X-Frame-Options)
- [ ] Cookies: `Secure`, `HttpOnly`, `SameSite=Strict`
- [ ] Debug mode disabled in production
- [ ] Default credentials changed / removed

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **No hardcoded secrets** | 0 | Secret scanning in CI |
| **All user input validated** | 100% | Validated at API boundary |
| **Parameterized queries** | 100% | No string concat in SQL/commands |
| **Secure password storage** | bcrypt/Argon2id | No weak hashes |
| **Security headers** | All required | HSTS, CSP minimum |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Trusting client validation** | Attackers bypass client code. | Always validate server-side. |
| **Security by obscurity** | Hidden URLs, secret paths. | Proper auth and authz. |
| **Silent exception swallowing** | `except: pass` hides security errors. | Log and alert. |
| **Rolling your own crypto** | Always broken. | Established libraries. |
| **Logging sensitive data** | Passwords/tokens in logs. | Redact. Structured logging. |

## References

- OWASP Secure Coding Practices: https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/
- OWASP Cheat Sheet Series: https://cheatsheetseries.owasp.org/
