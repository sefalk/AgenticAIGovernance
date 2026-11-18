---
name: 'Git Workflow'
description: 'Core git rules every agent must know: who may run git, branch naming, and the atomic commit contract. Operational depth lives in the git-workflow skill.'
applyTo: '**'
---

# Git Workflow

This file carries only the boundaries every agent needs. The operational
contract — branch lifecycle, work-item association, commit checkpoints,
planning documents, and pre-commit guards — lives in
[`git-workflow`](../skills/git-workflow/SKILL.md). Worktree lifecycle and
troubleshooting live in [`git-worktrees`](../skills/git-worktrees/SKILL.md).

## Cardinal Rule

**Only the coordinator runs git.** No worker agent (test-writer, implementer,
refactorer, critics, documenter, provider workers) executes git commands —
they change files; the coordinator handles local Git operations.

The coordinator may perform reviewed local operations. **Integration** into
shared branches is never a local merge:

- **Pure git (default):** remote push and merge are human-controlled.
- **Request-based (optional):** with a PR/MR provider enabled, the coordinator
  pushes only the feature branch; an integration worker manages the request.

Hard-denied for all agents, enforced by `block-dangerous` independently of
these instructions: force push, push to a protected branch (`dev`/`main`/
`master`), `git reset --hard`, `git rebase`, `git branch -D`, and `git add .`
or `-A`.

The coordinator loads **git-workflow** before its first Git checkpoint;
planner and documenter load it when they need its planning-document contract.
