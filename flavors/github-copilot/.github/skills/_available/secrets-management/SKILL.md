---
name: secrets-management
description: Store, access, rotate, and protect sensitive credentials — managed services, injection patterns, rotation strategies, detection, and emergency response.
argument-hint: '[secret type or concern] [environment: dev|ci|prod]'
activation:
  signals:
    python_packages: [fastapi, flask, django, python-dotenv, boto3, azure-identity]
    js_packages: [dotenv, @aws-sdk/client-secrets-manager]
  agents: [implementer, code-critic]
  priority: recommended
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

### Databricks Secret Scopes

Databricks has a built-in secrets service accessed via `dbutils.secrets`.

**Creating and managing scopes (CLI):**
```bash
# Create a scope (backed by Databricks or Azure Key Vault)
databricks secrets create-scope my-scope

# Store a secret
databricks secrets put-secret my-scope api-key --string-value "..."

# List scopes
databricks secrets list-scopes

# List secrets in a scope (values are redacted)
databricks secrets list-secrets my-scope
```

**Accessing secrets in notebooks/jobs:**
```python
# Read a secret value (returns string)
token = dbutils.secrets.get(scope="my-scope", key="api-key")

# List available keys (not values)
dbutils.secrets.list("my-scope")
```

**Accessing secrets via Python SDK:**
```python
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()
for scope in w.secrets.list_scopes():
    print(scope.name)
```

**Key rules for Databricks secrets:**
- Secret values are **redacted** in notebook output (`[REDACTED]`)
- ACLs control which users/groups can READ or MANAGE each scope
- Azure-backed scopes delegate to Azure Key Vault
- Databricks-backed scopes store secrets internally
- Secret scopes are workspace-scoped, not catalog-scoped

**ACL management:**
```bash
# Grant READ access to a group
databricks secrets put-acl my-scope data-engineers READ

# Grant MANAGE access
databricks secrets put-acl my-scope admins MANAGE
```

### Databricks `.databrickscfg` Profiles

The `~/.databrickscfg` file stores workspace connection profiles.
**This is NOT a secret store** — it's auth configuration:

```ini
[DEFAULT]
host = https://adb-xxx.azuredatabricks.net
auth_type = databricks-cli

[PROD]
host = https://adb-yyy.azuredatabricks.net
token = dapi...
```

**Security rules:**
- Never commit `.databrickscfg` to git
- Prefer `auth_type = databricks-cli` over plaintext tokens
- Use Azure AD / OAuth for production (no long-lived tokens)
- Rotate `dapi` tokens every 90 days

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
