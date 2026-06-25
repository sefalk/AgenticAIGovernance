# Copilot Agent Team Framework

**v1.17.0** · [Changelog](CHANGELOG.md) · [Troubleshooting](.github/TROUBLESHOOTING.md) · [Interactive Map](agent-framework-map.v2.html)

> Drop `.github/` into any Python project to get an **autonomous**, multi-agent
> TDD workflow with quality gates, traceability, and deterministic enforcement hooks.

## Why Use This

You describe a task. The framework runs the full pipeline — planning, failing
tests, implementation, refactoring, code review, documentation — autonomously.
Critics review every output; hooks enforce quality gates with real code, not
suggestions. You stay in control through mandatory escalation points.

- **14 specialised agents** (1 coordinator + 10 core workers + 3 optional ADO workers) with isolated contexts
- **Test-Driven Development** enforced as separate Red → Green → Refactor phases
- **Deterministic hooks** run pytest, scan for secrets, block destructive commands
- **Maker-Checker pattern** — every agent's output is reviewed by a critic
- **Escalation, not surprise** — the coordinator asks you when it needs domain input

## Prerequisites

- VS Code with GitHub Copilot extension (agent mode enabled)
- Python 3.10+ with `pytest` and `hypothesis` (for property-based tests)
- `ruff` (required for refactorer linting hard gate)
- Optional: `radon` (complexity), `mutmut` (mutation testing)
- Coordinator auto-bootstrap for missing `.venv` is configurable via
  `.github/af-env.conf` (`PY_ENV_BOOTSTRAP=ask|always|off`)

## Quick Setup

1. **Place** the `_agent-framework/` directory in your project root
   (or clone it as a subdirectory).
2. **Run `/setup-project`** in Copilot Chat — this runs the full pipeline
   (deploy → onboard → curate skills) in one step. Review the combined
   summary and confirm once.
3. **Start using** — open Copilot Chat and type `@coordinator <your task>`,
   or use `/tdd-feature`, `/quick-fix`, or `/review-code` slash commands.

<details>
<summary><strong>Manual setup</strong> (step-by-step alternative)</summary>

If you prefer running each phase separately:

1. **Deploy:** Run the deploy script:
   ```powershell
   # Windows — preview first, then deploy
   .\_agent-framework\deploy.ps1 -DryRun
   .\_agent-framework\deploy.ps1
   ```
   ```bash
   # macOS / Linux
   ./_agent-framework/deploy.sh --dry-run
   ./_agent-framework/deploy.sh
   ```
2. **Onboard:** Run `/onboard-project` in Copilot Chat — analyses your
   codebase and auto-fills configuration.
3. **Curate skills:** Run `/curate-skills` — matches skills to your tech
   stack and activates/deactivates them.

</details>

### Updating the AF

Re-run the deploy script after pulling AF updates. Customizable files
(`copilot-instructions.md`, `architecture.instructions.md`) are protected —
they won't be overwritten unless you use `-Force` / `--force`.

Use `-Diff` / `--diff` to compare source vs deployed before updating:
```powershell
.\_agent-framework\deploy.ps1 -Diff
```

### Recommended Deployment Policy

Use two deployment modes to balance speed and safety:

1. **Developer iteration (fast, non-blocking checks)**
  ```powershell
  .\_agent-framework\deploy.ps1 -Preflight -PreflightMode quick
  ```
  ```bash
  ./_agent-framework/deploy.sh --preflight --preflight-mode quick
  ```

2. **Release handoff (hard gate, blocks on failed checks)**
  ```powershell
  .\_agent-framework\deploy.ps1 -RequirePreflight -PreflightMode full
  ```
  ```bash
  ./_agent-framework/deploy.sh --require-preflight --preflight-mode full
  ```

**Backup retention:**
- Deploy now auto-prunes stale `.af-backup-*` folders older than 14 days.
- Team default can be set in `.github/af-env.conf` via `BACKUP_PRUNE_DAYS=<N>`.
- Override via `-BackupPruneDays <N>` / `--backup-prune-days <N>`.
- Set `0` to disable pruning.

