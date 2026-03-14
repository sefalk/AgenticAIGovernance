---
category: code_quality
applies_to: [all]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [ci_cd, containerization, security_testing, secrets_management, secure_coding, code_review]
---
# Dependency Management

## Purpose

Dependency management ensures that external libraries and frameworks are selected wisely, pinned precisely, kept up to date, and free of known vulnerabilities. Poor dependency management is one of the top sources of security incidents and build failures. Invoke this skill when establishing project setup conventions, defining Level-3 supply chain security workflows, or selecting tools at Level 4.

## Principles

- **Safety & Security (AAIG L1):** All dependencies must be from known, reputable sources. No execution of untrusted external code without user approval.
- **Verifiability (AAIG L1):** Dependency versions must be deterministic (lockfiles). Builds must be reproducible.
- **Efficiency (AAIG L1):** Minimize dependencies. Every dependency is a liability (security surface, maintenance burden, transitive risk).

## Techniques & Patterns

### Lockfiles

Lockfiles pin the exact version (including transitive dependencies) for deterministic builds.

| Language | Package Manager | Lockfile |
|----------|----------------|----------|
| JavaScript/TS | npm | `package-lock.json` |
| JavaScript/TS | yarn | `yarn.lock` |
| JavaScript/TS | pnpm | `pnpm-lock.yaml` |
| Python | pip | `requirements.txt` (pinned) or `pip.lock` |
| Python | Poetry | `poetry.lock` |
| Python | uv | `uv.lock` |
| Java/Kotlin | Gradle | `gradle.lockfile` (opt-in) |
| Java/Kotlin | Maven | `pom.xml` with exact versions |
| Go | go mod | `go.sum` |
| Rust | Cargo | `Cargo.lock` |
| C#/.NET | NuGet | `packages.lock.json` (opt-in) |

**Rules:**
- Always commit lockfiles to version control.
- Install from lockfile in CI: `npm ci` (not `npm install`), `pip install -r requirements.txt --no-deps`, `cargo build --locked`.
- Never manually edit lockfiles.

### Version Pinning Strategy

| Strategy | Syntax (npm) | Risk | When to Use |
|----------|-------------|------|-------------|
| **Exact** | `1.2.3` | Lowest | Production dependencies, critical libraries |
| **Patch range** | `~1.2.3` (>=1.2.3, <1.3.0) | Low | Libraries with good semver discipline |
| **Minor range** | `^1.2.3` (>=1.2.3, <2.0.0) | Medium | Development dependencies |
| **Any** | `*` | Highest | Never use in production |

**Recommendation:** Use exact pinning for production dependencies, patch ranges for dev dependencies. Let automated update tools (Dependabot, Renovate) handle version bumps via PRs.

### Automated Updates

| Tool | Features |
|------|----------|
| **Dependabot** (GitHub) | Auto-PR for dependency updates, security alerts, grouped updates |
| **Renovate** | Highly configurable, auto-merge for patch updates, monorepo support |
| **Snyk** | Vulnerability-focused updates with fix PRs |

**Recommended workflow:**
1. Enable automated update PRs (Dependabot or Renovate).
2. Auto-merge patch updates for dependencies with high test coverage.
3. Manually review minor/major updates.
4. Run full test suite on every update PR.
5. Schedule update reviews weekly (avoid update fatigue).

### Dependency Selection Criteria

Before adding a dependency, evaluate:

| Criterion | Check |
|-----------|-------|
| **Necessity** | Can this be done with the standard library or in < 50 lines? |
| **Maintenance** | Is it actively maintained? When was the last release? |
| **Community** | GitHub stars, download count, number of contributors |
| **Security** | Any open CVEs? How quickly are vulnerabilities patched? |
| **License** | Compatible with your project's license? (MIT, Apache = generally safe; GPL = copyleft risk) |
| **Transitive deps** | How many dependencies does it pull in? (Fewer is better.) |
| **Size** | Is the package size reasonable for the functionality? (Avoid pulling 50MB for one utility.) |
| **API stability** | Frequent breaking changes? Follows semver? |

**Rule of thumb:** If a library does less than what you could reasonably implement and maintain yourself, don't add the dependency.

### Vulnerability Scanning

See `security_testing.md` for comprehensive guidance. Key tools for dependency scanning:

| Tool | Ecosystem |
|------|-----------|
| **Trivy** | Multi-language, containers, IaC |
| **npm audit** | JavaScript/TypeScript |
| **pip-audit** | Python |
| **cargo-audit** | Rust |
| **OWASP Dependency-Check** | Java/.NET |
| **govulncheck** | Go |

**CI integration:** Run on every build. Block merge on critical/high CVEs.

### License Compliance

| Tool | Purpose |
|------|---------|
| **license-checker** (npm) | List all dependency licenses |
| **pip-licenses** | Python license report |
| **FOSSA** | Enterprise license compliance |
| **ScanCode** | Open-source license detector |

**Rules:**
- Maintain an allowed-license list (e.g., MIT, Apache-2.0, BSD, ISC).
- Block dependencies with copyleft licenses (GPL, AGPL) unless the project is itself copyleft.
- Flag unknown or multi-licensed dependencies for manual review.

### Monorepo Considerations

In monorepos, dependencies must be managed consistently:
- Use workspace-level lockfiles (`npm workspaces`, `yarn workspaces`, `pnpm workspaces`).
- Enforce consistent versions across packages (no package A using React 17 while package B uses React 18).
- Tools: `syncpack` (npm), `manypkg` for checking version consistency.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Lockfile committed** | Yes | Must be in version control and up to date. |
| **Zero critical CVEs** | 0 | Block merge. High CVEs deferred with ticket and SLA. |
| **License compliance** | All approved | No unapproved licenses in production dependencies. |
| **Deterministic install** | Verified | CI uses lockfile install (`npm ci`, `--locked`, etc.). |
| **No unused dependencies** | 0 | Detected via `depcheck` (npm), `deptry` (Python), etc. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **No lockfile** | Builds are non-reproducible. "Works on my machine." | Always commit lockfiles. Install from lockfile in CI. |
| **Dependency sprawl** | Hundreds of dependencies for a simple project. | Audit and prune. Prefer standard library. |
| **Ignoring updates** | Dependencies 3+ years out of date. Accumulating CVEs. | Enable automated updates. Schedule weekly review. |
| **Manual lockfile edits** | Corrupted lockfiles, mysterious build failures. | Never edit manually. Run package manager commands. |
| **Pinning nothing** | Using `*` or `latest`. Builds break unpredictably. | Pin exact versions or tight ranges. |


## See Also

- [Security Testing](../testing/security_testing.md)
- [Secrets Management](../security/secrets_management.md)
- [CI/CD](../devops/ci_cd.md)

## References

- Dependabot: https://docs.github.com/en/code-security/dependabot
- Renovate: https://docs.renovatebot.com/
- Trivy: https://aquasecurity.github.io/trivy/
- OWASP Dependency-Check: https://owasp.org/www-project-dependency-check/
