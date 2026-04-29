---
name: curate-skills
description: >-
  Analyse the project tech stack and activate/deactivate skills
  to match. Can be run at any time — during onboarding, after
  adding dependencies, or on demand.
argument-hint: 'Optional: --dry-run to preview without changes, --rollback to restore previous state, --reapply to restore curated skills after deploy'
tools:
  - search
  - read
  - edit
  - execute/runInTerminal
  - execute/getTerminalOutput
---

# Curate Skills

Analyse this project's tech stack and activate or deactivate Agent Framework
skills to match. Present findings for confirmation before making changes.

## Mode Detection

Check the argument for mode flags:

- **`--dry-run`** → execute Steps 1–5, display the change plan, then STOP (no writes)
- **`--rollback`** → jump to the Rollback section below
- **`--reapply`** → jump to the Reapply section below
- **no flag** → execute the full curation flow (Steps 1–8)

---

## Step 1: Read Project Configuration

Read `.github/af-env.conf` and extract:

- `SRC_DIR` — source code root
- `TEST_DIR` — test root
- `PROJECT_LANGUAGE` — primary language
- `WORKTREE_ENABLED` — worktree flag (for git-worktrees skill)

If `af-env.conf` is missing, halt and ask the user to run `/onboard-project` first.

## Step 2: Discover Tech Stack

Parse dependency files to build a tech-stack profile:

**Python projects:**
- Read `pyproject.toml` → `[project.dependencies]` and `[project.optional-dependencies]`
- Read `requirements.txt` / `requirements-dev.txt` if present
- Read `Pipfile` / `poetry.lock` if present

**JavaScript/TypeScript projects:**
- Read `package.json` → `dependencies` and `devDependencies`

**Structured documentation (low-confidence sources):**
- Scan `README.md`, `docs/plan.md`, `docs/plan-architecture.md` for
  explicit tech-stack sections (e.g., "## Tech Stack", "## Dependencies")
- Only extract names that appear in structured lists, NOT prose mentions

Record each discovered package with its source and confidence:
- `high` — from dependency file (pyproject.toml, package.json)
- `low` — from documentation only

## Step 3: Scan Skills for Activation Metadata

Read every `SKILL.md` frontmatter in:
1. `.github/skills/` — currently active skills
2. `.github/skills/_available/` — available but inactive skills

For each skill, extract:
- `activation.signals` — matching criteria
- `activation.agents` — target agent files
- `activation.priority` — required / recommended / optional

Skills **without** `activation:` metadata are skipped (not yet curated).

## Step 4: Match Signals to Tech Stack

For each skill with activation metadata:

1. **`priority: required`** with **no signals** → always activate (framework invariant)
2. **`priority: required`** with **signals** → activate only if a signal matches
3. **`priority: recommended`** with **signals** → recommend if a signal matches
4. **`priority: optional`** with **signals** → list as available if a signal matches

Signal matching:
- `python_packages`: match if ANY listed package is in the discovered Python dependencies
- `js_packages`: match if ANY listed package is in the discovered JS dependencies
- `file_patterns`: match if ANY glob pattern has at least one match in the project
- `af_config`: match if ALL listed key-value pairs match `af-env.conf` values
- `imports`: match if ANY listed import is found in source files

**Confidence gating:**
- `high`-confidence matches (from dependency files) → full recommendation
- `low`-confidence matches (from docs only) → recommend with caveat:
  "detected in documentation only — verify this dependency is installed"

## Step 5: Build Change Plan

Produce two lists:

**Activate** (copy from `_available/` to `skills/`):
- Skills matched by signal that are currently in `_available/` only

**Deactivate** (remove from `skills/`):
- Currently active skills whose signals do NOT match the tech stack
  AND whose `priority` is NOT `required`
- Only suggest deactivation for skills that have activation metadata
  (never deactivate skills without metadata — they may be manually managed)

**No change:**
- Already-active skills whose signals match → keep
- Framework invariants (`priority: required`, no signals) → keep

Check for existing `.af-skills-curated` — if the user previously dismissed
a skill (`user_overrides` with `action: dismissed`), do NOT re-suggest it.

## Step 6: Present Summary Table

Display the change plan in a clear table:

```
┌──────────────────────────────┬────────────┬────────────┬────────────────────────┐
│ Skill                        │ Action     │ Confidence │ Reason                 │
├──────────────────────────────┼────────────┼────────────┼────────────────────────┤
│ integration-testing          │ ACTIVATE   │ high       │ fastapi in deps        │
│ python-dev                   │ ACTIVATE   │ high       │ pyproject.toml found   │
│ git-worktrees                │ DEACTIVATE │ high       │ WORKTREE_ENABLED=false │
│ unit-testing                 │ KEEP       │ —          │ framework invariant    │
└──────────────────────────────┴────────────┴────────────┴────────────────────────┘
```

