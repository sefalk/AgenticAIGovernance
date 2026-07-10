---
name: af-validate-framework
description: 'Scan all Agent Framework files for internal consistency — broken references, invalid frontmatter, threshold divergence, missing files.'
argument-hint: 'Optional: specific area to focus on (e.g., "skills only", "thresholds")'
tools:
  - search
  - read
  - execute/runInTerminal
  - execute/getTerminalOutput
  - read/terminalLastCommand
  - read/terminalSelection
---

# Agent Framework Self-Validation

Scan all `.github/` Agent Framework files and report internal consistency
issues. This is a **read-only** audit — do not fix anything, only report.

## Step 1: Agent Skill References

For each `.agent.md` file in `.github/agents/`:

1. Parse the `skills:` list from the agent description body (look for
   `## Skills` sections or inline skill references like
   `Read the skill: skills/{name}/SKILL.md`).
2. For each referenced skill name, verify that
   `.github/skills/{name}/SKILL.md` exists.
3. Report any broken references as **FAIL**.

## Step 2: YAML / Markdown Frontmatter

For each `.agent.md`, `.prompt.md`, and `.instructions.md` file:

1. Parse the YAML frontmatter (between `---` delimiters).
2. Verify required fields are present:
   - `.agent.md`: `name`, `description`
   - `.prompt.md`: `name`, `description`
   - `.instructions.md`: `name`, `description`, `applyTo`
3. Verify `applyTo` patterns (if present) are valid glob syntax.
4. **Flag uncustomized defaults:** If any `applyTo` still contains a
   generic AF template default like `src/**/*.py`, report as **WARN** —
   it likely wasn't updated during project onboarding. Compare against
   the project's actual source directory structure.
5. Report missing fields as **WARN**, invalid syntax as **FAIL**.

## Step 3: Cross-File References

Scan all `.md` files in `.github/` for cross-references:

1. Look for patterns like `MANIFEST §{N}`, `§ {N}`, `templates/{name}`,
   `instructions/{name}`, `skills/{name}`, `agents/{name}`.
2. Verify each reference resolves to an existing file or section.
3. For `MANIFEST §{N}` references, verify the section number exists
   in MANIFEST.md (match `## {N}.` headings).
4. Report broken references as **FAIL**.

## Step 4: Metric Threshold Consistency

1. Read the **Metric Thresholds** table in MANIFEST.md § 5.
2. Search all other `.md` files for hardcoded threshold numbers
   (e.g., `90%`, `85%`, `80%`, `≥ 60%`, `≤ 10`, `≤ 15`).
3. If any file states a threshold that contradicts MANIFEST § 5,
   report as **FAIL** with both values and file locations.
4. Files that say "see MANIFEST § 5" or "per MANIFEST § 5" are OK.

## Step 5: Governance Layer Files

1. Verify `GOVERNANCE.md` exists and contains L1 Core Principles.
2. For each `R-SD-{NN}` rule referenced in MANIFEST.md § 12, verify
   the rule exists in GOVERNANCE.md.
3. Report missing rules as **WARN**.

## Step 6: Template Completeness

1. For each `.md` file in `.github/templates/`, verify it contains
   placeholder markers (`<!-- ... -->` or `{...}`).
2. Verify templates referenced by agents or instructions actually exist.
3. Report missing templates as **FAIL**.

## Step 7: Skill Directory Structure

**Automated check (preferred):** Run the validation script:

```bash
python .github/scripts/validate-skills.py
```

Add `--deep-available` to also deeply validate `_available/` skills.
Add `--ci` for GitHub Actions annotation output.

The script checks:
- Every skill directory has a `SKILL.md` with valid YAML frontmatter
- `name` matches directory name, is lowercase-hyphenated, ≤64 chars
- `description` is non-empty, ≤1024 chars, no XML tags
- `INDEX.md` lists all active and available skills (no orphans/phantoms)

**Manual fallback** (if script unavailable):

**Active skills** (`.github/skills/`, excluding `_available/`):
For each directory, perform a full check:

1. Verify a `SKILL.md` file exists in the directory.
2. Verify the `SKILL.md` has a top-level `#` heading.
3. Optionally check for a `## Quality Gates` section (report absence
   as **INFO** — not all skills need one).

**Available skills** (`.github/skills/_available/`):
Light scan only — verify each subdirectory contains a `SKILL.md` file.
Do not validate contents. Report missing files as **WARN**.

## Step 8: Hook Configuration

1. Verify `.github/hooks/` directory exists.
2. For each `.json` or `.json.template` file, verify it is valid JSON
   (or JSON-with-comments for `.jsonc`).
3. Report parse errors as **FAIL**.

## Output Format

Present results as a structured report:

```markdown
## AF Validation Report

### Summary
- **Files scanned:** {count}
- **FAIL:** {count} (must fix)
- **WARN:** {count} (should review)
- **INFO:** {count} (informational)
- **PASS:** All other checks

### FAIL Items
1. **{file}** — {description of the issue}

### WARN Items
1. **{file}** — {description}

### INFO Items
1. **{file}** — {description}
```

If there are zero FAIL items, state: **✅ Framework integrity: PASS**

If the user specified a focus area in the argument, run only the
relevant steps and skip the rest.
