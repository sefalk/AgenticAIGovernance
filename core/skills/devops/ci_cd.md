---
category: devops
applies_to: [all]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [containerization, monitoring_observability, infrastructure_as_code, dependency_management, ml_pipeline_design, configuration_management, secrets_management, embedded_systems, mobile_development]
---
# CI/CD

## Purpose

Continuous Integration (CI) and Continuous Delivery/Deployment (CD) automate the process of building, testing, and deploying software. CI ensures every code change is validated automatically; CD ensures validated code can reach production safely and rapidly. Invoke this skill when setting up pipelines, defining Level-3 deployment workflows, or configuring Level-4 project tooling.

## Principles

- **Every commit is validated:** No code merges without automated build, lint, and test. This is the programmatic enforcement of quality gates (AAIG L1).
- **Deployment is boring:** A good pipeline makes deployment routine, not heroic. Reduce human steps to zero.
- **Fail fast:** The pipeline should catch issues as early as possible. Lint before test, unit test before integration test.
- **Verifiability (AAIG L1):** Pipeline results are deterministic, logged, and auditable.

## Techniques & Patterns

### Pipeline Stages

```
Commit --> Build --> Lint/Format --> Unit Test --> Integration Test --> Security Scan
       --> Artifact Build --> Deploy to Staging --> E2E Test --> Deploy to Production
```

| Stage | Purpose | Duration Target |
|-------|---------|-----------------|
| **Build** | Compile, resolve dependencies | < 2 min |
| **Lint / Format** | Code style and static analysis | < 1 min |
| **Unit Tests** | Fast, isolated tests | < 2 min |
| **Integration Tests** | Test with real dependencies | < 5 min |
| **Security Scan** | SAST, dependency audit, secrets | < 3 min |
| **Artifact Build** | Docker image, binary, package | < 5 min |
| **Deploy Staging** | Deploy to pre-production | < 5 min |
| **E2E Tests** | Full-stack validation | < 10 min |
| **Deploy Production** | Production release | < 5 min |

**Total target: < 30 minutes from commit to production.**

### Platform Comparison

| Platform | Best For | Key Features |
|----------|----------|-------------|
| **GitHub Actions** | GitHub-hosted projects | Marketplace actions, matrix builds, reusable workflows |
| **GitLab CI** | GitLab-hosted, self-hosted | Built-in container registry, environments, review apps |
| **Jenkins** | Enterprise, complex pipelines | Maximum flexibility, plugin ecosystem |
| **CircleCI** | Fast builds, Docker-native | Orbs (reusable configs), powerful caching |
| **Azure DevOps** | Microsoft ecosystem | Tight Azure integration, multi-stage pipelines |

### GitHub Actions Example

```yaml
name: CI/CD
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

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
      # Deploy steps here
```

### Branching and Deployment Strategies

| Strategy | Description | When to Use |
|----------|-------------|-------------|
| **Trunk-based** | Everyone commits to main. Short-lived feature branches (< 1 day). | Small teams, high CI maturity |
| **GitHub Flow** | Feature branches merged via PR. Deploy from main. | Most teams (recommended default) |
| **GitFlow** | develop, release, hotfix branches. Formal releases. | Packaged software with versioned releases |

### Deployment Strategies

| Strategy | Description | Rollback Speed | Risk |
|----------|-------------|---------------|------|
| **Rolling** | Replace instances gradually | Medium | One bad instance serves traffic briefly |
| **Blue-Green** | Switch traffic between two identical environments | Instant | Requires 2x infrastructure |
| **Canary** | Route small % of traffic to new version first | Fast | Requires traffic splitting, monitoring |
| **Feature Flags** | Deploy code but toggle features on/off | Instant | Flag management complexity |

### Pipeline Best Practices

- **Cache dependencies:** Cache `node_modules`, `.m2`, pip cache between runs. Saves 1-3 minutes per build.
- **Parallelize:** Run lint, test, and security in parallel, not sequentially.
- **Matrix builds:** Test across multiple OS/language/version combinations.
- **Reusable workflows:** Extract common pipeline logic into shared workflows/templates.
- **Environment protection:** Require approval for production deployments. Use environment secrets.
- **Artifact retention:** Store build artifacts, test reports, coverage reports. Set retention policy (30 days default).
- **Notifications:** Alert on failures (Slack, email, Teams). Don't notify on success (noise).

### Secrets Management in CI

- **Never hardcode secrets** in pipeline files.
- Use platform-native secrets: GitHub Secrets, GitLab CI Variables (masked), Jenkins Credentials.
- Rotate secrets regularly. Audit access.
- Use OIDC for cloud provider authentication (no static credentials).

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Pipeline passes on every PR** | 100% | No merge without green pipeline. |
| **Build reproducibility** | Deterministic | Same commit produces same artifact. Use lockfiles, pinned base images. |
| **Pipeline duration** | < 15 min (PR), < 30 min (deploy) | Optimize for developer feedback speed. |
| **No manual steps** | 0 (except production approval) | Everything automated except deliberate human gates. |
| **Rollback tested** | Yes | Rollback procedure validated at least monthly. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **CI only, no CD** | Code is tested but still deployed manually. | Automate deployment. Even if manual approval is required, the deployment itself should be scripted. |
| **Slow pipelines** | 45-minute pipelines kill developer productivity. | Parallelize, cache, split into fast (PR) and full (merge) pipelines. |
| **Flaky pipeline** | Pipeline fails randomly. Developers re-run and pray. | Fix flaky tests and unstable infra. Flakiness is a P1 bug. |
| **Snowflake environments** | Staging doesn't match production. "Works in staging." | Infrastructure as Code. Identical configs for all environments. |
| **No rollback plan** | If deploy fails, panic. | Define and test rollback for every deployment strategy. |


## See Also

- [Containerization](../devops/containerization.md)
- [Monitoring and Observability](../devops/monitoring_observability.md)
- [Infrastructure as Code](../devops/infrastructure_as_code.md)

## References

- GitHub Actions documentation: https://docs.github.com/en/actions
- GitLab CI documentation: https://docs.gitlab.com/ee/ci/
- Martin Fowler, ["Continuous Integration"](https://martinfowler.com/articles/continuousIntegration.html)
- Jez Humble & David Farley, *Continuous Delivery* (2010) -- the canonical reference.
