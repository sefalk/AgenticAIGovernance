---
name: security-testing
description: Identify vulnerabilities before attackers do — SAST, DAST, dependency scanning, secret detection, OWASP Top 10 coverage, and fuzzing.
argument-hint: '[project or component] [focus: sast|dast|deps|secrets|owasp|all]'
---

# Security Testing

## When to Use

- When the project processes user input or handles authentication
- When setting up CI security gates
- When evaluating dependency vulnerabilities
- When preparing for a security audit or compliance review

## Principles

1. **Defense in Depth** — No single test type is sufficient. Layer SAST,
   DAST, dependency scanning, and secret detection.
2. **Shift Left** — Integrate into CI, not just pre-deployment audits.
   Find vulnerabilities at the code level where they're cheapest to fix.
3. **Fail-Safe** — When a critical vulnerability is found, the pipeline
   must halt. No deployment until resolved.

## Techniques & Patterns

### SAST (Static Application Security Testing)

Analyzes source code without executing it.

| Language | Tools |
|----------|-------|
| Multi-language | Semgrep (recommended), SonarQube, CodeQL |
| Python | Bandit, Semgrep |
| JS/TS | `eslint-plugin-security`, Semgrep |
| Java/Kotlin | SpotBugs + Find Security Bugs |
| Go | gosec, Semgrep |
| Rust | `cargo-audit`, `cargo-clippy` |

### DAST (Dynamic Application Security Testing)

Tests the running application with malicious inputs.

| Tool | Type | Best For |
|------|------|----------|
| **OWASP ZAP** | Open-source | Web app scanning, CI automation |
| **Burp Suite** | Commercial | Deep manual + automated testing |
| **Nuclei** | Template-based | Fast, specific vulnerability checks |

### Dependency / SCA

| Tool | Ecosystem |
|------|-----------|
| **Trivy** | Multi-language, containers, IaC (recommended) |
| **Snyk** | Multi-language, commercial + free tier |
| **Dependabot** | GitHub-native, automatic PRs |
| **pip-audit** | Python |
| **npm audit** | JavaScript |

### Secret Detection

| Tool | Scope |
|------|-------|
| **Gitleaks** | Git history + staged changes (recommended) |
| **TruffleHog** | Git history, S3, filesystems |
| **detect-secrets** | Pre-commit hook, baseline-based |

If a secret is detected in history, **rotate it immediately** — the secret
is compromised regardless of removal from code.

### OWASP Top 10 (2021) Checklist

| # | Category | Key Tests |
|---|----------|-----------|
| A01 | Broken Access Control | Privilege escalation, IDOR |
| A02 | Cryptographic Failures | TLS, weak algorithms |
| A03 | Injection | SQLi, XSS, command injection |
| A04 | Insecure Design | Threat modeling, business logic abuse |
| A05 | Security Misconfiguration | Default credentials, verbose errors |
| A06 | Vulnerable Components | Dependency scanning |
| A07 | Auth & Identity Failures | Brute force, session management |
| A08 | Integrity Failures | CI/CD security, deserialization |
| A09 | Logging Failures | Security events logged, no PII in logs |
| A10 | SSRF | Internal URL access via user-supplied URLs |

### Fuzzing

Send randomized inputs to find crashes and unexpected behavior.

| Tool | Language |
|------|----------|
| AFL++ | C/C++ |
| Atheris | Python |
| Jazzer | Java |
| Go native fuzzing | Go (since 1.18) |
| cargo-fuzz | Rust |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Zero critical/high SAST** | 0 | Block merge. Medium may be deferred. |
| **Zero critical CVEs in deps** | 0 | Block release. |
| **Zero hardcoded secrets** | 0 | Block merge. Rotate immediately. |
| **DAST scan pass** | 0 critical/high | Run on staging before production. |
| **OWASP Top 10 coverage** | All 10 addressed | Each category has test or mitigation. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Security as afterthought** | Auditing only before release. | Shift left: SAST + dep scanning in CI on every PR. |
| **Ignoring medium findings** | They accumulate and become exploitable. | Track in backlog with SLA. |
| **False-positive fatigue** | Devs ignore all findings. | Tune rules, suppress documented FPs. |
| **Secret rotation avoidance** | Removing but not rotating. | Always rotate after detection. Git history is forever. |
| **Only one test type** | SAST misses runtime; DAST misses logic. | Layer all types. |

## References

- OWASP Top 10 (2021): https://owasp.org/www-project-top-ten/
- Semgrep: https://semgrep.dev/
- Trivy: https://aquasecurity.github.io/trivy/
- Gitleaks: https://github.com/gitleaks/gitleaks
- OWASP ZAP: https://www.zaproxy.org/
