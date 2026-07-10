# Feature: Automated Skill Curation

**Status:** ⬜ TODO
**Created:** 2026-04-29
**Owner:** User Request
**Type:** Enhancement (skill management, deploy, onboarding)

---

## 1. Problem Statement

The AF ships with a two-tier skill library: 17 active skills (in `skills/`)
and 34 available-on-demand skills (in `skills/_available/`). The active set
is a **generic default** — it fits no specific project without manual tuning.

Today, skill activation requires **4 manual steps** per skill:

1. Copy folder from `_available/` to `skills/`
2. Edit the relevant `.agent.md` files to add skill references
3. Update `skills/INDEX.md` agent-skill matrix
4. Update `copilot-instructions.md` Available Skills table

No automation exists for any of these. The result:

- **Projects miss relevant skills.** A FastAPI + SQLModel project ships
  without `integration-testing`, `python-dev`, or `idempotent-operations`.
  Agents never consult those skills, silently producing lower-quality output.
- **Projects carry irrelevant skills.** A project with `WORKTREE_ENABLED=false`
  still has `git-worktrees` active. Agents read irrelevant skill content,
  wasting context tokens and potentially producing confusing guidance.
- **Onboarding recommends but doesn't execute.** `/af-onboard-project` Step 8
  scans for tech-stack matches and presents recommendations, but Step 9
  explicitly says "Do NOT modify agent files." The user must perform the
  4-step process manually or not at all.
- **No re-curation path.** As a project evolves (adds a database, introduces
  an API, enables worktrees), there is no command to re-evaluate and adapt
  the active skill set.

### Contradiction in Onboarding

`/af-onboard-project` Step 8 says:
> "Based on your tech stack, consider activating these skills: {list}.
> Move from `skills/_available/` to `skills/` and **assign to the relevant
> agent.**"

Step 9 says:
> "Do NOT modify agent files, MANIFEST, GOVERNANCE, or skill content."

These instructions conflict. An agent following Step 9 cannot fulfil the
"assign to the relevant agent" instruction from Step 8.

---

## 2. Proposed Solution: `/af-curate-skills` Prompt + Automation

### 2.1 Architecture Overview

Introduce a **standalone `/af-curate-skills` slash command** that can be
invoked at any time — during onboarding, after dependency changes, or
manually when the developer decides to re-evaluate.

```
                    ┌────────────────────────┐
                    │    /af-curate-skills       │
                    │  (standalone command)   │
                    └───────────┬────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                  ▼
     ┌──────────────┐ ┌──────────────────┐ ┌─────────────┐
     │  1. Discover  │ │  2. Match Skills │ │  3. Apply    │
     │  Tech Stack   │ │  to Stack        │ │  Changes     │
     └──────────────┘ └──────────────────┘ └─────────────┘
     pyproject.toml    SKILL.md frontmatter   Copy/delete skills
     package.json      metadata.activation    Edit agent sections
     af-env.conf       Confidence gating      Update INDEX
     imports scan                             Update instructions
     planning docs
```

### 2.2 Three Phases

**Phase 1: Discover** — Analyse the project to extract the tech stack.

Sources (in priority order):
1. `af-env.conf` → `SRC_DIR`, `PROJECT_LANGUAGE`, `WORKTREE_ENABLED`
2. `pyproject.toml` / `requirements.txt` → Python dependencies
3. `package.json` → JS/TS dependencies
4. Import scan on `SRC_DIR/**/*.py` → actually-used libraries
5. Existing `copilot-instructions.md` → project description, tech stack
6. **Planning & documentation files** → broad workspace scan for
   `**/*.md`, `**/*.txt`, `**/*.rst`, `**/*.adoc`
   (excluding `.venv/`, `node_modules/`, `.git/`, `__pycache__/`,
   and files already processed by sources 1–5: `af-env.conf`,
   `pyproject.toml`, `requirements.txt`, `package.json`,
   `copilot-instructions.md`).
   Only plain-text formats — no binary formats (`.docx`, `.pdf`, etc.)
   to avoid external library dependencies.

   The scan targets **structured markers**, not free-text semantic analysis.
   The marker list is extensible — implementations should start with these
   patterns and expand as real-world docs reveal new conventions:

   - YAML frontmatter blocks (e.g., `tech_stack:` keys)
   - Markdown tables where **any column header** contains "Choice",
     "Technology", "Stack", "Tool", "Framework", or "Library"
     (e.g., a table with "Layer | Choice | Rationale" qualifies)
   - Sections titled `## Tech Stack`, `## Dependencies`, `## Technology`,
     `## Stack`, `## Architecture`, `## Tools`, `## Tooling`
   - Bullet lists directly under those headings
   - Explicit "Tech stack: X, Y, Z" one-liners

   Free-text mentions (e.g., "we considered Flask but chose FastAPI") are
   **not** treated as signals — only declarative statements in structured
   sections. This avoids false positives from comparison tables or
   rejected-alternative discussions.

   Includes root-level files as well as any subfolder — not restricted
   to `docs/`.

