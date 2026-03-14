---
name: ci-cd
description: Automate building, testing, and deploying software — pipeline stages, platform comparison, deployment strategies, caching, and quality gates.
argument-hint: '[platform: github-actions|gitlab|azure-devops] [focus: pipeline|deploy|optimize]'
---

# CI/CD

## When to Use

- When setting up build, test, and deployment pipelines
- When optimizing pipeline duration or reliability
- When choosing deployment strategies (rolling, blue-green, canary)
- When establishing quality gates enforced by automation

## Principles

1. **Every Commit Is Validated** — No code merges without automated build,
   lint, and test. Programmatic enforcement of quality gates.
2. **Deployment Is Boring** — A good pipeline makes deployment routine.
   Reduce human steps to zero.
3. **Fail Fast** — Catch issues early. Lint before test, unit before
   integration.
4. **Verifiability** — Pipeline results are deterministic, logged, and
   auditable.

## Techniques & Patterns

### Pipeline Stages

```
Commit → Build → Lint → Unit Test → Integration Test → Security Scan
       → Artifact Build → Deploy Staging → E2E Test → Deploy Production
```

| Stage | Duration Target |
|-------|-----------------|
| Build | < 2 min |
| Lint / Format | < 1 min |
| Unit Tests | < 2 min |
| Integration Tests | < 5 min |
| Security Scan | < 3 min |
| Deploy + E2E | < 15 min |

**Total target: < 30 minutes commit to production.**

### Platform Comparison

| Platform | Best For |
|----------|----------|
| **GitHub Actions** | GitHub-hosted, marketplace actions, matrix builds |
| **GitLab CI** | Self-hosted, built-in registry, review apps |
| **Jenkins** | Enterprise, maximum flexibility |
| **Azure DevOps** | Microsoft ecosystem |

### GitHub Actions Example

```yaml
name: CI/CD
on:
  push: { branches: [main] }
  pull_request: { branches: [main] }

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npm run lint
      - run: npm run test -- --coverage
      - run: npm run build

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aquasecurity/trivy-action@master
        with: { scan-type: fs, severity: CRITICAL,HIGH }

  deploy:
    needs: [lint-and-test, security]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build
```

### Deployment Strategies

| Strategy | Rollback Speed | Risk |
|----------|---------------|------|
| **Rolling** | Medium | One bad instance serves traffic briefly |
| **Blue-Green** | Instant | Requires 2x infrastructure |
| **Canary** | Fast | Requires traffic splitting, monitoring |
| **Feature Flags** | Instant | Flag management complexity |

### Pipeline Best Practices

- **Cache dependencies** between runs (1–3 min savings).
- **Parallelize** lint, test, and security.
- **Matrix builds** across OS/version combinations.
- **Reusable workflows** for shared pipeline logic.
- **Environment protection** for production.
- **Notifications** on failure only (success = noise).
- **OIDC** for cloud provider auth (no static credentials).

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Pipeline passes on every PR** | 100% | No merge without green. |
| **Build reproducibility** | Deterministic | Lockfiles, pinned images. |
| **Pipeline duration** | < 15 min (PR), < 30 min (deploy) | Optimize for feedback speed. |
| **No manual steps** | 0 (except prod approval) | Everything automated. |
| **Rollback tested** | Yes | Validated monthly. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **CI only, no CD** | Tested but deployed manually. | Automate deployment. |
| **Slow pipelines** | 45-min waits kill productivity. | Parallelize, cache, split fast/full. |
| **Flaky pipeline** | Random failures → "re-run and pray." | Fix flaky tests. Flakiness is P1. |
| **Snowflake environments** | Staging ≠ production. | IaC. Identical configs. |
| **No rollback plan** | Deploy fails → panic. | Define and test rollback. |

## References

- GitHub Actions: https://docs.github.com/en/actions
- Martin Fowler, ["Continuous Integration"](https://martinfowler.com/articles/continuousIntegration.html)
- Jez Humble & David Farley, *Continuous Delivery* (2010)
