---
category: security
applies_to: [all]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [security_testing, secrets_management, threat_modeling, dependency_management, authentication_authorization, compliance_regulatory, embedded_systems, code_review]
---
# Secure Coding

## Purpose

Secure coding practices prevent vulnerabilities from being introduced during development. This skill covers secure coding patterns, common vulnerability classes, and language-specific hardening. It complements `testing/security_testing.md` (which detects vulnerabilities) by focusing on prevention. Invoke this skill when writing code that handles user input, authentication, data storage, or external communication.

## Principles

- **Defense in depth:** No single control is sufficient. Layer validation, authentication, authorization, and encryption.
- **Least privilege:** Code should have only the permissions it needs. No admin connections, no wildcard access.
- **Secure by default:** Default configurations should be secure. Users must opt into less security, not opt out.
- **Safety & Security (AAIG L1):** All code must adhere to highest safety and security standards.

## Techniques & Patterns

### Input Validation

**All external input is untrusted.** Validate before processing.

| Technique | Description |
|-----------|-------------|
| **Allowlist validation** | Accept only known-good patterns. Reject everything else. |
| **Type coercion** | Parse input into typed values early (int, date, enum). |
| **Length limits** | Enforce maximum lengths on all string inputs. |
| **Encoding** | Normalize encoding (UTF-8) before processing. |

```python
# Python -- input validation example
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
| **SQL injection** | Parameterized queries (prepared statements). Never concatenate user input into SQL. |
| **XSS** | Output encoding (HTML-escape user content). Use framework auto-escaping (React, Jinja2). Content-Security-Policy headers. |
| **Command injection** | Avoid `os.system()`, `eval()`, `exec()`. Use subprocess with array arguments, not shell strings. |
| **Path traversal** | Validate and canonicalize file paths. Reject `../`. Use allowlisted base directories. |
| **LDAP injection** | Escape special characters. Use parameterized LDAP queries. |
| **Template injection** | Use sandboxed template engines. Never pass user input as template code. |

```python
# SQL injection prevention
# BAD:
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")

# GOOD:
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
```

```javascript
// XSS prevention in React (auto-escaped by default)
// BAD:
<div dangerouslySetInnerHTML={{ __html: userInput }} />

// GOOD:
<div>{userInput}</div>  // React auto-escapes
```

### Authentication Best Practices

| Practice | Details |
|----------|---------|
| **Password hashing** | Use bcrypt, scrypt, or Argon2id. Never MD5, SHA-1, or plain SHA-256. |
| **MFA** | Implement TOTP or WebAuthn for sensitive accounts. |
| **Session management** | Random, high-entropy session IDs. Expire sessions on inactivity. Regenerate on privilege change. |
| **OAuth/OIDC** | Use established libraries. Never implement OAuth from scratch. |
| **Rate limiting** | Limit login attempts (5 per minute per account). Use CAPTCHA after threshold. |

```python
# Password hashing with bcrypt
import bcrypt

hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12))
is_valid = bcrypt.checkpw(password.encode(), hashed)
```

### Authorization Patterns

| Pattern | Description | When to Use |
|---------|-------------|-------------|
| **RBAC** (Role-Based Access Control) | Permissions assigned to roles, roles assigned to users | Most common. Suitable for most applications. |
| **ABAC** (Attribute-Based Access Control) | Policies based on user, resource, and context attributes | Complex, fine-grained access needs |
| **ReBAC** (Relationship-Based Access Control) | Access based on relationships between entities | Social graphs, document sharing (Google Docs model) |

**Rules:**
- Enforce authorization on the server, never the client.
- Check permissions at every API endpoint, not just the UI.
- Default deny. Whitelist access, don't blacklist.

### Cryptography

| Do | Don't |
|----|-------|
| Use TLS 1.3 (minimum TLS 1.2) | Use TLS 1.0/1.1 or SSL |
| Use AES-256-GCM for symmetric encryption | Use DES, 3DES, or RC4 |
| Use RSA-2048+ or Ed25519 for asymmetric | Use RSA-1024 or DSA |
| Use established libraries (`cryptography`, `libsodium`) | Roll your own crypto |
| Generate keys using CSPRNG | Use `random()` or `Math.random()` for security |

### Error Handling

```python
# BAD: Exposes internal details
try:
    user = db.get_user(user_id)
except Exception as e:
    return {"error": str(e)}  # Stack trace, DB schema, internal paths

# GOOD: Generic message, log detail internally
try:
    user = db.get_user(user_id)
except Exception:
    logger.exception("Failed to fetch user", extra={"user_id": user_id})
    return {"error": "An internal error occurred.", "requestId": request_id}
```

**Rules:**
- Never expose stack traces, database errors, or internal paths to users.
- Log the full error internally with request ID for debugging.
- Return generic error messages with a correlation ID.

### Secure Defaults Checklist

- [ ] HTTPS enforced (HSTS header)
- [ ] CORS configured explicitly (no wildcard in production)
- [ ] Security headers set (CSP, X-Content-Type-Options, X-Frame-Options)
- [ ] Cookies: `Secure`, `HttpOnly`, `SameSite=Strict`
- [ ] Debug mode disabled in production
- [ ] Admin endpoints not publicly accessible
- [ ] Default credentials changed / removed
- [ ] Error pages don't leak information

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **No hardcoded secrets** | 0 | Verified by secret scanning in CI. |
| **All user input validated** | 100% | Validated at the API boundary before processing. |
| **Parameterized queries** | 100% | No string concatenation in SQL/LDAP/command construction. |
| **Secure password storage** | bcrypt/Argon2id | No reversible encryption or weak hashes. |
| **Security headers** | All required headers set | HSTS, CSP, X-Content-Type-Options minimum. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Trusting client-side validation** | Attackers bypass client code. | Always validate server-side. Client validation is UX only. |
| **Security by obscurity** | Hiding admin URLs, relying on secret paths. | Proper authentication and authorization. |
| **Catching all exceptions silently** | `except: pass` hides security-relevant errors. | Log exceptions. Alert on unexpected patterns. |
| **Rolling your own crypto** | Home-grown encryption is always broken. | Use established libraries and algorithms. |
| **Logging sensitive data** | Passwords, tokens, PII in log files. | Redact sensitive fields. Use structured logging. |


## See Also

- [Security Testing](../testing/security_testing.md)
- [Secrets Management](../security/secrets_management.md)
- [Threat Modeling](../security/threat_modeling.md)
- [Dependency Management](../code_quality/dependency_management.md)

## References

- OWASP Secure Coding Practices: https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/
- OWASP Cheat Sheet Series: https://cheatsheetseries.owasp.org/
- CERT Secure Coding Standards: https://wiki.sei.cmu.edu/confluence/display/seccode
