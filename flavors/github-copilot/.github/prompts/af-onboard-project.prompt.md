---
name: af-onboard-project
description: 'Analyse the current project and auto-fill the Agent Framework configuration files (copilot-instructions, architecture map, hooks).'
argument-hint: 'Optional: any special notes about your project'
tools:
  - search
  - read
  - edit
  - execute/runInTerminal
  - execute/getTerminalOutput
  - read/terminalLastCommand
  - read/terminalSelection
---

# Project Onboarding

Analyse this project and customise the Agent Framework configuration files.
Do NOT ask questions — infer everything from the codebase. Present your
findings for confirmation before writing any changes.

## Step 1: Discover Project Metadata

Examine the project root for metadata files:

- `pyproject.toml`, `setup.py`, `setup.cfg` → project name, Python version, dependencies
- `package.json` → Node.js project details
- `README.md` → project description, purpose
- `.git/config` or remote URLs → repository URL
- `requirements.txt`, `Pipfile`, `poetry.lock` → dependency list

Collect: **project name**, **tech stack**, **repo URL**, **Python/Node version**.

## Step 2: Discover Repository Structure

Scan the directory tree (exclude `.git/`, `node_modules/`, `__pycache__/`,
`.venv/`, `*.egg-info/`). Identify:

- Source code directories and their purpose
- Test directories and their structure
- Documentation directories
- Configuration directories
- Any legacy or read-only directories

Build a concise directory tree with purpose annotations.

## Step 3: Discover Architecture Layers

For Python projects, analyse imports to classify modules:

- **Domain core:** modules with no I/O imports (no `spark`, `requests`,
  `sqlalchemy`, file I/O, network calls at module level)
- **Ports:** modules defining `Protocol` classes or abstract interfaces
- **Adapters:** modules that import I/O libraries and implement port interfaces
- **Orchestrators:** modules that wire adapters to domain and manage flow
- **Mixed:** modules that combine domain logic with I/O (note these for
  future refactoring)

Determine the correct `applyTo` glob pattern for
`architecture.instructions.md` (e.g., `src/**/*.py`, `mypackage/**/*.py`).

## Step 4: Discover Build Tools

Check for configured tools:

- **Formatter:** `ruff`, `black`, `autopep8`, `prettier` — check
  `pyproject.toml [tool.ruff]`, `[tool.black]`, `.prettierrc`
- **Linter:** `ruff`, `flake8`, `pylint`, `eslint` — check configs
- **Test runner:** `pytest`, `unittest`, `jest`, `vitest` — check
  `pyproject.toml [tool.pytest]`, `jest.config.*`
- **Type checker:** `mypy`, `pyright`, `pylance` — check configs

Build the formatter command, linter command, and test runner command.

## Step 5: Discover Project-Specific Rules

Look for existing conventions:

- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` → contributor guidelines
- Existing `.github/copilot-instructions.md` → prior instructions
- Module-level docstrings → domain terminology and constraints
- "What NOT to Do" patterns — any `# DO NOT`, `# WARNING`, `# LEGACY`
  comments or documented anti-patterns

## Step 6: Present Findings

Present a summary table:

```
Project: {name}
Tech stack: {stack}
Repo: {url}
Source dirs: {list}
Test dirs: {list}
Architecture: {summary of layers found}
Formatter: {tool + command}
Linter: {tool + command}
Test runner: {tool + command}
Special rules: {any discovered constraints}
```

## Step 7: Detect Conflicts

Before applying changes, check for existing `.github/` content:

1. **Enumerate existing files** in `.github/` — list any non-AF files
   (workflows, CODEOWNERS, dependabot.yml, etc.).
2. **Check `.af-manifest`** — read `.github/.af-manifest` for the list of
   AF-owned paths. Only AF-owned files will be modified.
3. **Check existing `copilot-instructions.md`** — if the project already has
   one with real content (not TODO placeholders), offer to **merge** rather
   than overwrite: append AF-required sections, preserve existing rules.
4. **Report conflicts** to the user:
   ```
   AF will add/modify: {list of AF-owned files}
   Existing non-AF files (untouched): {list}
   Merge needed: copilot-instructions.md (existing content detected)
   ```

## Step 8: Evaluate Available Skills

Scan `skills/_available/` for skills that match the discovered tech stack:

- Data engineering project → suggest: data-pipeline-design, data-quality,
  data-modeling
- ML project → suggest: ml-pipeline-design, model-evaluation, feature-engineering
- Web project → suggest: containerization, security-testing, performance-testing

Present recommendations: "Based on your tech stack, consider activating
these skills: {list}. Move from `skills/_available/` to `skills/` and
assign to the relevant agent."

## Step 9: Apply Changes (After Confirmation)

Ask the user to confirm the findings. Then update these files:

1. **`.github/copilot-instructions.md`** — replace all `TODO:` placeholders
   with discovered values. If merging with existing content, preserve the
   user's existing rules and append AF sections.

2. **`.github/instructions/architecture.instructions.md`** — replace the
   example module tables with actual modules. Update the `applyTo` glob.
   Mark modules as Domain Core, Ports, Adapters, Orchestrators, or Mixed.

3. **`.github/hooks/quality-gates.json.template`** → rename to
   `quality-gates.json` and replace TODO commands with actual tool commands.
   Only include hooks for tools that are actually configured in the project.

**Important:**
- Do NOT modify agent files, MANIFEST, GOVERNANCE, or skill content
- Do NOT overwrite non-AF files (workflows, CODEOWNERS, dependabot.yml)
- Do NOT invent project details — only use what you discover
- If a field cannot be determined, leave the TODO placeholder and note it
- Preserve the existing file structure — only replace placeholder content
- Respect `.af-manifest` ownership boundaries

## Step 10: Offer Skill Curation

After all onboarding changes are applied, check whether skill curation
has already been performed:

1. If `skills/curated-assignments.json` exists → skip (already curated)
2. If it does NOT exist → tell the user:

   > "Onboarding complete. Your skills can be optimised for this tech stack.
   > Run `/af-curate-skills` to activate matching skills and deactivate
   > irrelevant ones."
   >
   > **Tip:** Use `/af-setup-project` next time to run deploy + onboard +
   > curate in one step.

This is informational only — do NOT auto-run skill curation from here.
The `/af-setup-project` prompt handles the integrated flow.

${input:notes:Any special notes about your project (optional)}