Source 6 is critical for **pre-implementation projects** where planning
documents exist but no code, dependency files, or config has been written
yet. A project plan that states "Tech stack: FastAPI, SQLModel, pytest"
is a valid discovery source even without a `pyproject.toml`.

**Discovery precedence:** Concrete artifacts (sources 1–4) override
planning documents (source 6) when both exist. Planning docs serve as
the **fallback** for greenfield projects and as **validation** for
established ones (flag drift between planned and actual stack).

Output: a structured tech-stack profile (language, frameworks, DB, testing
tools, external APIs, enabled AF features) with a **confidence indicator**
per entry:
- `high` — from dependency file or import scan (verifiable)
- `medium` — from `copilot-instructions.md` or `af-env.conf` (configured)
- `low` — from planning documents only (declared intent, not yet realised)

**Confidence gating in Phase 2 (Match):**

| Confidence | `required` skills | `recommended` skills | `optional` skills |
|---|---|---|---|
| `high` | Auto-activate | Auto-activate | Suggest, user opts in |
| `medium` | Auto-activate | Suggest with strong recommendation | Suggest, user opts in |
| `low` | Suggest with strong recommendation | Suggest | List only (no prompt) |

**Auto-filled `copilot-instructions.md`:** If `/af-onboard-project` auto-fills
the tech stack section from planning docs, it must insert an origin marker:
`<!-- af:auto-filled-from-docs -->`. When `/af-curate-skills` encounters this
marker, it downgrades affected entries from `medium` to `low`. Without the
marker, `copilot-instructions.md` content is treated as `medium` (assumed
human-authored or human-reviewed).

**Phase 2: Match** — Map tech stack to skills using matching rules.

Each skill in `_available/` should declare **activation signals** in its
SKILL.md YAML frontmatter (see §3). The matching engine compares the
discovered tech stack against these signals to produce:
- Skills to **activate** (copy from `_available/` to `skills/`)
- Skills to **deactivate** (delete from `skills/`; canonical copy remains in `_available/`)
- Skills to **keep** (already correctly placed)

**Deactivation rule:** A skill currently in `skills/` is a deactivation
candidate if ALL of: (a) it has activation metadata with non-empty signals,
(b) none of its signals match the discovered tech stack, and (c) it is not
`priority: required` with empty signals. Skills without activation metadata
are never deactivation candidates (see §7 edge case table).

**Copy, not move:** `_available/` is AF-owned — deploy overwrites it from
the template on every update. Activation **copies** into `skills/`;
deactivation **deletes** from `skills/`. The `_available/` directory is
never modified by curation.

The match also determines which **agents** should reference each skill,
using the agent-skill affinity matrix in INDEX.md as a baseline.

**Phase 3: Apply** — Execute the changes with user confirmation.

Present a diff-style summary before writing:
```
Skills to ACTIVATE (copy from _available/ to skills/):
  + integration-testing     → test-writer, test-critic, implementer
  + python-dev              → implementer, refactorer
  + idempotent-operations   → implementer, planner
  + secrets-management      → code-critic, implementer
  + security-testing        → code-critic
  + configuration-management → implementer

Skills to DEACTIVATE (delete from skills/; stays in _available/):
  - git-worktrees           → coordinator  (WORKTREE_ENABLED=false)

Files to update:
  • skills/{name}/                  (copy from _available/)
  • .github/agents/{agent}.agent.md (add/remove skill refs)
  • skills/INDEX.md                 (regenerate)
  • copilot-instructions.md         (regenerate Available Skills table)

Accept all? [y/n/select]
  (select = choose per skill; dismiss individual recommendations)
```

