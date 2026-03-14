---
category: devops
applies_to: [all]
complexity: foundational
maturity: reviewed
version: "1.0"
last_reviewed: 2026-02-26
related: [ci_cd, containerization, secrets_management, monitoring_observability]
---
# Configuration Management

## Purpose

Configuration management governs how applications discover and consume their runtime settings across environments. This skill covers environment variables, config hierarchies, feature flags, config vs secrets, and the 12-factor methodology. Invoke this skill when designing deployment configurations, defining Level-3 config workflows, or establishing Level-4 environment standards.

## Principles

- **Separation of Concern (AAIG L1):** Configuration must be separated from code. The same artifact (binary, container) must run in any environment by changing only the configuration.
- **Transparency (AAIG L1):** All configuration sources and their precedence must be documented. "Where does this value come from?" must always be answerable.
- **Safety & Security (AAIG L1):** Secrets are NOT configuration. They require different handling (encryption, rotation, access control). See Secrets Management skill.
- **Fail-Safe (AAIG L1):** Missing required configuration must cause a fast, clear startup failure -- never a silent default that hides a misconfiguration.

## Techniques & Patterns

### Configuration Hierarchy (Precedence)

```
Priority (highest to lowest):
  1. Command-line arguments    (--port=8080)
  2. Environment variables     (PORT=8080)
  3. Local config file         (.env, config.local.yaml)
  4. Environment config file   (config.production.yaml)
  5. Default config file       (config.defaults.yaml)
  6. Code defaults             (const DEFAULT_PORT = 3000)
```

Higher-priority sources override lower-priority ones. Document this hierarchy explicitly in the project README.

### Configuration Formats

| Format | Strengths | Use Case |
|--------|-----------|----------|
| **Environment variables** | Universal, 12-factor, container-native | Primary config mechanism for deployed services |
| **YAML** | Human-readable, nested, comments | Application config files |
| **JSON** | Universal, schema-validatable | API config, structured data |
| **TOML** | Clean syntax, typed | Rust/Python projects (Cargo.toml, pyproject.toml) |
| **dotenv (.env)** | Simple key-value, local development | Local overrides. Never commit to git. |

### The 12-Factor Config Approach

From the 12-Factor App methodology:

> "Store config in the environment."

**Rules:**
1. Config that varies between environments (dev, staging, prod) goes in env vars.
2. Config that is the same across environments goes in code (constants).
3. Never commit env-specific config to the repository.
4. Config is not code -- it should be injectable without rebuilding.

### Config vs Secrets

| Aspect | Configuration | Secret |
|--------|--------------|--------|
| **Sensitivity** | Non-sensitive | Sensitive |
| **Examples** | Port, log level, feature flags | API keys, passwords, certificates |
| **Storage** | Config files, env vars | Vault, managed secret service |
| **Rotation** | On deployment | Regular schedule + on compromise |
| **Visibility** | readable in logs/dashboards | Never logged, masked |
| **Skill** | This skill | Secrets Management |

### Feature Flags

| Type | Lifespan | Use Case |
|------|----------|----------|
| **Release flag** | Temporary | Dark launch. Remove after rollout complete. |
| **Experiment flag** | Temporary | A/B testing. Remove after experiment concludes. |
| **Ops flag** | Semi-permanent | Kill switch, maintenance mode |
| **Permission flag** | Permanent | Feature gating by plan/tier |

**Tools:**
| Tool | Type | Notes |
|------|------|-------|
| **LaunchDarkly** | SaaS | Enterprise, real-time, targeting |
| **Unleash** | Open-source | Self-hosted, simple, free |
| **Flagsmith** | Open-source + SaaS | Feature flags + remote config |
| **ConfigCat** | SaaS | Simple, developer-friendly |
| **Environment variables** | Basic | For simple on/off flags only |

**Flag hygiene:**
- Every flag has an owner and an expiration date.
- Temporary flags are removed within 2 sprints of full rollout.
- Flag inventory reviewed monthly.
- Dead flags (never evaluated) are deleted.

### Validation at Startup

```python
# Fail fast on missing config
import os, sys

REQUIRED = ["DATABASE_URL", "REDIS_URL", "API_KEY_NAME"]

def validate_config():
    missing = [var for var in REQUIRED if not os.getenv(var)]
    if missing:
        print(f"FATAL: Missing required config: {', '.join(missing)}")
        sys.exit(1)

validate_config()  # Call before app starts
```

**Rules:**
- Validate ALL required configuration at startup, not at first use.
- Report ALL missing values at once, not one at a time.
- Validate types and ranges (e.g., port must be 1-65535).
- Log the configuration source (but mask secrets).

### Per-Environment Config Pattern

```
config/
  defaults.yaml       # base defaults
  development.yaml    # local overrides
  staging.yaml        # staging overrides
  production.yaml     # production overrides (minimal)
```

**Merging:** Load defaults, then overlay the environment-specific file. Environment variables override both.

### Language-Specific Libraries

| Language | Library | Notes |
|----------|---------|-------|
| **Python** | `pydantic-settings`, `python-dotenv` | Typed, validated, env + file + secrets |
| **Node.js** | `dotenv`, `convict`, `config` | `convict` adds schema validation |
| **Java** | Spring Config, `owner` | Spring profiles, Kubernetes ConfigMaps |
| **Go** | `viper`, `envconfig` | `viper` supports multiple formats + remote config |
| **Rust** | `config-rs`, `dotenvy` | Layered config, typed deserialization |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **No secrets in config** | Zero | Secrets handled via Secrets Management skill |
| **Startup validation** | All required vars checked | Fast fail on missing config |
| **Config documented** | README or config schema | Every variable: name, type, default, required, description |
| **No hardcoded env-specific values** | Zero in code | URLs, ports, hostnames only in config |
| **.env in .gitignore** | Always | Local config never committed |
| **Feature flag inventory** | Monthly review | Owner, expiration, removal plan |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Config in code** | `if env == "production"` scattered through business logic. | External config, injected at runtime. |
| **Catch-all defaults** | Every config has a "safe" default. Missing production config silently uses dev values. | Required vars must not have defaults. Fail fast. |
| **Config sprawl** | Config values defined in env vars, YAML, JSON, database, and command-line args with undocumented precedence. | Document the hierarchy. Use a single config library. |
| **Immortal feature flags** | Flag added in 2022, still in code in 2026. Nobody knows if it's safe to remove. | Expiration dates. Monthly cleanup. Automated dead-flag detection. |
| **Secrets as config** | `DATABASE_PASSWORD=hunter2` in a committed `.env` file. | Use a secret manager. Never commit secrets. See Secrets Management. |
| **Late validation** | Config validated only when first used (e.g., database URL checked on first query). | Validate at startup. Fail before serving traffic. |

## See Also

- [CI/CD](../devops/ci_cd.md)
- [Containerization](../devops/containerization.md)
- [Secrets Management](../security/secrets_management.md)
- [Monitoring & Observability](../devops/monitoring_observability.md)

## References

- 12-Factor App -- Config: https://12factor.net/config
- pydantic-settings: https://docs.pydantic.dev/latest/concepts/pydantic_settings/
- LaunchDarkly: https://launchdarkly.com/
- Unleash: https://www.getunleash.io/
