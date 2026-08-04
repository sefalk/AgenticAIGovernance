---
name: 'VS Code Task Authoring'
description: 'Rules for editing .vscode/tasks.json — strict JSON, stable labels, venv routing, and fixed arguments.'
applyTo: '**/.vscode/tasks.json'
---

# VS Code Task Authoring

`tasks.json` is an **agent execution surface**, not a convenience file. Agents
without `run_in_terminal` (test-writer, implementer, refactorer) can only run
tools through the tasks defined here. Every rule below exists because breaking
it silently removed an agent's ability to do its job.

## No comments — strict JSON only

VS Code accepts JSONC in `tasks.json`, but the `createAndRunTask` tool **cannot
parse it**. A single `//` line disables the documented fallback path for
restricted agents (`skills/test-execution/SKILL.md`).

Do not add comments. Put per-task explanation in the `detail` field — it is
data, survives tooling round-trips, and is shown in the task picker. Put
cross-cutting rules in this file.

A pre-commit guard (`.github/hooks/scripts/check-strict-json.py`) rejects
commits that stage a `tasks.json` which is not strict JSON. Deliberate override:
`ALLOW_JSONC=1 git commit ...`.

## Task labels are a stable API

Labels are referenced by agent definitions, `testing.instructions.md`, and
`skills/metrics/SKILL.md`. Renaming a label breaks `run_task` calls at runtime
with no compile-time signal.

Before renaming or removing a label, grep the payload for it and update every
reference in the same commit. Prefer **adding** a task over renaming one.

## Resolve executables through the venv

Task shells do **not** activate the project virtual environment. A bare `ruff`,
`pytest`, or `pip-audit` command fails with `CommandNotFoundException` on a
machine where the tool is only installed in `.venv`.

Two acceptable forms:

1. **Call a runner script** — preferred. `.github/scripts/run-tests.ps1`,
   `run-lint.ps1`, `run-metrics.ps1` resolve the interpreter themselves and
   apply the configuration from `af-env.conf`.
2. **Invoke the venv interpreter explicitly** —
   `"command": ".venv\\Scripts\\python.exe"`, `"args": ["-m", "<tool>", ...]`.

Never `"command": "<tool>"` for a Python-provided tool.

Routing through a runner script has a second benefit: the rule set or scope
stays single-sourced. A task that calls `ruff` directly bypasses
`LINTING_STRICTNESS` and silently lints with different rules than the quality
gate.

## Fixed arguments only

Restricted agents call `run_task` with a label and nothing else — they cannot
pass parameters. Every distinct invocation needs its own task
(`tests: domain`, `tests: domain + coverage`, `lint: ruff check tests`, …).

Do not use `${input:...}` prompts in agent-facing tasks; they block autonomous
execution waiting for human input.

## Required boilerplate on every task

```json
"presentation": { "panel": "dedicated", "reveal": "always", "showReuseMessage": false, "clear": true },
"runOptions": { "instanceLimit": 1 }
```

Without `instanceLimit`, re-triggering a `type: shell` label while a previous
instance still runs makes VS Code interrupt with a "select an instance" prompt,
which halts autonomous execution. The dedicated panel keeps concurrent task
output separable.

## Checklist before saving

- [ ] File parses as strict JSON (no `//`, no trailing commas)
- [ ] Every task has `detail`, `presentation`, and `runOptions.instanceLimit`
- [ ] No bare Python-tool executables as `command`
- [ ] No renamed or deleted labels without updating all references
- [ ] Arguments are literal — no `${input:...}`
