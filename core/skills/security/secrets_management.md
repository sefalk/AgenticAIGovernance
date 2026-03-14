---
category: security
applies_to: [all, cloud]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [secure_coding, threat_modeling, security_testing, ci_cd, authentication_authorization, configuration_management, dependency_management, compliance_regulatory]
---
# Secrets Management

## Purpose

Secrets management ensures that sensitive credentials (API keys, database passwords, encryption keys, tokens, certificates) are stored securely, accessed safely, rotated regularly, and never exposed in source code or logs. Invoke this skill when designing credential handling, configuring secret storage, or defining Level-3 secrets workflows.

## Principles

- **Zero secrets in code:** No secret appears in source files, configuration files committed to git, or CI pipeline definitions.
- **Least privilege access:** Each service gets only the secrets it needs, with minimum required permissions.
- **Rotation:** All secrets must be rotatable without downtime.
- **Safety & Security (AAIG L1):** All code must adhere to highest safety and security standards. Hardcoded secrets are a critical violation.

## Techniques & Patterns

### Secret Storage Hierarchy

| Level | Storage | Security | Use Case |
|-------|---------|----------|----------|
| 1 (best) | **Managed secrets service** (Vault, AWS Secrets Manager, GCP Secret Manager) | Encrypted, audited, auto-rotated | Production secrets |
| 2 | **Platform secrets** (GitHub Secrets, GitLab CI Variables) | Encrypted at rest, masked in logs | CI/CD pipeline secrets |
| 3 | **Environment variables** (not committed) | In-memory only | Local development |
| 4 | **Encrypted config files** (SOPS, age) | Encrypted in git | Teams needing version-controlled secrets |
| 5 (worst) | **Plaintext in code/config** | None | Never acceptable |

### Managed Secrets Services

| Service | Type | Key Features |
|---------|------|-------------|
| **HashiCorp Vault** | Self-hosted / HCP | Dynamic secrets, leasing, PKI, multi-cloud |
| **AWS Secrets Manager** | AWS-managed | Auto-rotation, RDS integration, cross-account sharing |
| **GCP Secret Manager** | GCP-managed | IAM integration, versioning, auto-replication |
| **Azure Key Vault** | Azure-managed | HSM-backed, certificate management, soft delete |
| **1Password / Doppler** | SaaS | Developer-friendly, team sharing, environment sync |

### Secret Injection Patterns

#### Runtime Injection (Recommended)
```yaml
# Kubernetes -- mount from secret store
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: app-secrets
        key: database-url

# Docker -- pass at runtime
docker run -e DATABASE_URL="$(vault kv get -field=url secret/db)" myapp
```

#### Cloud-Native Injection
```python
# Python -- AWS Secrets Manager
import boto3
import json

def get_secret(name):
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId=name)
    return json.loads(response['SecretString'])

db_config = get_secret('prod/database')
```

#### Encrypted Config (SOPS + age)
```bash
# Encrypt a config file (committed to git safely)
sops --encrypt --age age1... config.yaml > config.enc.yaml

# Decrypt at runtime
sops --decrypt config.enc.yaml | app --config -
```

### Secret Rotation

| Secret Type | Rotation Frequency | Automation |
|-------------|-------------------|------------|
| API keys | 90 days | Automated (key pair swap) |
| Database passwords | 90 days | Automated (Vault/Secrets Manager dynamic creds) |
| TLS certificates | Before expiry (auto-renew) | Let's Encrypt + certbot / cert-manager |
| SSH keys | Annually | Automated (Vault SSH backend) |
| Encryption keys | Annually | Key versioning (envelope encryption) |
| Service tokens | 24-72 hours | Dynamic short-lived tokens (Vault, OIDC) |

**Zero-downtime rotation pattern:**
```
1. Generate new secret (v2) alongside existing (v1).
2. Update consumers to accept both v1 and v2.
3. Switch primary secret to v2.
4. Verify all consumers use v2.
5. Revoke v1.
```

### Secret Detection

Prevent secrets from entering the codebase:

| Layer | Tool | When |
|-------|------|------|
| **Pre-commit hook** | Gitleaks, detect-secrets | Before commit (developer machine) |
| **CI pipeline** | Gitleaks, TruffleHog | On every PR/push |
| **Repository scanning** | GitHub Secret Scanning | Continuous |

**Pre-commit hook setup (Gitleaks):**
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

### Emergency Response: Secret Leaked

```
1. IMMEDIATELY rotate/revoke the compromised secret.
   (The secret is compromised regardless of "removing" it from code --
    it exists in git history.)
2. Audit access logs for the compromised secret.
3. Assess blast radius (what could the secret access?).
4. Update all systems with the new secret.
5. Post-incident review: how did it leak? Improve controls.
```

### Development Secrets

| Approach | Description |
|----------|-------------|
| **`.env` file (gitignored)** | Local development only. Never committed. |
| **`.env.example`** | Template with placeholder values. Committed to git. |
| **Local vault** | `docker run vault` for local development. |
| **Doppler / 1Password CLI** | Sync development secrets securely. |

```
# .env.example (committed -- shows required variables)
DATABASE_URL=postgres://user:password@localhost:5432/mydb
API_KEY=your-api-key-here

# .env (gitignored -- contains real values)
DATABASE_URL=postgres://dev:devpass@localhost:5432/devdb
API_KEY=sk-real-dev-key-123
```

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Zero hardcoded secrets** | 0 | Pre-commit + CI scanning. Block merge on detection. |
| **Secrets in managed store** | Production secrets: 100% | No env vars or config files for production secrets. |
| **Rotation schedule** | All secrets < 90 days old | Track and alert on aging secrets. |
| **Access audit** | Quarterly | Review who/what has access to each secret. |
| **Leaked secret response** | < 1 hour to rotate | Time from detection to revocation. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Secrets in git** | Secrets in source code, even in "private" repos. | Pre-commit scanning. Managed secrets service. |
| **Shared credentials** | Entire team uses one database password. | Per-service, per-environment credentials. |
| **No rotation** | Same API key for 3 years. If compromised, window is unlimited. | Automated rotation on schedule. |
| **Secrets in logs** | `logger.info(f"Connecting with password={password}")` | Redact sensitive values. Use structured logging. |
| **Removing but not rotating** | Deleting a secret from code but not revoking it. | Always rotate after detection. Git history is forever. |


## See Also

- [Secure Coding](../security/secure_coding.md)
- [Threat Modeling](../security/threat_modeling.md)
- [Security Testing](../testing/security_testing.md)
- [CI/CD](../devops/ci_cd.md)

## References

- HashiCorp Vault: https://www.vaultproject.io/
- AWS Secrets Manager: https://aws.amazon.com/secrets-manager/
- Gitleaks: https://github.com/gitleaks/gitleaks
- SOPS: https://github.com/getsops/sops
- OWASP Secrets Management Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html