For `--dry-run` mode: display this table and STOP. Do not proceed to Step 7.

Ask the user: "Apply these changes? (yes / yes-except [names] / no)"

- **yes** → apply all
- **yes-except [names]** → apply all except listed skills; record excluded
  skills as `user_overrides` with `action: dismissed`
- **no** → abort

## Step 7: Execute Changes

For each skill to **activate**:
1. Copy the entire folder from `skills/_available/{name}/` to `skills/{name}/`

For each skill to **deactivate**:
1. Remove the folder `skills/{name}/`
   (the copy in `_available/` remains untouched)

For each affected **agent** file (from the skill's `activation.agents`):
1. Open `.github/agents/{agent}.agent.md`
2. Find the `## Skills` section
3. Add or remove the skill reference line:
   `- **{name}** (\`skills/{name}/SKILL.md\`) — {description}`
   Place new entries after existing skill lines.

Regenerate `skills/INDEX.md`:
1. List all active skills (from `skills/*/SKILL.md` frontmatter)
2. List all available skills (from `skills/_available/*/SKILL.md` frontmatter)

Update `copilot-instructions.md` Available Skills table to match the new
active skill set.

## Step 8: Write State Files

Write `skills/curated-assignments.json`:

```json
{
  "version": 1,
  "activated": ["integration-testing", "python-dev"],
  "deactivated": ["git-worktrees"],
  "assignments": {
    "implementer": ["integration-testing", "python-dev"],
    "test-writer": ["integration-testing"],
    "code-critic": []
  }
}
```

Write `.af-skills-curated` sentinel:

```yaml
# Auto-generated by /curate-skills — do not edit manually
version: 1
last_curated: {ISO-8601 timestamp}
tech_stack_profile:
  python_packages: [{discovered packages}]
  js_packages: [{discovered packages}]
  af_config: {key-value pairs from af-env.conf}
  confidence_sources:
    {package}: {high|low}

activated:
  - name: {skill-name}
    agents: [{agent list}]
    confidence: {high|low}

deactivated:
  - name: {skill-name}
    agents: [{original agent list}]
    reason: "{why deactivated}"

user_overrides:
  - name: {skill-name}
    action: dismissed
    reason: "{user's reason or 'user declined'}"

previous_state:
  active_skills: [{list of skills that were active before this curation}]
  agent_skill_assignments:
    {agent}: [{skill names that were referenced before}]
```

---

## Reapply Mode

Deterministic replay of curated skill state after a deploy. No tech-stack
re-discovery, no user confirmation.

1. Read `skills/curated-assignments.json`. If missing, halt with:
   "No curated-assignments.json found. Run /curate-skills first."
2. For each skill in `activated`: copy folder from `_available/{name}/`
   to `skills/{name}/` (overwrites any existing copy — deploy may have
   updated `_available/` contents).
   **Note:** This overwrites local modifications to curated skill copies.
   Users who customise skill content should re-apply edits after reapply.
3. For each skill in `deactivated`: remove folder `skills/{name}/`
   (deploy re-creates template defaults; reapply undoes this).
4. For each agent in `assignments`: regenerate the `## Skills` section
   in `.github/agents/{agent}.agent.md` to include the assigned curated skills.
5. Regenerate `skills/INDEX.md` from current active/available skill folders.
6. Update `copilot-instructions.md` Available Skills table.
7. Print summary: "Reapplied curated skills: {N} activated, {M} deactivated,
   {K} agent files updated."

---

## Rollback Mode

Restore skills to pre-curation state using the sentinel snapshot.

1. Read `.af-skills-curated`. If missing, halt with:
   "No .af-skills-curated found. Nothing to roll back."
2. For each skill in `previous_state.active_skills` that is NOT currently
   in `skills/`: copy from `_available/` to restore it.
3. For each skill currently in `skills/` that is NOT in
   `previous_state.active_skills` and IS in the `activated` list:
   remove it (it was added by curation).
4. For each agent in `previous_state.agent_skill_assignments`:
   regenerate the `## Skills` section to match the saved assignment.
5. Regenerate `skills/INDEX.md` and update `copilot-instructions.md`.
6. Write updated `skills/curated-assignments.json` reflecting the restored state.
7. Print summary: "Rolled back to pre-curation state: {details}."