**Git worktree configuration:**
- Agent workflows run in isolated **git worktrees** to enable parallel agent work.
- Disable via `WORKTREE_ENABLED=false` in `.github/af-env.conf` (useful for CI/CD or single-threaded environments).
- Worktree paths default to auto-computed project-scoped folder:
  ```
  WORKTREE_DIR=../{git_repo_folder_name}_worktrees
  ```
  Example: `MP Field Data Analysis CT` → `../MP Field Data Analysis CT_worktrees`
- Override `WORKTREE_DIR` explicitly if needed (sibling paths, absolute paths, or inside-repo `.worktrees/`).
- Configure Python mode via `WORKTREE_VENV_MODE=shared|isolated`:
  - `shared` (default): worktree uses parent repo `.venv` via explicit interpreter path.
  - `isolated`: worktree creates its own `.venv` (use for dependency-changing tasks).
- **VS Code integration:** Worktree folder is automatically added to your `.code-workspace` file,
  making it visible in Explorer as a separate workspace root. Workspace is cleaned up on worktree removal.
- **Interpreter prompt avoidance:** worktree bootstrap writes `python.defaultInterpreterPath`
  into worktree settings, so VS Code should not repeatedly ask to select/create an interpreter.

**Preflight profiles:**
- `quick`: hook integration tests, skills validation, tool audit, notebook git-filter alignment (`NOTEBOOKS_ENABLED=true` projects)
- `full`: quick + worktree integration tests

<details>
<summary>Manual file copy (if you prefer not to use any script or prompt)</summary>

1. **Copy AF-owned directories** from `_agent-framework/.github/` into your
   project's `.github/`. AF owns: `agents/`, `hooks/`, `instructions/`,
   `prompts/`, `skills/`, `templates/`, `logs/`, `retros/`, plus
   `MANIFEST.md`, `GOVERNANCE.md`, `TROUBLESHOOTING.md`, and
   `copilot-instructions.md`. See `.github/.af-manifest` for the full list.
   **Do NOT overwrite** existing non-AF files.
2. **Copy** `.vscode/toolsets.jsonc` into your `.vscode/` folder.
3. **Run `/onboard-project`** to auto-fill configuration, then
   `/curate-skills` to match skills to your tech stack.

</details>

## Your First Week

> Don't try to use the full pipeline from day one. Start small.

| Week | What to Do |
|---|---|
| **1** | Use `@coordinator` for small tasks — try `/quick-fix` or `/trivial-fix` |
| **2** | Run a feature with `/tdd-feature`. Watch the subagent calls in the chat |
| **3** | Customise `copilot-instructions.md` and `architecture.instructions.md` for your project |
| **4** | Review workflow logs in `.github/logs/` and retro snippets in `retros/auto/` |

## How It Works

### The Coordinator Pattern

The **coordinator** is the only agent you interact with. It receives your task
and autonomously runs the full workflow by invoking workers as **subagents**:

```
You → @coordinator
        ├─→ researcher (subagent)          → returns research brief (conditional)
        ├─→ compliance-checker (subagent)   → returns pre-flight status
        ├─→ planner (subagent)              → returns plan
        ├─→ test-writer (subagent)          → returns failing tests
        ├─→ test-critic (subagent)          → returns APPROVED/REJECTED
        ├─→ implementer (subagent)          → returns passing code
        ├─→ refactorer (subagent)           → returns cleaned code
        ├─→ code-critic (subagent)          → returns APPROVED/REJECTED
        ├─→ documenter (subagent)           → returns workflow log
        ├─→ ado-work-item-manager (optional)→ provider sync for work items
        ├─→ ado-wiki-manager (optional)      → provider sync for wiki updates
        ├─→ ado-pr-manager (optional)        → request-based integration (PR)
        └─→ compliance-checker (subagent)   → returns post-flight status
```

