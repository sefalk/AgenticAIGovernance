---
name: secrets-management
description: Store, access, rotate, and protect sensitive credentials — managed services, injection patterns, rotation strategies, detection, and emergency response.
argument-hint: '[secret type or concern] [environment: dev|ci|prod]'
---

# Secrets Management

## When to Use

- When designing how credentials are stored and accessed
- When setting up secret injection for CI/CD or containers
- When establishing rotation schedules
- When responding to a leaked secret

## Principles

1. **Zero Secrets in Code** — No secret appears in source files,
   committed config, or CI pipeline definitions.
2. **Least Privilege Access** — Each service gets only the secrets it
   needs, with minimum permissions.
3. **Rotation** — All secrets must be rotatable without downtime.
4. **Safety & Security** — Hardcoded secrets are a critical violation.

## Techniques & Patterns

### Secret Storage Hierarchy

| Level | Storage | Use Case |
|-------|---------|----------|
| 1 (best) | **Managed service** (Vault, AWS/GCP/Azure Secret Manager) | Production |
| 2 | **Platform secrets** (GitHub Secrets, GitLab CI Variables) | CI/CD |
| 3 | **Environment variables** (not committed) | Local dev |
| 4 | **Encrypted config** (SOPS, age) | Version-controlled secrets |
| 5 (worst) | **Plaintext in code** | Never acceptable |

### Managed Secrets Services

| Service | Key Features |
|---------|-------------|
| **HashiCorp Vault** | Dynamic secrets, leasing, PKI, multi-cloud |
| **AWS Secrets Manager** | Auto-rotation, RDS integration |
| **GCP Secret Manager** | IAM integration, versioning |
| **Azure Key Vault** | HSM-backed, certificate management |

### Secret Injection Patterns

**Runtime injection (recommended):**
```yaml
# Kubernetes
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: app-secrets
        key: database-url
```

**Encrypted config (SOPS + age):**
```bash
sops --encrypt --age age1... config.yaml > config.enc.yaml
sops --decrypt config.enc.yaml | app --config -
```

### Secret Rotation

| Secret Type | Frequency | Automation |
|-------------|-----------|------------|
| API keys | 90 days | Key pair swap |
| Database passwords | 90 days | Dynamic creds (Vault) |
| TLS certificates | Before expiry | Let's Encrypt + cert-manager |
| Service tokens | 24–72 hours | Short-lived (Vault, OIDC) |

**Zero-downtime pattern:**
1. Generate new secret (v2) alongside v1.
2. Update consumers to accept both.
3. Switch primary to v2.
4. Verify all consumers use v2.
5. Revoke v1.

### Secret Detection

| Layer | Tool | When |
|-------|------|------|
| Pre-commit | Gitleaks, detect-secrets | Before commit |
| CI | Gitleaks, TruffleHog | Every PR/push |
| Repository | GitHub Secret Scanning | Continuous |

### Emergency: Secret Leaked

```
1. IMMEDIATELY rotate/revoke the compromised secret.
2. Audit access logs.
3. Assess blast radius.
4. Update all systems with new secret.
5. Post-incident review: how did it leak?
```

### Development Secrets

- `.env` file (gitignored) for local development.
- `.env.example` (committed) with placeholder values.
- Local vault or Doppler/1Password CLI for team sync.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Zero hardcoded secrets** | 0 | Pre-commit + CI scanning |
| **Managed store for prod** | 100% | No env vars for production |
| **Rotation schedule** | All < 90 days old | Track and alert |
| **Leaked secret response** | < 1 hour to rotate | Detection to revocation |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Secrets in git** | Even "private" repos get breached. | Scanning + managed service. |
| **Shared credentials** | Entire team uses one password. | Per-service, per-environment. |
| **No rotation** | Unlimited compromise window. | Automated rotation. |
| **Secrets in logs** | `password={password}` in log output. | Redact. Structured logging. |
| **Removing but not rotating** | Git history is forever. | Always rotate after detection. |

## References

- HashiCorp Vault: https://www.vaultproject.io/
- Gitleaks: https://github.com/gitleaks/gitleaks
- SOPS: https://github.com/getsops/sops
- OWASP Secrets Management Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html
