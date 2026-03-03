---
title: Agentic Code Review
description: Automated evaluation of pull requests via static analysis, diff analysis, and ADR compliance checks
applies_to: [all]
complexity: intermediate
maturity: draft
version: "2.0"
last_reviewed: 2026-02-26
related: [secure_coding, static_analysis, dependency_management, accessibility_testing, error_handling, documentation, refactoring]
---
# Agentic Code Review

## Purpose
To treat code review as a rigorous, automatable verification step ensuring code quality, security, and architectural alignment. For Autonomous AI Agents, code review is not about human etiquette, but about systematically verifying the diff against explicit governance rules, test coverage thresholds, and established patterns.

## Principles
1. **Automation over Opinions:** Formatting, linting, and basic security checks must be automated in CI (Prettier, ESLint). AI Agents should not spend tokens debating brace placement.
2. **Review the Diff, Not Just the Code:** Code review assesses the *delta*. Agents must verify that the diff explicitly solves the linked issue and doesn't introduce regressions in unmodified files. *(AAIG L1: Review Principle)*
3. **Architectural Compliance:** Verify that the pull request adheres to the project's Architecture Decision Records (ADRs). New dependencies or structural changes must have an approved ADR. *(AAIG L1: Separation of Concern)*
4. **Test Corroboration:** Code that introduces new logic but zero new tests is incomplete by default.

## Techniques & Patterns

### 1. Diff Analysis & AST Parsing
*   **Abstract Syntax Tree (AST):** Agents should parse the AST of the modified files (using tools like `ast-grep` or Semgrep) to understand structural changes, rather than relying solely on raw string diffs, to detect complex logical issues.
*   **The "Blast Radius" Check:** Use dependency graphs (`npm graph`, `pipdeptree`) to predict what downstream modules are impacted by the PR, and verify those modules are covered by the automated test suite.

### 2. Static Analysis Integration 
*   **SonarQube / CodeQL:** The review process starts by ingesting the results of static analysis SAST tools. If SonarQube flags a "Blocker" or "Critical" code smell, the review fails automatically before semantic analysis begins.

### 3. Contextual Pattern Matching
*   **Anti-Pattern Detection:** Scan the proposed changes against known project-specific anti-patterns (e.g., verifying that raw SQL is not used when the project strictly requires Prisma ORM).
*   **Secret Sweep:** Ensure no credentials, API keys, or PII regex patterns appear anywhere in the diff payload. (Tools like TruffleHog or Gitleaks).

### 4. PR Description & Documentation
*   Verify that the PR description adheres to the `PULL_REQUEST_TEMPLATE.md`.
*   Verify that any new exported functions or classes include JSDoc/Docstring blocks.
*   Verify that changes to environment variables (`.env.example`) are documented in the README.

## Quality Gates
*   **Coverage Threshold:** The PR diff cannot reduce the total repository test coverage below the minimum threshold (e.g., 80% line coverage via Istanbul/JaCoCo).
*   **CI Green:** No code review begins until the pipeline (build, test, lint) reports a green status.
*   **ADR Verification:** If `package.json` adds a new high-impact dependency, the review system checks for a corresponding `docs/adr/` entry.
*   **Semantic Passing:** A secondary AI agent must provide a structured JSON response evaluating the PR against the specific [Level-2 Domain Rules](file:///d:/Dokumente/Projekte/AgenticAIGovernance/L2_Software_Development.md).

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **Rubber Stamping** | Agents instantly approving a PR because the syntax is valid, ignoring architectural drift. | Cross-reference the PR against the specific Project Instantiation rules and ADRs. |
| **"LGTM" Reviews** | A review with zero meaningful feedback or actionable requests provides no value or audit trail. | Every review must include a structured summary of what was checked (Performance, Security, Architecture). |
| **Reviewing 10,000 Lines** | Massive monolithic PRs are impossible for humans to review and exhaust the context window of AI agents. | Force PR decomposition. Reject PRs exceeding 500 lines of functional code changes. |
| **Arguing over formatting** | Leaving 20 comments on trailing commas wastes compute and time. | Fail the build if `prettier --check` fails. Format validation belongs in the pipeline, not the review. |

## See Also
*   [Static Analysis](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/code_quality/static_analysis.md)
*   [Level-2 Agentic Software Development Rules](file:///d:/Dokumente/Projekte/AgenticAIGovernance/L2_Software_Development.md)

## References
*   [Google Engineering Practices: Code Review](https://google.github.io/eng-practices/review/reviewer/)
*   [Semgrep Rules Repository](https://semgrep.dev/explore)
