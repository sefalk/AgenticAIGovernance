---
name: setup-project
description: >-
  End-to-end project setup: deploy the Agent Framework, run onboarding
  to configure project files, then curate skills for the tech stack —
  all in one conversation with a single confirmation.
argument-hint: 'Optional: path to AF source (default: ./_agent-framework)'
tools:
  - search
  - read
  - edit
  - execute/runInTerminal
  - execute/getTerminalOutput
  - read/terminalLastCommand
  - read/terminalSelection
---

# Setup Project

Run the full Agent Framework setup pipeline in one conversation:
**Deploy → Onboard → Curate Skills**. Requires only one user confirmation
before applying changes.

## Overview

| Phase | What Happens | User Interaction |
|---|---|---|
| **1. Deploy** | Copy AF files into `.github/` and `.vscode/` | None (automatic) |
| **2. Onboard** | Analyse codebase, fill configuration files | Review findings |
| **3. Curate** | Match skills to tech stack, activate/deactivate | Part of same review |
| **4. Apply** | Write all changes at once | **One confirmation** |

---

## Phase 1: Deploy

Run the deploy script to install AF files. Detect the OS and use the
appropriate script.

**Windows:**
```powershell
.\_agent-framework\deploy.ps1
```

**macOS / Linux:**
```bash
./_agent-framework/deploy.sh
```

If the user provided a custom AF source path via the argument, use that
instead of the default `_agent-framework`.

If the deploy script is not found at the expected path, check for common
alternatives (`_agent-framework/`, `agent-framework/`, `af/`) and ask
the user only if none are found.

**After deploy completes:**
- Verify `.github/.af-manifest` exists (proves deploy succeeded)
- Verify `.github/af-env.conf` exists (may be a new empty template)
- Note any deploy warnings or errors for the summary

Do NOT stop for confirmation here — proceed directly to Phase 2.

---

## Phase 2: Onboard

Perform the full onboarding analysis inline (same logic as
`/onboard-project`). Do NOT delegate to another prompt — execute all
steps here.

### 2a: Discover Project Metadata

Examine the project root for metadata files:

- `pyproject.toml`, `setup.py`, `setup.cfg` → project name, Python version, dependencies
- `package.json` → Node.js project details
- `README.md` → project description, purpose
- `.git/config` or remote URLs → repository URL
- `requirements.txt`, `Pipfile`, `poetry.lock` → dependency list

Collect: **project name**, **tech stack**, **repo URL**, **Python/Node version**.

### 2b: Discover Repository Structure

Scan the directory tree (exclude `.git/`, `node_modules/`, `__pycache__/`,
`.venv/`, `*.egg-info/`). Identify:

- Source code directories and their purpose
- Test directories and their structure
- Documentation directories
- Configuration directories

Build a concise directory tree with purpose annotations.

### 2c: Discover Architecture Layers

For Python projects, analyse imports to classify modules:

- **Domain core:** modules with no I/O imports
- **Ports:** modules defining `Protocol` classes or abstract interfaces
- **Adapters:** modules that import I/O libraries and implement port interfaces
- **Orchestrators:** modules that wire adapters to domain and manage flow
- **Mixed:** modules that combine domain logic with I/O

Determine the correct `applyTo` glob pattern for
`architecture.instructions.md`.

### 2d: Discover Build Tools

Check for configured tools:

- **Formatter:** `ruff`, `black`, `autopep8`, `prettier`
- **Linter:** `ruff`, `flake8`, `pylint`, `eslint`
- **Test runner:** `pytest`, `unittest`, `jest`, `vitest`
- **Type checker:** `mypy`, `pyright`, `pylance`

Build the formatter command, linter command, and test runner command.

### 2e: Discover Project-Specific Rules

Look for existing conventions:

- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`
- Module-level docstrings for domain terminology
- `# DO NOT`, `# WARNING`, `# LEGACY` comments

---

## Phase 3: Curate Skills

Perform skill curation inline (same logic as `/curate-skills`).
This runs immediately after onboarding — reuse the tech stack data
already discovered in Phase 2.