When the user chooses `select`, present each `recommended` and `optional`
skill individually:
```
  ? integration-testing (recommended — fastapi, sqlmodel detected)
    Activate? [y/n]
  ? secrets-management (recommended — fastapi, dotenv detected)
    Activate? [y/n]
```

Deactivation candidates are also presented individually in `select` mode:
```
  ? git-worktrees (deactivate — WORKTREE_ENABLED=false)
    Keep active? [y/n]
```

Dismissals are recorded in `user_overrides` (§5.1) and respected on
subsequent runs. `required` skills are not prompted — they are always
activated silently.

On confirmation, the command:
1. Copies skill folders from `_available/` to `skills/` (activate) or
   deletes from `skills/` (deactivate) — never modifies `_available/`
2. Edits each affected `.agent.md` file's `## Skills` customizable section
   (see §3.3 for deploy-safe mechanism)
3. Regenerates the agent-skill matrix in `INDEX.md`
4. Regenerates the Available Skills table in `copilot-instructions.md`
5. Writes `.af-skills-curated` sentinel with rollback snapshot (see §5)

---

## 3. Skill Activation Metadata

### 3.1 SKILL.md Frontmatter Extension

Add optional `activation` fields to each SKILL.md, nested under the
VS Code-supported `metadata` key:

```yaml
---
name: integration-testing
description: >-
  Verify multiple components work together — test containers, ...
metadata:
  activation:
    signals:
      python_packages: [fastapi, flask, django, sqlalchemy, sqlmodel, httpx]
      js_packages: [express, nestjs, next]
      file_patterns: ["**/test_integration_*.py", "**/tests/integration/**"]
      af_config:
        WORKTREE_ENABLED: true    # only for git-worktrees
    agents: [test-writer, test-critic, implementer]
    priority: recommended   # required | recommended | optional
---
```

**Signal types:**
| Signal | Source | Match Logic |
|---|---|---|
| `python_packages` | pyproject.toml, requirements.txt | ANY package present → match |
| `js_packages` | package.json | ANY package present → match |
| `file_patterns` | filesystem glob | ANY pattern has matches → match |
| `af_config` | af-env.conf key-value | ALL conditions must match |
| `imports` | source code scan | ANY import found → match |

**Priority levels:**
| Level | Behaviour |
|---|---|
| `required` | Auto-activate, no user prompt (e.g. `unit-testing` for any Python project) |
| `recommended` | Suggest with strong recommendation; activate on blanket "yes" |
| `optional` | List as available; user must explicitly opt in |

**Signal-less `required` skills:** A skill with `priority: required` and
**empty or absent `signals`** is a framework invariant — it is **always
activated** regardless of tech stack. This is the mechanism for core skills
(e.g., `unit-testing`, `error-handling`, `human-escalation`) that every
project needs. Skills with `priority: required` and populated `signals`
are activated only when a signal matches.

### 3.2 Agent Affinity

The `agents` list in activation metadata declares which agents should
reference the skill when it is active. This replaces the manual editing
of agent files and resolves the Step 8 / Step 9 contradiction: the
curation command — not the onboarding command — modifies agent files.

### 3.3 Deploy-Safe Agent Skill Sections (Section-Level Customizable Zones)

**Problem:** Agent `.agent.md` files are AF-owned (not `[customizable]`
in `.af-manifest`). Deploy overwrites them on every update, destroying
curated skill references.

**Solution:** Introduce **section-level customizable zones** using sentinel
comments, extending the existing `[customizable]` file-level concept.

Each agent file's `## Skills` section is wrapped in markers:

```markdown
## Skills

<!-- AF:DEFAULT-SKILLS:START -->
Consult these skills when relevant to the task:
- **hexagonal-architecture** (`skills/hexagonal-architecture/SKILL.md`)
- **pydantic** (`skills/pydantic/SKILL.md`)
- **error-handling** (`skills/error-handling/SKILL.md`)
<!-- AF:DEFAULT-SKILLS:END -->

<!-- AF:CURATED-SKILLS:START — DO NOT EDIT MANUALLY (managed by /af-curate-skills) -->
- **integration-testing** (`skills/integration-testing/SKILL.md`) — integration test patterns
- **python-dev** (`skills/python-dev/SKILL.md`) — Python 3.10+ idioms
<!-- AF:CURATED-SKILLS:END -->
```

