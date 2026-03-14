---
title: Agentic Version Control
description: Mechanical guidelines for agents interacting with Git repositories, branching, and commit history.
applies_to: [all]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-03-04
related: [code_review, ci_cd, task_decomposition]
---
# Agentic Version Control

## Purpose
This skill defines the mechanical operations of version control. For Autonomous AI Agents, interacting with Git requires explicit care: agents can destroy history instantly if they misuse tools like `push -f`. This skill teaches agents *how* to construct clean, traceable repositories that align with the declarative constraints of the framework.

## Principles
1. **Repository as the Source of Truth:** Code is only real once it is reliably persisted in version control.
2. **Atomic Commits:** A commit must do exactly one thing. If an agent fixes a bug and refactors a function, those are two commits. *(AAIG L1: Separation of Concern)*
3. **Traceability in the Log:** The git log serves as the ultimate historical ledger. It must be linear, descriptive, and clearly link back to business logic or task assignments. *(AAIG L1: Transparency/Traceability)*
4. **Non-Destructive Operations:** Agents must never permanently destroy shared remote history. *(AAIG L1: Fail-Safe)*

## Techniques & Patterns

### 1. Branch Strategy (The Working Context)
*   **Scoped Branches:** Unless explicitly told otherwise by the Level-4 Project Instantiation, agents should create short-lived feature branches targeting the primary integration branch (e.g., `feature/fix-auth-bug` -> `main`).
*   **Branch Naming:** Prefix branches with their type of work (e.g., `feat/`, `fix/`, `docs/`, `chore/`).

### 2. Commit Construction
*   **Conventional Commits:** Agents must format messages using the Conventional Commits specification.
    *   *Format:* `<type>[optional scope]: <description>`
    *   *Example:* `feat(auth): enable JWT token rotation`
*   **Attribute Identity:** AI agents must use a distinct Git author identity (e.g., `git config user.name "ProjectAgent-Bot"`). They must never masquerade as the human user.

### 3. History Management Before Merging
*   **Squashing Agent Noise:** AI agents often create messy local histories (e.g., "trying fix", "fix typo", "fixing test"). Before opening a PR or merging, the agent **must** interactively rebase or squash these intermediate steps into a single, professional atomic commit.
*   **Rebasing over Merging:** When updating a feature branch with changes from `main`, prefer `git rebase main` over `git merge main` to keep the project history linear, unless the project specifically mandates merge commits.

## Quality Gates
*   **Linearity Check:** The commit history of a feature branch must be logically squashed before a PR is opened.
*   **Identity Check:** The `git log` must reflect the Agent's identity, not the human operator's identity.
*   **Message Format Check:** All commits must pass a linter enforcing Conventional Commits.

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **Force Pushing to `main`** | Permanently destroys the team's shared history and roll-back capability. | NEVER run `git push -f` against `main`, `master`, or `develop`. |
| **The "Megacommit"** | A 50-file commit labeled "fixed stuff" is impossible to code-review or `git bisect`. | Use `git add -p` or commit file-by-file (Atomic Commits). |
| **Masquerading** | Using the human's global `.gitconfig` masks the fact that an AI generated the code, breaking auditability. | Locally scope the git config (`git config --local user.name "Agent"`). |
| **Detached HEAD Panic** | Agents entering detached HEAD state and making unbranch commits that get garbage collected. | Always ensure you are on a named branch (`git checkout -b <name>`) before committing. |

## See Also
*   [Agentic Code Review](../code_quality/code_review.md)
*   [CI/CD](../devops/ci_cd.md)

## References
*   [Conventional Commits Specification](https://www.conventionalcommits.org/)
*   [Trunk Based Development](https://trunkbaseddevelopment.com/)