Each subagent runs in its **own isolated context window** — it receives only
the task prompt, does its work, and returns a summary. The coordinator manages
the flow, handles retries, and escalates to you when needed.

### What Happens Under the Hood

0. The **researcher** fetches external docs (conditional — only for external APIs/libs)
0b. The **compliance-checker** runs pre-flight checks (branch, plan dir)
1. The coordinator invokes the **planner** subagent to decompose your task
2. The **test-writer** creates failing tests (Red phase)
3. The **test-critic** reviews test quality → APPROVED or REJECTED (retry)
4. The **implementer** makes tests pass (Green phase)
5. The **refactorer** cleans up without changing behaviour
6. The **code-critic** reviews everything → APPROVED or REJECTED (retry)
7. The **documenter** writes the workflow log
7b. The **compliance-checker** runs post-flight checks (plan, log, retro)

**Rejections** trigger automatic retries (up to 2). After a 3rd rejection,
the **arbiter** mediates or the workflow escalates to you.

### Workflow Modes

The coordinator picks the right workflow for the task:

| Task Type | Workflow | Agents Used | Slash Command |
|---|---|---|---|
| New feature | Full TDD | All 10 workers | `/tdd-feature` |
| Small bug fix | Quick Fix | planner → implementer → code-critic → documenter | `/quick-fix` |
| Mechanical fix | Trivial Fix | implementer → code-critic → documenter | `/trivial-fix` |
| Code review | Review Only | code-critic | `/review-code` |
| Planning | Plan Only | planner | — |

<details>
<summary><strong>Model Selection (v1.18.6+)</strong> (click to expand)</summary>

As of v1.18.6, agents no longer have hardcoded model lists. Instead:

- **All agents** use the model **selected by the user** in Copilot Chat
- **Fallback:** If no model is explicitly selected, VS Code uses its default
- **No maintenance burden:** Model updates require zero agent edits — they're
  configured by the user or automatically by VS Code availability

**Legacy reference (pre-v1.18.6):** Prior versions had tiered model lists
(Tier 1: Opus/Sonnet/GPT-5; Tier 2: Sonnet/GPT-5/GPT-4; Tier 3: Sonnet/GPT-4/Haiku).
This design was replaced for simplicity and maintainability.

**Rationale:** Company model updates happen frequently. Hardcoding models
in 13 agent files created maintenance overhead. Dynamic model selection via
user preference is simpler and future-proof.

</details>

## When You're Involved

The coordinator runs autonomously but **escalates** to you for:

- 3rd rejection by any critic (after 2 retries)
- Ambiguous requirements needing domain expertise
- Large plans (6+ subtasks) requiring approval
- New architectural elements (ports, adapters)
- Destructive or security-sensitive actions

Everything else is fully autonomous.

<details>
<summary><strong>File Map</strong> (click to expand)</summary>