### 3a: Read Skill Metadata

Read every `SKILL.md` frontmatter in:
1. `.github/skills/` — currently active skills
2. `.github/skills/_available/` — available but inactive skills

Extract `metadata.activation` blocks (signals, agents, priority).
Skills without activation metadata are skipped.

### 3b: Match Signals to Tech Stack

Use the dependency data from Phase 2:

- `python_packages` → match against discovered Python deps
- `js_packages` → match against discovered JS deps
- `file_patterns` → match against project file tree
- `af_config` → match against `.github/af-env.conf` values
- `imports` → match against source file imports

Apply confidence gating:
- `high` — from dependency files (pyproject.toml, package.json)
- `low` — from documentation only

### 3c: Build Change Plan

Produce lists: **Activate**, **Deactivate**, **Keep**.

For skills with `priority: required` and no signals → always keep.

---

## Phase 4: Present Combined Summary

Present all findings in one consolidated summary:

```
══════════════════════════════════════════════════════
  SETUP SUMMARY
══════════════════════════════════════════════════════

📦 Deploy
  Status: {success/warnings}
  Files deployed: {count}

🔍 Project Analysis
  Project: {name}
  Tech stack: {stack}
  Source dirs: {list}
  Test dirs: {list}
  Architecture: {layers summary}
  Formatter: {tool + command}
  Linter: {tool + command}
  Test runner: {tool + command}

🧩 Skill Curation
┌──────────────────────┬────────────┬────────────┬─────────────────────┐
│ Skill                │ Action     │ Confidence │ Reason              │
├──────────────────────┼────────────┼────────────┼─────────────────────┤
│ ...                  │ ACTIVATE   │ high       │ ...                 │
│ ...                  │ DEACTIVATE │ high       │ ...                 │
│ ...                  │ KEEP       │ —          │ framework invariant │
└──────────────────────┴────────────┴────────────┴─────────────────────┘

📝 Configuration Changes
  copilot-instructions.md: {what will change}
  architecture.instructions.md: {what will change}
  af-env.conf: {what will change}
  Skills: {N activated, M deactivated}
  Agent files: {K updated with skill references}

══════════════════════════════════════════════════════
```

Ask the user **once**:

> "Apply all changes? (yes / yes-except [items] / no)"

- **yes** → apply everything (Phase 5)
- **yes-except [items]** → apply all except listed items; for skills,
  record excluded ones as `user_overrides` with `action: dismissed`
- **no** → abort (deploy already happened, but config remains at defaults)

---

## Phase 5: Apply All Changes

Execute all writes in one batch:

### Onboarding writes:
1. **`.github/copilot-instructions.md`** — replace TODO placeholders with
   discovered values. If merging with existing content, preserve user rules.
2. **`.github/instructions/architecture.instructions.md`** — replace example
   module tables with actual modules. Update `applyTo` glob.
3. **`.github/af-env.conf`** — fill in discovered values (SRC_DIR, TEST_DIR,
   PROJECT_LANGUAGE, etc.)

### Skill curation writes:
4. Copy activated skills from `_available/` to `skills/`
5. Remove deactivated skills from `skills/`
6. Update agent `.agent.md` files with skill references in `## Skills` sections
7. Regenerate `skills/INDEX.md`
8. Update `copilot-instructions.md` Available Skills table
9. Write `skills/curated-assignments.json`
10. Write `.af-skills-curated` sentinel

### Final:
11. Print completion message:
    ```
    ✅ Setup complete!
    - AF deployed and configured
    - {N} skills activated, {M} deactivated
    - Configuration files updated

    Next: open a new chat and try @coordinator with a task,
    or use /tdd-feature for a full TDD workflow.
    ```

**Important:**
- Do NOT modify agent core files, MANIFEST, GOVERNANCE, or hook scripts
- Do NOT overwrite non-AF files (workflows, CODEOWNERS, dependabot.yml)
- Do NOT invent project details — only use what you discover
- If a field cannot be determined, leave the TODO placeholder and note it

${input:af_source:Path to AF source directory (default: ./_agent-framework)}
