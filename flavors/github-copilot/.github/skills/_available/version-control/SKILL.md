---
name: version-control
description: Mechanical guidelines for agents interacting with Git — branching, atomic commits, history management, and identity. Prevents history destruction and ensures traceability.
argument-hint: '[git operation or workflow question]'
---

# Version Control

## When to Use

- When an agent needs to create branches, commits, or manage Git history
- When designing branching strategies for agent workflows
- When reviewing commit hygiene before merging
- When establishing Git identity for agent-generated commits

## Principles

1. **Repository as Source of Truth** — Code is only real once it is
   reliably persisted in version control.
2. **Atomic Commits** — A commit must do exactly one thing. A bug fix and a
   refactor are two commits. *(Separation of Concern)*
3. **Traceability in the Log** — The git log is the ultimate historical
   ledger. It must be linear, descriptive, and clearly link back to tasks.
   *(Transparency)*
4. **Non-Destructive Operations** — Agents must never permanently destroy
   shared remote history. *(Fail-Safe)*

## Techniques & Patterns

### 1. Branch Strategy

- **Scoped Branches:** Create short-lived feature branches targeting the
  primary integration branch.
- **Branch Naming:** Prefix with work type: `feat/`, `fix/`, `docs/`,
  `chore/`, or `agent/<agent-id>/<task-slug>`.

### 2. Commit Construction

- **Conventional Commits:** Format messages as
  `<type>[optional scope]: <description>`.
  Example: `feat(auth): enable JWT token rotation`
- **Agent Identity:** AI agents must use a distinct Git author identity.
  Never masquerade as the human user.

### 3. History Management Before Merging

- **Squash Agent Noise:** Before opening a PR or merging, squash messy
  intermediate commits into clean atomic commits.
- **Rebase over Merge:** Prefer `git rebase main` over `git merge main`
  to keep history linear (unless the project mandates merge commits).

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| **Linear history** | Squashed before PR | Feature branch has clean, logical commits. |
| **Identity check** | Agent identity used | Git log reflects the agent's identity, not the human's. |
| **Message format** | Conventional Commits | All commits pass a format linter. |

## Anti-Patterns

| Anti-Pattern | Why It's Harmful | Better Approach |
|---|---|---|
| **Force Pushing to `main`** | Permanently destroys shared history. | NEVER `git push -f` against `main`, `master`, or `develop`. |
| **The Megacommit** | 50-file commit labeled "fixed stuff" — impossible to review or bisect. | Atomic commits, one logical change each. |
| **Masquerading** | Using the human's `.gitconfig` masks AI authorship. | Locally scope: `git config --local user.name "Agent"`. |
| **Detached HEAD Panic** | Commits on detached HEAD get garbage collected. | Always ensure you're on a named branch before committing. |

## References

- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [Trunk-Based Development](https://trunkbaseddevelopment.com/)