```
deploy.ps1                                 # AF deploy script (Windows)
deploy.sh                                  # AF deploy script (macOS/Linux)
VERSION                                    # Semver version of the framework
CHANGELOG.md                               # Release history (Keep a Changelog format)
.github/
├── copilot-instructions.md                # Global project instructions (customise!)
├── MANIFEST.md                            # Governing principles for the agent team
├── GOVERNANCE.md                          # Governance model and AI provenance rules
├── TROUBLESHOOTING.md                     # Common issues and diagnostic steps
├── .af-manifest                           # AF-owned file registry (controls deploy)
├── agents/                                # 14 agent definitions (includes optional ADO workers)
│   ├── coordinator.agent.md               # 🎯 Main entry point (user-facing)
│   ├── planner.agent.md                   # Worker: task decomposer
│   ├── test-writer.agent.md               # Worker: failing tests (Red phase)
│   ├── test-critic.agent.md               # Worker: test quality review
│   ├── implementer.agent.md               # Worker: passing code (Green phase)
│   ├── refactorer.agent.md                # Worker: code cleanup (Refactor phase)
│   ├── code-critic.agent.md               # Worker: architecture + metrics review
│   ├── arbiter.agent.md                   # Worker: dispute resolution
│   ├── documenter.agent.md                # Worker: workflow logging
│   ├── researcher.agent.md                # Worker: external research & domain expertise
│   ├── compliance-checker.agent.md        # Worker: workflow compliance watchdog (bookends)
│   ├── ado-work-item-manager.agent.md     # Optional worker: Azure DevOps work item lifecycle
│   ├── ado-wiki-manager.agent.md          # Optional worker: Azure DevOps wiki lifecycle
│   └── ado-pr-manager.agent.md            # Optional worker: Azure DevOps pull request integration
├── hooks/                                 # Agent hooks (deterministic enforcement)
│   ├── README.md                          # Hook documentation and templates
│   ├── agent-hooks.json                   # Active hooks: 5 total hook commands
│   ├── quality-gates.json.template        # Reference: example hook patterns
│   └── scripts/                           # Hook implementation scripts
│       ├── session-context.ps1            # SessionStart: inject git/env context (Windows)
│       ├── session-context.sh             # SessionStart: inject git/env context (Unix)
│       ├── block-dangerous.ps1            # PreToolUse: catch destructive commands (Windows)
│       ├── block-dangerous.sh             # PreToolUse: catch destructive commands (Unix)
│       ├── scan-secrets.ps1               # PostToolUse: detect hardcoded secrets (Windows)
│       ├── scan-secrets.sh                # PostToolUse: detect hardcoded secrets (Unix)
│       ├── stop-tests.ps1                 # Stop: run test suite gate (Windows)
│       ├── stop-tests.sh                  # Stop: run test suite gate (Unix)
│       ├── implementer-stop.ps1           # SubagentStop: Green phase gate (Windows)
│       ├── implementer-stop.sh            # SubagentStop: Green phase gate (Unix)
│       ├── test-writer-stop.ps1           # SubagentStop: Red phase gate (Windows)
│       ├── test-writer-stop.sh            # SubagentStop: Red phase gate (Unix)
│       ├── test-writer-pretooluse.ps1     # PreToolUse: block production code edits (Windows)
│       ├── test-writer-pretooluse.sh      # PreToolUse: block production code edits (Unix)
│       ├── refactorer-stop.ps1            # SubagentStop: Refactor phase gate (Windows)
│       ├── refactorer-stop.sh             # SubagentStop: Refactor phase gate (Unix)
│       ├── refactorer-pretooluse.ps1      # PreToolUse: block file creation (Windows)
│       ├── refactorer-pretooluse.sh       # PreToolUse: block file creation (Unix)
│       ├── documenter-stop.ps1            # SubagentStop: artifact existence gate (Windows)
│       └── documenter-stop.sh             # SubagentStop: artifact existence gate (Unix)
├── instructions/                          # Auto-applied instruction files
│   ├── architecture.instructions.md       # Architecture map (customise!)
│   ├── copilot-authoring.instructions.md  # Rules for authoring copilot files
│   ├── git-workflow.instructions.md       # Branch lifecycle, atomic commits, plan files
│   ├── provenance.instructions.md         # AI traceability markers
│   ├── quality-gates.instructions.md      # Gate taxonomy, tiers, per-agent exit gates
│   └── testing.instructions.md            # TDD and test conventions
├── templates/                             # Structured document templates
│   ├── PLAN.md                            # Plan template (persisted as {type}-{date}-{slug}.md in docs/plans/)
│   ├── INVESTIGATION.md                   # Quick Fix investigation template
│   └── WIP.md                             # WIP checkpoint template (docs/plans/WIP.md)
├── skills/                                # On-demand skill references (38 skills)
│   ├── metrics/SKILL.md                   # Coverage, complexity, mutation testing
│   ├── property-testing/SKILL.md          # Hypothesis property-based testing
│   ├── INDEX.md                           # Auto-generated skill index with agent matrix
│   └── ... (35 more)                      # See skills/ directory for full list
├── prompts/                               # Reusable slash commands
│   ├── setup-project.prompt.md            # /setup-project → deploy + onboard + curate (all-in-one)
│   ├── onboard-project.prompt.md          # /onboard-project → auto-fill config
│   ├── curate-skills.prompt.md            # /curate-skills → match skills to tech stack
│   ├── find-skill.prompt.md               # /find-skill → search skill library by topic
│   ├── audit-config.prompt.md             # /audit-config → detect config drift
│   ├── validate-framework.prompt.md       # /validate-framework → AF integrity scan
│   ├── simulate.prompt.md                 # /simulate → dry-run workflow prediction
│   ├── draft-pr-description.prompt.md     # /draft-pr-description → PR text from artifacts
│   ├── retro-summary.prompt.md            # /retro-summary → pull recent workflow lessons
│   ├── resume.prompt.md                   # /resume → discover paused workflows
│   ├── tdd-feature.prompt.md              # /tdd-feature → full TDD pipeline
│   ├── quick-fix.prompt.md                # /quick-fix → implement + review
│   ├── trivial-fix.prompt.md              # /trivial-fix → mechanical fix
│   ├── review-code.prompt.md              # /review-code → code review only
│   ├── smoke-test.prompt.md               # /smoke-test → verify framework health
│   └── workflow-summary.prompt.md         # /workflow-summary → log summary
├── logs/                                  # Workflow handoff logs (gitignored)
│   └── README.md
└── retros/                                # Retrospective documents
    └── README.md
```

