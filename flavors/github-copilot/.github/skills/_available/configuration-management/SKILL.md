---
name: configuration-management
description: Govern how applications discover and consume runtime settings — environment variables, config hierarchies, feature flags, 12-factor methodology, and startup validation.
argument-hint: '[config concern] [environment: dev|staging|prod]'
activation:
  signals:
    python_packages: [python-dotenv, pydantic-settings, dynaconf]
    js_packages: [dotenv, config, convict]
  agents: [implementer, code-critic]
  priority: recommended
---

# Configuration Management

## When to Use

- When designing deployment configurations for multiple environments
- When separating config from code (12-factor)
- When implementing feature flags
- When establishing config validation at startup

## Principles

1. **Separation of Concern** — Configuration must be separated from code.
   The same artifact runs in any environment by changing only config.
2. **Transparency** — All configuration sources and their precedence must
   be documented. "Where does this value come from?" is always answerable.
3. **Config ≠ Secrets** — Secrets require encryption, rotation, access
   control. See the secrets-management skill.
4. **Fail-Safe** — Missing required configuration must cause a fast, clear
   startup failure — never a silent default hiding misconfiguration.

## Techniques & Patterns

### Configuration Hierarchy (Precedence)

```
1. Command-line arguments       (highest priority)
2. Environment variables
3. Local config file            (.env, config.local.yaml)
4. Environment config file      (config.production.yaml)
5. Default config file          (config.defaults.yaml)
6. Code defaults                (lowest priority)
```

### Configuration Formats

| Format | Strengths | Use Case |
|--------|-----------|----------|
| **Env vars** | Universal, 12-factor, container-native | Deployed services |
| **YAML** | Readable, nested, comments | App config files |
| **TOML** | Clean syntax, typed | Python/Rust projects |
| **dotenv (.env)** | Simple key-value | Local dev (never commit) |

### The 12-Factor Approach

1. Config that varies between environments → env vars.
2. Config that is the same across environments → code constants.
3. Never commit env-specific config to the repo.
4. Config is not code — injectable without rebuilding.

### Config vs. Secrets

| Aspect | Configuration | Secret |
|--------|--------------|--------|
| Sensitivity | Non-sensitive | Sensitive |
| Examples | Port, log level, feature flags | API keys, passwords |
| Storage | Config files, env vars | Vault, managed service |
| Visibility | Readable in dashboards | Never logged, always masked |

### Feature Flags

| Type | Lifespan | Use Case |
|------|----------|----------|
| **Release flag** | Temporary | Dark launch. Remove after rollout. |
| **Experiment flag** | Temporary | A/B testing. Remove after experiment. |
| **Ops flag** | Semi-permanent | Kill switch, maintenance mode. |
| **Permission flag** | Permanent | Feature gating by tier/plan. |

**Tools:** LaunchDarkly, Unleash (open-source), Flagsmith, ConfigCat.

**Hygiene:** Every flag has an owner and expiration. Temporary flags
removed within 2 sprints. Monthly cleanup review.

### Validation at Startup

```python
import os, sys

REQUIRED = ["DATABASE_URL", "REDIS_URL", "LOG_LEVEL"]

def validate_config():
    missing = [v for v in REQUIRED if not os.getenv(v)]
    if missing:
        print(f"FATAL: Missing config: {', '.join(missing)}")
        sys.exit(1)

validate_config()
```

**Rules:**
- Validate ALL required config at startup, not at first use.
- Report ALL missing values at once.
- Validate types and ranges (port: 1–65535).
- Log config source but mask secrets.

### Language-Specific Libraries

| Language | Library | Notes |
|----------|---------|-------|
| Python | `pydantic-settings`, `python-dotenv` | Typed, validated |
| Node.js | `dotenv`, `convict` | `convict` adds schema validation |
| Go | `viper`, `envconfig` | Multi-format + remote config |
| Rust | `config-rs`, `dotenvy` | Layered, typed deserialization |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **No secrets in config** | Zero | Handled via secrets-management skill |
| **Startup validation** | All required vars checked | Fast fail on missing |
| **Config documented** | Every variable | Name, type, default, required, description |
| **.env in .gitignore** | Always | Local config never committed |
| **Feature flag inventory** | Monthly review | Owner, expiration, removal plan |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Config in code** | `if env == "production"` in business logic. | External config, injected at runtime. |
| **Catch-all defaults** | Missing prod config silently uses dev values. | Required vars must not have defaults. Fail fast. |
| **Config sprawl** | Values from env vars, YAML, JSON, DB with undocumented precedence. | Document hierarchy. Single config library. |
| **Immortal feature flags** | Flag from 2022, still in code in 2026. | Expiration dates. Monthly cleanup. |
| **Secrets as config** | `PASSWORD=hunter2` in committed `.env`. | Use secret manager. Never commit. |
| **Late validation** | Config checked only on first use. | Validate at startup. |

## References

- 12-Factor App — Config: https://12factor.net/config
- pydantic-settings: https://docs.pydantic.dev/latest/concepts/pydantic_settings/
- Unleash: https://www.getunleash.io/