**Deploy behaviour:**
- The `AF:DEFAULT-SKILLS` zone is AF-owned: deploy overwrites it with
  template content (new AF skills, updated descriptions, etc.)
- The `AF:CURATED-SKILLS` zone is project-owned: deploy **preserves** it
  entirely, treating it as a `[customizable]` section

**Deploy script changes required:**
- Extend the file-copy logic for `.agent.md` files to perform a
  **section-aware merge** instead of full-file overwrite:
  1. Parse both source and target for sentinel markers
  2. Replace `DEFAULT-SKILLS` zone from AF template
  3. Preserve `CURATED-SKILLS` zone from project
  4. If target has no `CURATED-SKILLS` zone, append nothing (clean deploy)
  5. If source adds new sentinel zones, insert them

- Register `agents/*.agent.md` as `[section-customizable]` in
  `.af-manifest` — a new annotation distinct from `[customizable]`
  (which protects the entire file)

**Phased approach:** The section-aware merge is the target architecture
but involves HIGH effort (parsing, edge cases, dual PS1/sh implementation).
To avoid blocking the curation value, the implementation is split:

- **Phase A+B (interim):** Store curated skill assignments in
  `skills/curated-assignments.json`. `/af-curate-skills` writes this file.
  After each deploy, the user re-runs `/af-curate-skills --reapply` which
  reads the JSON and regenerates agent `## Skills` sections. The deploy
  script emits a post-deploy reminder: "Curated skills detected — run
  `/af-curate-skills --reapply` to restore agent skill references."

  ```json
  {
    "version": 1,
    "activated": ["integration-testing", "python-dev", "secrets-management",
                  "security-testing", "configuration-management",
                  "idempotent-operations"],
    "deactivated": ["git-worktrees"],
    "assignments": {
      "implementer": ["integration-testing", "python-dev"],
      "test-writer": ["integration-testing"],
      "code-critic": ["secrets-management", "security-testing"],
      "coordinator": []
    }
  }
  ```

  The `activated` / `deactivated` lists track which skill **folders** to
  restore or re-delete after deploy. The `assignments` map tracks which
  **agents** reference which curated skills.

  The file is stored at `skills/curated-assignments.json` (relative to
  `.github/`).

  This JSON file is marked `[customizable]` in `.af-manifest` — deploy
  never overwrites it.