</details>

<details>
<summary><strong>Tool Configuration</strong> (click to expand)</summary>

Agents list their permitted tools individually in their `tools:` YAML
frontmatter using the `namespace/tool` format:

```yaml
tools:
  - search/codebase
  - search/textSearch
  - read/readFile
  - edit/editFiles
  - execute/runInTerminal
  - pylance-mcp-server/pylanceFileSyntaxErrors
```

Each agent has a minimal, explicitly scoped tool list. Read-only agents
(planner, critics, compliance-checker) have no edit or execute tools.

VS Code also supports **named tool sets** defined in `.vscode/tool-sets.jsonc`.
The project defines shared sets (`reader`, `dev`, `python-analysis`, etc.)
that can be referenced by name instead of listing tools individually.

</details>

## Agent Hooks (Deterministic Enforcement)

Hooks execute **your code** at lifecycle points — deterministic, not AI-guided.
Unlike instructions ("please run the formatter"), hooks guarantee execution.

### Ready-to-Use Hooks (active in `agent-hooks.json`)

| Hook | Event | What It Does |
|---|---|---|
| **Session Context** | `SessionStart` | Injects git branch, last commit, Python version into every session |
| **Safety Gate** | `PreToolUse` | Prompts for confirmation on `rm -rf`, `DROP TABLE`, `--force`, etc. |
| **Secret Scan** | `PostToolUse` | Scans edited files for hardcoded secrets (gitleaks or regex fallback) |
| **Test Gate** | `Stop` | Runs `pytest tests/ -q --tb=line` before session ends |

All five hooks work out of the box — no configuration needed.
`quality-gates.json.template` is kept as a reference for additional hook patterns.

### Agent-Scoped Hooks (in agent YAML frontmatter)

In addition to global hooks, individual agents have **scoped hooks** defined
in their `.agent.md` YAML frontmatter. These fire only when that agent is active:

| Hook | Agent | Event | What It Does |
|---|---|---|---|
| **Green Gate** | implementer | `SubagentStop` | Blocks if tests fail after implementation |
| **Red Gate** | test-writer | `SubagentStop` | Blocks if all tests pass (tests must FAIL) |
| **TDD Isolation** | test-writer | `PreToolUse` | Blocks edits to production code |
| **Refactor Gate** | refactorer | `SubagentStop` | Blocks if tests fail or new files created |
| **No New Files** | refactorer | `PreToolUse` | Blocks `createFile`/`createDirectory` |
| **Artifact Gate** | documenter | `SubagentStop` | Blocks if workflow log or retro is missing |

