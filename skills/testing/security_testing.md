---
category: testing
applies_to: [all]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [secure_coding, secrets_management, threat_modeling, dependency_management]
---
# Security Testing

## Purpose

Security testing identifies vulnerabilities, misconfigurations, and weaknesses before attackers do. It validates that the application resists common attack vectors and complies with security standards. Invoke this skill when the project processes user input, handles authentication/authorization, stores sensitive data, or exposes public-facing interfaces.

## Principles

- **Defense in depth:** No single security test type is sufficient. Layer SAST, DAST, dependency scanning, and secret detection.
- **Shift left:** Integrate security testing into CI, not just pre-deployment audits. Find vulnerabilities where they're cheapest to fix -- at the code level.
- **Safety & Security (AAIG L1):** All code must adhere to the highest safety and security standards. Security quality gates are mandatory for any project handling user data.
- **Fail-Safe (AAIG L1):** When a security test reveals a critical vulnerability, the pipeline must halt. No deployment until resolved.

## Techniques & Patterns

### SAST (Static Application Security Testing)

Analyzes source code without executing it. Finds vulnerabilities from code patterns.

| Language | Tools |
|----------|-------|
| **Multi-language** | Semgrep (recommended -- open-source, rule-based, fast), SonarQube, CodeQL (GitHub) |
| **Python** | Bandit, Semgrep |
| **JavaScript/TypeScript** | ESLint security plugins (`eslint-plugin-security`), Semgrep |
| **Java/Kotlin** | SpotBugs + Find Security Bugs, Semgrep |
| **Go** | gosec, Semgrep |
| **C#/.NET** | Security Code Scan, Semgrep |
| **Rust** | `cargo-audit` (dependencies), `cargo-clippy` (code patterns) |

**CI integration:** Run SAST on every PR. Block merge on critical/high severity findings.

### DAST (Dynamic Application Security Testing)

Tests the running application by sending malicious inputs (like a real attacker).

| Tool | Type | Best For |
|------|------|----------|
| **OWASP ZAP** | Open-source proxy/scanner | General web app scanning, CI automation |
| **Burp Suite** | Commercial proxy/scanner | Deep manual + automated security testing |
| **Nuclei** | Template-based scanner | Fast, specific vulnerability checks |
| **Nikto** | Web server scanner | Server misconfiguration detection |

**Workflow:**
1. Deploy the application in a test environment.
2. Run the DAST scanner against it (spider + active scan).
3. Review findings, filter false positives.
4. Block release on critical/high findings.

### Dependency / SCA (Software Composition Analysis)

Scans dependencies for known vulnerabilities (CVEs).

| Tool | Ecosystem |
|------|-----------|
| **Trivy** | Multi-language, containers, IaC (recommended) |
| **Snyk** | Multi-language, commercial with free tier |
| **Dependabot** | GitHub-native, automatic PRs |
| **npm audit** | JavaScript/TypeScript |
| **pip-audit** | Python |
| **OWASP Dependency-Check** | Java, .NET |
| **cargo-audit** | Rust |

**Best practices:**
- Run on every CI build. Fail on critical CVEs.
- Enable automated dependency update PRs (Dependabot, Renovate).
- Pin dependency versions (lockfiles). Audit before upgrading.

### Secret Detection

Scans code, commits, and config for hardcoded secrets (API keys, passwords, tokens).

| Tool | Scope |
|------|-------|
| **Gitleaks** | Git history + staged changes (recommended) |
| **TruffleHog** | Git history, S3, filesystems |
| **detect-secrets** (Yelp) | Pre-commit hook, baseline-based |
| **GitHub Secret Scanning** | GitHub-native, partner pattern detection |

**Best practices:**
- Run as a pre-commit hook AND in CI (defense in depth).
- If a secret is detected in history, rotate it immediately -- the secret is compromised regardless of removal.
- Use `.gitleaksignore` or `.secretsignore` for documented false positives only.

### OWASP Top 10 Checklist

Validate coverage against the current OWASP Top 10 (2021):

| # | Category | Key Tests |
|---|----------|-----------|
| A01 | Broken Access Control | Test horizontal/vertical privilege escalation, IDOR, missing function-level access control |
| A02 | Cryptographic Failures | Verify TLS enforcement, check for weak algorithms, validate sensitive data encryption at rest |
| A03 | Injection | SQL injection, XSS, command injection, LDAP injection -- via DAST + SAST |
| A04 | Insecure Design | Threat modeling review, business logic abuse tests |
| A05 | Security Misconfiguration | Default credentials, verbose error messages, unnecessary features enabled |
| A06 | Vulnerable Components | Dependency scanning (SCA), outdated framework detection |
| A07 | Auth & Identity Failures | Brute force protection, session management, MFA bypass attempts |
| A08 | Software & Data Integrity | CI/CD pipeline security, unsigned artifact detection, deserialization attacks |
| A09 | Logging & Monitoring Failures | Verify security events are logged, verify no sensitive data in logs |
| A10 | SSRF | Test internal URL access via user-supplied URLs, DNS rebinding |

### Fuzzing

Sends randomized, malformed, or boundary inputs to find crashes, hangs, and unexpected behavior.

| Tool | Language |
|------|----------|
| **AFL++** | C/C++, any compiled binary |
| **libFuzzer** | C/C++ (built into LLVM) |
| **Atheris** | Python |
| **Jazzer** | Java |
| **go-fuzz / native fuzzing** | Go (native since Go 1.18: `testing.F`) |
| **cargo-fuzz** | Rust |

**When to fuzz:** Parsers, deserializers, protocol handlers, any code processing untrusted input.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Zero critical/high SAST findings** | 0 | Block merge on critical/high. Medium may be deferred with ticket. |
| **Zero critical CVEs in deps** | 0 | Block release. High CVEs must have mitigation plan within 48h. |
| **Zero hardcoded secrets** | 0 | Block merge. Rotate any detected secret immediately. |
| **DAST scan pass** | 0 critical/high | Block release on critical/high. Run on staging before production. |
| **OWASP Top 10 coverage** | All 10 addressed | Each category must have at least one test or documented mitigation. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Security as afterthought** | Auditing only before release. Costly fixes, delayed launches. | Shift left: SAST + dep scanning in CI on every PR. |
| **Ignoring medium findings** | Medium-severity issues accumulate. Some become exploitable. | Track in backlog with SLA. No permanent suppression without review. |
| **False-positive fatigue** | Too many false positives cause developers to ignore all findings. | Tune rules, create baselines, suppress documented FPs. |
| **Secret rotation avoidance** | Removing a secret from code without rotating it. | The secret exists in git history. Always rotate after detection. |
| **Only one type of security test** | SAST alone misses runtime issues; DAST alone misses logic bugs. | Layer SAST + DAST + SCA + secrets + fuzzing. |


## See Also

- [Secure Coding](../security/secure_coding.md)
- [Secrets Management](../security/secrets_management.md)
- [Threat Modeling](../security/threat_modeling.md)
- [Dependency Management](../code_quality/dependency_management.md)

## References

- OWASP Top 10 (2021): https://owasp.org/www-project-top-ten/
- OWASP Testing Guide: https://owasp.org/www-project-web-security-testing-guide/
- Semgrep: https://semgrep.dev/
- Trivy: https://aquasecurity.github.io/trivy/
- Gitleaks: https://github.com/gitleaks/gitleaks
- OWASP ZAP: https://www.zaproxy.org/
