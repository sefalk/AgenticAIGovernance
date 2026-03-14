---
name: dependency-management
description: Dependency selection, version pinning, lockfiles, vulnerability scanning, and license compliance. Use when adding or auditing dependencies.
argument-hint: '[package name or "audit"] [action: add|remove|update|scan]'
disable-model-invocation: true
---

# Dependency Management Skill

Guidance for selecting, pinning, auditing, and maintaining project
dependencies.

## When to Use

- Adding a new dependency to the project
- Auditing existing dependencies for vulnerabilities
- Setting up lockfiles and version pinning
- Reviewing dependency changes in code review

## Principles

- **Minimise dependencies** — every dependency is a liability (security
  surface, maintenance burden, transitive risk)
- **Deterministic builds** — lockfiles ensure reproducibility
- **Known sources only** — all dependencies from reputable, maintained sources
- **No untrusted code** — no execution of unvetted external packages

## Dependency Selection Criteria

Before adding a dependency, evaluate:

| Criterion | Check |
|---|---|
| **Necessity** | Can this be done with stdlib or in < 50 lines? |
| **Maintenance** | Actively maintained? Last release date? |
| **Security** | Any open CVEs? How quickly are vulns patched? |
| **License** | Compatible? (MIT, Apache = safe; GPL = copyleft risk) |
| **Transitive deps** | How many dependencies does it pull in? |
| **Size** | Reasonable for the functionality? |
| **API stability** | Follows semver? Frequent breaking changes? |

**Rule:** If a library does less than what you could implement and maintain
yourself, don't add the dependency.

## Python Dependency Stack

| Tool | Purpose | Config |
|---|---|---|
| **pip** | Package installer | `requirements.txt` / `pyproject.toml` |
| **pip-compile** | Generate pinned requirements | `requirements.in` → `requirements.txt` |
| **uv** | Fast installer + resolver | `uv.lock` |
| **Poetry** | Full dependency management | `poetry.lock` |

### Version Pinning

```ini
# requirements.txt — production: exact pins
pyspark==3.5.1
numpy==1.26.4
pandas==2.2.1

# requirements-dev.txt — dev: allow patches
pytest~=8.0
hypothesis~=6.98
ruff~=0.3
```

| Strategy | Syntax | Risk | When |
|---|---|---|---|
| **Exact** | `==1.2.3` | Lowest | Production dependencies |
| **Compatible** | `~=1.2` | Low | Dev dependencies |
| **Range** | `>=1.2,<2.0` | Medium | Libraries you publish |

### Lockfiles

**Rules:**
- Always commit lockfiles to version control
- Install from lockfile in CI: `pip install -r requirements.txt --no-deps`
- Never manually edit lockfiles

## Vulnerability Scanning

```bash
# Python
pip-audit

# With specific requirements file
pip-audit -r requirements.txt

# Bandit for code-level security
bandit -r <package>/ -ll
```

| Tool | What It Checks |
|---|---|
| **pip-audit** | Known CVEs in installed packages |
| **safety** | Python dependency vulnerabilities |
| **Bandit** | Code-level security patterns |
| **Trivy** | Multi-ecosystem scanner |

**CI integration:** Run `pip-audit` on every build. Block merge on
critical/high CVEs.

## License Compliance

```bash
pip-licenses --format=table
```

**Rules:**
- Maintain an allowed-license list (MIT, Apache-2.0, BSD, ISC)
- Block copyleft licenses (GPL, AGPL) unless project is copyleft
- Flag unknown licenses for manual review

## ADR Requirement

If a new high-impact dependency is added (e.g., a new framework, database
driver, or security library), the code-critic verifies that a corresponding
ADR exists in `docs/adr/`.

## Quality Gates

| Gate | Threshold |
|---|---|
| Lockfile committed | Yes |
| Zero critical CVEs | 0 |
| License compliance | All approved |
| Deterministic install | CI uses lockfile |
| No unused deps | 0 (use `deptry` to detect) |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **No lockfile** | Non-reproducible builds | Always commit lockfiles |
| **Dependency sprawl** | Hundreds of deps for simple project | Audit and prune |
| **Ignoring updates** | 3+ year old deps, accumulating CVEs | Automated updates, weekly review |
| **Pinning nothing** | `*` or unpinned — builds break randomly | Pin exact for production |
| **Manual lockfile edits** | Corrupted lockfiles | Use package manager commands |

## Governance References

- **R-SD-11** — No execution of untrusted external code
- **R-SD-12** — Dependency audit for known vulnerabilities