- **Phase C.5 (target):** Implement section-aware merge with sentinel
  markers (see §8 roadmap). Migrate from JSON-based reapply to automatic
  deploy-time preservation of agent skill sections. The JSON file remains
  as the source of truth but deploy reads it during the merge instead of
  requiring manual reapply for agent sections.

  **Limitation:** Phase C.5 addresses agent `.agent.md` sections only.
  Deactivation of template-default skill folders (e.g., `git-worktrees`
  shipped in the template's `skills/`) still requires `--reapply` after
  deploy, because deploy re-creates any template folder missing in the
  target. A future enhancement could teach deploy to read the JSON's
  `deactivated` list and skip re-creating those folders, but this is out
  of scope for Phase C.5.

---

## 4. Integration Points

### 4.1 Onboarding Integration

Update `/af-onboard-project` Step 8 to:

```markdown
## Step 8: Skill Curation (optional)

If the project has enough metadata to determine the tech stack (at least
one of: pyproject.toml, package.json, populated copilot-instructions.md,
or planning/documentation files with structured tech-stack sections),
invoke `/af-curate-skills` as a sub-step.

If insufficient metadata exists (truly blank project — no dependency files,
no documentation, no README with tech stack info), skip with:
"⚠️ Skipping skill curation — no tech stack metadata found. Run
`/af-curate-skills` later when the project has dependency files or
documentation describing the intended tech stack."
```

Remove the contradiction with Step 9 by **delegating activation to
`/af-curate-skills`** rather than doing it inline.

### 4.2 Deploy Integration

Add a `--curate-skills` flag to `deploy.ps1` / `deploy.sh`:

```powershell
# deploy.ps1
[switch]$CurateSkills   # Run /af-curate-skills after deployment
```

When set, the deploy script outputs:
```
  Post-deploy: Run /af-curate-skills in Copilot Chat to adapt skills.
```

The deploy script itself does NOT modify skills (deterministic file copy
only). It signals the user to run the curation command in Copilot Chat.

### 4.3 Stale Skill Check Enhancement

The existing deploy stale-skill detection (in deploy.ps1)
should be extended to also warn about:
- **Missing activations:** skills that match the tech stack but aren't active
- **Unnecessary activations:** active skills that don't match any signal

This makes the passive warning actionable: "Run `/af-curate-skills` to
resolve X skill mismatches."

### 4.4 Coordinator Awareness

The coordinator's workflow selection (Step 0) can check if `/af-curate-skills`
has ever been run (presence of a `.af-skills-curated` sentinel file with
a timestamp). If not, and the project has metadata, the coordinator emits
a one-time reminder:

```
ℹ️ Skill library has not been curated for this project.
  Consider running /af-curate-skills to optimise agent skill access.
```

---

## 5. Standalone `/af-curate-skills` Prompt Specification

```yaml
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
---
```

### Steps

1. Read `af-env.conf` for `SRC_DIR`, `PROJECT_LANGUAGE`, feature flags
2. Parse dependency files (pyproject.toml, package.json)
3. Scan planning/documentation files for structured tech-stack sections
   (see §2.2 Phase 1, source 6 — structured markers only)
4. Scan `skills/_available/` and `skills/` for `metadata.activation` blocks
5. Match tech-stack signals → produce activate/deactivate lists,
   applying confidence gating (see §2.2 confidence matrix)
6. Present summary table with affected files
7. On user confirmation: execute copies/deletes, agent edits, INDEX regeneration
8. Write `.af-skills-curated` sentinel with rollback snapshot (see below)

### Dry-Run Mode

When `--dry-run` is specified, display the full change plan but do not
write any files. Useful for CI or review.

### Reapply Mode (Phase A+B interim)

When `--reapply` is specified:

1. Read `skills/curated-assignments.json` for skill state and agent assignments
2. Re-copy `activated` skill folders from `_available/` to `skills/`
   (deploy may have updated the `_available/` copies — that's fine)
   **Note:** This overwrites any local modifications to curated skill copies.
   Users who customise skill content should re-apply their edits after
   reapply, or maintain customisations in a project-specific skill addendum
   rather than editing the AF-owned SKILL.md.
3. Re-delete `deactivated` skill folders from `skills/`
   (deploy re-creates template defaults; reapply undoes this)
4. Regenerate `## Skills` sections in all listed agent `.agent.md` files
   (add `CURATED-SKILLS` entries matching the JSON assignments)
5. Regenerate `INDEX.md` and `copilot-instructions.md` Available Skills table
6. No tech-stack re-discovery — uses the stored assignments as-is
7. No user confirmation prompt — this is a deterministic replay

This mode exists to restore curated skill state after a deploy overwrite.
After Phase C.5, `--reapply` remains necessary only for skill folder
activation/deactivation (steps 2–3); agent section regeneration (step 4)
becomes a no-op because deploy preserves `CURATED-SKILLS` zones directly.

**Why re-delete matters:** Deploy never deletes target files. When
`/af-curate-skills` deactivates a template default (e.g., `skills/git-worktrees/`),
the next deploy sees the template has that folder but the target doesn't,
and re-creates it. Without re-deletion, INDEX and instructions regeneration
would list the zombie skill as active again.

### Rollback Mode

When `--rollback` is specified:

1. Read `.af-skills-curated` for the previous state snapshot
2. Restore skill folders to their pre-curation locations
3. Restore agent `## Skills` sections from the saved snapshot
4. Regenerate `INDEX.md` and `copilot-instructions.md`

The sentinel file stores the full pre-curation state (see §5.1).

**Rollback limitation:** Rollback restores the *set* of active skills but
uses current file contents from `_available/`. If deploy updated a skill
between curation and rollback, the restored copy will be the updated
version, not the exact previous version.

---

## 5.1 Sentinel File Format

The `.af-skills-curated` file stores curation state for rollback and
re-run intelligence:

```yaml
# Auto-generated by /af-curate-skills — do not edit manually
version: 1
last_curated: 2026-04-29T14:30:00Z
tech_stack_profile:
  python_packages: [fastapi, sqlmodel, alembic, pytest, hypothesis]
  js_packages: [react, vite, typescript]
  af_config: {WORKTREE_ENABLED: false}
  confidence_sources:
    fastapi: high   # from pyproject.toml
    react: low      # from docs/plan.md structured section

activated:
  - name: integration-testing
    agents: [test-writer, test-critic, implementer]
    confidence: high
  - name: python-dev
    agents: [implementer, refactorer]
    confidence: high

deactivated:
  - name: git-worktrees
    agents: [coordinator]
    reason: "WORKTREE_ENABLED=false"

user_overrides:
  - name: performance-testing
    action: dismissed    # user said "no" to recommendation
    reason: "not needed yet"

previous_state:
  active_skills: [code-review, dependency-management, design-patterns, ...]
  agent_skill_assignments:
    implementer: [hexagonal-architecture, pydantic, error-handling]
    coordinator: [git-worktrees]
    test-writer: [unit-testing, property-testing]
```

**Note:** `previous_state.agent_skill_assignments` stores structured skill
name lists, not raw Markdown. The Markdown representation is regenerated
from skill names + SKILL.md descriptions during rollback. This avoids
fragile multi-line Markdown embedded in YAML (quoting issues with `*`,
`:`, `|` in Markdown bullets).

The `previous_state` block enables rollback. The `user_overrides` block
prevents re-suggesting dismissed skills on subsequent runs — the user's
"no" is remembered until they explicitly re-run with `--reset-overrides`.

### 5.2 State File Lifecycle

The plan introduces **two** persistence files. Their purposes are distinct:

| File | Purpose | Created | `[customizable]`? |
|---|---|---|---|
| `skills/curated-assignments.json` | Declarative skill state (activated/deactivated lists) + agent→skill map. Deploy-safe persistence. Input for `--reapply`. | Phase A+B | Yes |
| `.github/.af-skills-curated` | Operational curation metadata: tech profile, confidence data, user overrides, rollback snapshot. | Phase A+B (alongside JSON) | No (AF-internal) |

**Source of truth:** `skills/curated-assignments.json` is the authoritative
source for *which skills are activated/deactivated and assigned to which
agents*. `.af-skills-curated` is the
authoritative source for *how that assignment was decided* (confidence,
overrides, previous state). `/af-curate-skills` writes both files
atomically. `--reapply` reads only the JSON. `--rollback` reads only the
sentinel (but updates both on restore).

After Phase C.5 (section-aware deploy merge), the JSON remains as the
deploy-time input. `--reapply` becomes a **partial** no-op: agent section
regeneration is handled by deploy, but skill folder activation/deactivation
still requires `--reapply` (deploy re-creates template defaults that were
deactivated — see §3.3 Phase C.5 limitation).

---

## 6. INDEX.md Auto-Generation

Replace the manually maintained `INDEX.md` with a **generated** file.
The generation script (`.github/scripts/generate-skill-index.py`) reads:

1. All `skills/*/SKILL.md` frontmatter → active skills table
2. All `skills/_available/*/SKILL.md` frontmatter → available skills table
3. Agent `.agent.md` `## Skills` sections → agent-skill matrix

Output: regenerated `INDEX.md` with:
- Active Skills table (name, description, agents)
- Available Skills table (name, description, activation signals)
- Agent-Skill Matrix (cross-reference grid)

This script is called by `/af-curate-skills` after every activation change,
and can be run standalone (`python .github/scripts/generate-skill-index.py`).

---

## 7. Edge Cases

| Scenario | Behaviour |
|---|---|
| Blank project (no dependency files, no docs, no README) | Skip with message; keep default skill set |
| Pre-implementation project (planning docs only) | Extract tech stack from structured sections with `low` confidence; apply confidence gating matrix (§2.2) |
| Planning doc mentions rejected alternative ("considered Flask") | Ignored — only structured declarations count (§2.2 source 6 markers) |
| `copilot-instructions.md` was auto-filled from planning docs | Confidence is `medium` by default; downgraded to `low` if `<!-- af:auto-filled-from-docs -->` marker is present (see §2.2) |
| Skill has no activation metadata | Never auto-activated; only manual. Listed in dry-run output as "no signals" |
| Default-active skill (shipped in `skills/`) without metadata | Kept active. Deactivation requires metadata with `af_config` signals (e.g., `git-worktrees` needs `WORKTREE_ENABLED: true`) — AF defaults must have metadata added in Phase B |
| Skill in `_available/` was customised by user | Detect via hash comparison; warn before overwriting |
| Agent already references a skill being deactivated | Remove from `CURATED-SKILLS` zone; warn user |
| Multiple skills match same signal | Activate all; no conflict |
| Project uses both Python and JS | Match signals from both ecosystems |
| Skill activation fails (permission error) | Report failure; continue with remaining skills |
| Re-running after previous curation | Diff against current state; respect `user_overrides` from sentinel |
| User previously dismissed a skill | Not re-suggested unless `--reset-overrides` flag is used |
| Deploy ran after curation (Phase A+B) | Deploy overwrites agent files. Run `--reapply` to restore skill folders and agent skill sections. |
| Deploy ran after curation (Phase C.5+) | `DEFAULT-SKILLS` zone updated; `CURATED-SKILLS` zone preserved (§3.3). Run `--reapply` for deactivated skill folder re-deletion only. |
| Rollback requested but no sentinel exists | Error message: "No previous curation found" |
| `--reapply` with no `curated-assignments.json` | Error message: "No curated assignments found. Run `/af-curate-skills` first." |
| Deploy re-creates a deactivated template-default skill folder | `--reapply` re-deletes it using the JSON `deactivated` list (see §5 Reapply Mode) |
| Agent file has no `## Skills` section (e.g. coordinator) | `/af-curate-skills` inserts a minimal `## Skills` section with sentinel markers before adding curated entries. `--reapply` skips agents not listed in JSON. |

---

## 8. Implementation Priority

| Phase | Scope | Effort | Impact |
|---|---|---|---|
| **Phase A+B** | `/af-curate-skills` prompt (including `--reapply`, `--dry-run`, `--rollback` modes) + `curated-assignments.json` mechanism + deploy post-deploy reminder + activation metadata in 10 high-priority SKILL.md files (see list below) + extend `validate-skills.py` for activation schema | MEDIUM | HIGH — delivers the full curation loop from discovery to deploy-safe persistence |
| **Phase B.5** | Activation metadata on all 17 default-active skills (enables deactivation of irrelevant defaults like `git-worktrees`) | LOW | HIGH — completes the deactivation path |
| **Phase C** | Activation metadata in remaining `_available/` SKILL.md files | LOW | MEDIUM — completes the signal coverage |
| **Phase C.5** | Section-aware deploy merge (§3.3 target: sentinel markers, `[section-customizable]` annotation, dual PS1/sh implementation) — replaces JSON-based reapply | HIGH | MEDIUM — eliminates manual reapply after deploy |
| **Phase D** | `generate-skill-index.py` auto-generation | LOW | MEDIUM — eliminates INDEX drift |
| **Phase E** | Deploy integration (`--curate-skills` post-deploy reminder) | LOW | MEDIUM — streamlines workflow |
| **Phase F** | Coordinator awareness (sentinel + reminder) | LOW | LOW — reduces missed curation |

### Phase A+B: Initial 10 SKILL.md Files for Activation Metadata

These skills cover the most common tech stacks and include all framework
invariants:

| # | Skill | Priority | Rationale |
|---|---|---|---|
| 1 | `unit-testing` | `required` (no signals) | Framework invariant — every project needs tests |
| 2 | `error-handling` | `required` (no signals) | Framework invariant — every project needs error handling |
| 3 | `human-escalation` | `required` (no signals) | Framework invariant — escalation protocol always needed |
| 4 | `integration-testing` | `recommended` | Signals: fastapi, flask, django, sqlalchemy, sqlmodel, httpx |
| 5 | `python-dev` | `recommended` | Signals: any Python project (presence of pyproject.toml or .py files) |
| 6 | `idempotent-operations` | `recommended` | Signals: fastapi, celery, sqlalchemy (retry/upsert patterns) |
| 7 | `secrets-management` | `recommended` | Signals: fastapi, flask, django, dotenv, any API client lib |
| 8 | `security-testing` | `recommended` | Signals: fastapi, flask, django (web attack surface) |
| 9 | `configuration-management` | `recommended` | Signals: dotenv, pydantic-settings, dynaconf |
| 10 | `git-worktrees` | `recommended` | Signals: `af_config: {WORKTREE_ENABLED: true}` |

**Why A+B as a single phase:** The JSON mechanism (`--reapply`, deploy
reminder) depends on the `/af-curate-skills` prompt to produce the JSON file
and on SKILL.md activation metadata to match against. Shipping the JSON
format without its producer or consumers has no standalone value. Merging
them into one deliverable eliminates a dead interim and ships the full
loop in one increment.

**Why not "heuristics-only prompt":** A prompt with hardcoded matching
rules would need to be rewritten when skills declare their own signals.
Starting with sparse metadata (10 skills) gives the same immediate value
with zero throwaway work.

### Phase A+B: `validate-skills.py` Extension

Extend the existing validation script to verify activation metadata
(nested under `metadata.activation` in SKILL.md frontmatter):
- `priority` must be one of: `required`, `recommended`, `optional`
- `agents` values must match existing `.agent.md` filenames (minus extension)
- `signals` keys must be from the known set: `python_packages`,
  `js_packages`, `file_patterns`, `af_config`, `imports`
- Warn on `priority: required` with non-empty signals (unusual combination)

---

## 9. Relation to Existing Features

| Feature | Relationship |
|---|---|
| `/af-find-skill` | **Complementary.** Discovery (read-only) vs curation (read-write). `/af-find-skill` stays as-is for ad-hoc queries. |
| `/af-onboard-project` Step 8 | **Replaced by** delegation to `/af-curate-skills`. Step 8 becomes: "if metadata exists, run `/af-curate-skills`." |
| `/af-validate-framework` | **Extended.** Add a check: "skills active but no activation signal matches tech stack." |
| Deploy stale-skill warning | **Extended.** Add tech-stack mismatch warnings alongside staleness warnings. |
| Knowledge graph idea | **Feeds into.** Skill activation metadata becomes edges in the knowledge graph (`ACTIVATES_FOR` relationship). |
| `/af-audit-config` | **Extended.** Include skill-stack alignment in the config audit report. |

---

## 10. Resolved Decisions

| # | Question | Decision | Rationale |
|---|---|---|---|
| 1 | Should core skills be un-deactivatable? | **Yes — mark as `priority: required`.** Skills like `unit-testing`, `error-handling`, `human-escalation` get `required` priority in their activation metadata. `/af-curate-skills` auto-activates them regardless of tech stack and warns if the user tries to deactivate. | These skills are framework-level requirements, not project-specific. |
| 2 | Modify `## Skills` directly or use YAML frontmatter? | **Markdown section with sentinel markers** (§3.3). | Follows existing `.agent.md` structure. Agents already parse `## Skills` as Markdown. No YAML schema change needed. |
| 3 | How to survive deploy overwrites? | **Phase A+B:** `skills/curated-assignments.json` (marked `[customizable]`) + `--reapply` mode for skill folders and agent sections. **Phase C.5:** Section-level customizable zones with sentinel markers (§3.3) for agent sections only; `--reapply` still needed for deactivated skill folder re-deletion (see §3.3 Phase C.5 limitation). | JSON + reapply ships with the prompt in a single deliverable. Sentinel merge is the target for agent sections but HIGH effort — deferred to avoid blocking value delivery. |
| 4 | Skill versioning: symlink or snapshot? | **Snapshot (copy).** Activated skills are copies, not symlinks. Deploy's stale-skill warning already detects when `_available/` has a newer version. User re-runs `/af-curate-skills` or manually re-copies to update. | Symlinks are fragile on Windows. Copies are deterministic and work with the existing stale-skill detection. |

## 11. Remaining Open Questions

1. **Inter-skill dependencies:** Some skills assume knowledge from others
   (e.g., `security-testing` assumes `secure-coding` concepts). Should
   SKILL.md declare `depends_on: [secure-coding]`? If so, `/af-curate-skills`
   would auto-activate dependencies when activating a skill. Deferred to
   a future iteration — noted here as a known gap. For now, the agent-skill
   affinity matrix implicitly handles this (agents that need
   `security-testing` also reference `secure-coding`).

2. **Multi-language skill sets:** The current signal types cover Python and
   JS. If AF expands to Rust, Go, or C#, the activation metadata needs
   new signal types (`rust_crates`, `go_modules`, etc.). The schema should
   be extensible but this is not a concern for the initial implementation.