Requires `chat.useCustomAgentHooks: true` in `.vscode/settings.json`.

Configure global hooks via `.github/hooks/*.json`.
See `hooks/README.md` for detailed format and templates.

## Slash Commands

Type `/` in chat to access workflow shortcuts:

### Workflow Entry Points (route to coordinator)

| Command | What It Does |
|---|---|
| `/tdd-feature` | Full TDD pipeline via coordinator |
| `/quick-fix` | Implement + review for small fixes |
| `/trivial-fix` | Mechanical fix (typo, rename, config) — no planning |
| `/review-code` | Code review only (no changes) |
| `/resume` | Find paused workflows and resume via coordinator |
| `/smoke-test` | Run canned task through full pipeline to verify framework health |

These pre-select a workflow and delegate to the coordinator. You can
also talk to `@coordinator` directly — it selects the right workflow
from your description.

### Post-Workflow Reporting (coordinator-assisted)

| Command | What It Does |
|---|---|
| `/workflow-summary` | Generate summary from workflow log |
| `/draft-pr-description` | Generate PR text from PLAN.md + log |

### Standalone Utilities (no coordinator needed)

| Command | What It Does |
|---|---|
| `/setup-project` | **Full setup** — deploy + onboard + curate skills in one step |
| `/onboard-project` | Analyse project and auto-fill AF config (onboarding only) |
| `/curate-skills` | Match skills to tech stack, activate/deactivate |
| `/audit-config` | Detect drift between AF config and project |
| `/validate-framework` | Scan AF files for internal consistency |
| `/find-skill` | Search the skill library by topic |
| `/simulate` | Dry-run a task without executing |
| `/retro-summary` | Aggregate past workflow lessons |

Standalone utilities run independently — the coordinator doesn't invoke
them. Use them for framework maintenance and discovery.

## Using Workers Standalone (Optional)

Workers are hidden from the agents dropdown by default (`user-invocable: false`).
To use a worker directly (e.g., just the planner or just the code-critic),
edit its `.agent.md` file and change:

```yaml
user-invocable: true
```

Then you can invoke it directly: `@planner Analyse my module structure`.

To add handoff buttons for standalone workers, add a `handoffs:` section
to the worker's YAML frontmatter.

## Key Principles (Summary)

1. **Autonomous by Default** — Coordinator runs the full pipeline via subagents
2. **Test-Driven Development** — Red → Green → Refactor as separate subagent steps
3. **Maker-Checker** — Every output is reviewed by a critic subagent
4. **Retry with Feedback** — Critics reject → maker retries (up to 2×)
5. **Human-in-the-Loop** — Escalation at mandatory triggers, never blind
6. **Isolated Context** — Each subagent has a clean context window
7. **Deterministic Hooks** — Quality gates enforced by code, not instructions
8. **Model Optimisation** — Cheaper models for analysis, capable for editing
9. **Traceability** — Provenance markers + workflow logs + git conventions

## Lessons Baked In

This framework was refined through real usage. Key lessons:

- **Instructions without gates are suggestions.** The pre-delivery checklist
  in each agent is a hard gate, not a guideline.
- **Subagents get clean context.** Pass all needed information in the prompt —
  subagents don't inherit the coordinator's conversation history.
- **Urgency may override TDD — but tests must be backfilled.**
- **Build incrementally.** Use the coordinator for one task, fix friction, expand.
- **Domain expertise is the human's irreplaceable contribution.** Agents
  investigate and implement; the human confirms domain semantics.

---

**Resources:** [CHANGELOG](CHANGELOG.md) · [TROUBLESHOOTING](.github/TROUBLESHOOTING.md) · [MANIFEST](.github/MANIFEST.md) · [Interactive Map](agent-framework-map.v2.html)
