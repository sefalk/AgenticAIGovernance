# Fix: VS Code "select an instance" prompt on test tasks

- **Created:** 2026-07-29
- **Issue:** [#4](https://github.com/sefalk/AgenticAIGovernance/issues/4)
- **Branch:** `agent/4-vscode-task-instance-prompt`
- **Complexity tier:** Standard (single config file, mechanical, no logic)

## Problem

Restricted agents (test-writer, implementer, refactorer) have no
`run_in_terminal` and must run tests via fixed-arg `run_task`
(`testing.instructions.md` §147-171). VS Code intermittently interrupts these
`type: shell` tasks with a **"select an instance"** prompt, blocking
autonomous execution.

## Root cause

Not the runner and not `af-env.conf`:

- `.github/scripts/run-tests.ps1` is fully non-interactive
  (`& $python $pytestArgs 2>$null`).
- `af-env.conf` already auto-approves tests (`AUTONOMY_CAT_TESTS=auto`).

The prompt is a VS Code task-runner artifact: when a task label is re-triggered
while a previous instance is still running and there is no
`runOptions.instanceLimit`, VS Code asks which instance to target. The
framework `.vscode/tasks.json` defines **no** `presentation`/`runOptions`.

## Fix

Add to **every** task in `flavors/github-copilot/.vscode/tasks.json`:

```jsonc
"presentation": { "panel": "dedicated", "reveal": "always", "showReuseMessage": false, "clear": true },
"runOptions": { "instanceLimit": 1 }
```

- `runOptions.instanceLimit: 1` removes the instance-collision prompt (primary
  root cause).
- `presentation.panel: dedicated` gives each task label its own panel.
- Applied to all 28 tasks (not only the 12 test tasks) for consistent behavior.

### Decisions

- **Keep the `tests:` tasks.** They are deliberate design — restricted agents
  depend on them. Only the prompt is fixed.
- **Do not set `terminal.integrated.defaultProfile.windows`** in framework
  `settings.json`. That would impose a Windows-specific profile on all target
  repos; the prompt at hand is instance collision, not profile selection.

## Acceptance criteria

- [ ] AC1: All 12 `tests:` tasks carry the `presentation` + `runOptions` block.
- [ ] AC2: All remaining tasks (git/lint/metrics/pip/audit/hooks) carry the same
      block for consistency.
- [ ] AC3: Task labels and `args` are unchanged (stable API preserved).
- [ ] AC4: JSONC remains valid (parses, no trailing-comma/syntax errors).
- [ ] AC5: CHANGELOG has an Unreleased entry referencing issue #4.

## Workflow

1. Implement in framework source `flavors/github-copilot/.vscode/tasks.json`.
2. CHANGELOG entry (VERSION auto-bumps via pre-commit hook).
3. Local merge to `dev`; human pushes `dev` (protected).
4. PR `dev` → `main`, closing #4.
5. Re-deploy to MP target repo (target `.vscode/` is gitignored, so the durable
   fix lives in the framework).
