# Copilot Agent Team Framework

> A ready-to-use folder structure for VS Code + GitHub Copilot agent workflows.
> Drop the `.github/` folder into any Python project to get an **autonomous**,
> multi-agent TDD workflow with quality gates and traceability.

## What This Is

A **generic, battle-tested** framework for organising AI agents in VS Code
GitHub Copilot. It uses the **Coordinator-Worker pattern** — one coordinator
agent autonomously orchestrates 10 specialised workers as subagents, running
the full TDD pipeline without manual intervention.

## Quick Setup

1. **Place** the `github-copilot/` directory in your project root
   (or clone it as a subdirectory).
2. **Run the deploy script** to install AF files into `.github/` and `.vscode/`:
   ```powershell
   # Windows — preview first, then deploy
   .\github-copilot\deploy.ps1 -DryRun
   .\github-copilot\deploy.ps1
   ```
   ```bash
   # macOS / Linux
   ./github-copilot/deploy.sh --dry-run
   ./github-copilot/deploy.sh
   ```
   The script copies only AF-owned files (see `.github/.af-manifest`).
   Existing non-AF files (`workflows/`, `CODEOWNERS`, etc.) are never touched.
3. **Run `/onboard-project`** in Copilot Chat — it analyses your codebase,
   detects existing `.github/` files, shows what AF will add vs. what
   conflicts exist, and auto-fills configuration. Review before confirming.
4. **Start using** — open Copilot Chat and type `@coordinator <your task>`,
   or use `/tdd-feature`, `/quick-fix`, or `/review-code` slash commands.

### Updating the AF

Re-run the deploy script after pulling AF updates. Customizable files
(`copilot-instructions.md`, `architecture.instructions.md`) are protected —
they won't be overwritten unless you use `-Force` / `--force`.

Use `-Diff` / `--diff` to compare source vs deployed before updating:
```powershell
.\github-copilot\deploy.ps1 -Diff
```

<details>
<summary>Manual setup (if you prefer not to use the deploy script)</summary>

1. **Copy AF-owned directories** from `github-copilot/.github/` into your
   project's `.github/`. AF owns: `agents/`, `hooks/`, `instructions/`,
   `prompts/`, `skills/`, `templates/`, `logs/`, `retros/`, plus
   `MANIFEST.md`, `GOVERNANCE.md`, `TROUBLESHOOTING.md`, and
   `copilot-instructions.md`. See `.github/.af-manifest` for the full list.
   **Do NOT overwrite** existing non-AF files.
2. **Copy** `.vscode/toolsets.jsonc` into your `.vscode/` folder.
3. **Run `/onboard-project`** and follow prompts.

</details>

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

### Model Prioritization

Every worker has a **prioritized model list** sized to its task complexity.
VS Code tries each model in order until one is available.

| Tier | Agents | Model Priority | Rationale |
|---|---|---|---|
| **1 — Full Power** | implementer, test-writer, refactorer | Opus 4.6 → Sonnet 4.6 → GPT-5.4 | Complex creative code generation (3x premium) |
| **2 — Strong** | planner, code-critic, researcher | Sonnet 4.6 → GPT-5.4 → GPT-4.1 | Deep analysis at standard cost (1x) |
| **3 — Efficient** | test-critic, arbiter, documenter, compliance-checker | Sonnet 4 → GPT-4.1 → Haiku 4.5 | Checklist review / template output (0.33x fallback) |
| **— (user)** | coordinator | *(no `model:` field)* | Uses whatever model the user selects |

```yaml
# Tier 1 — makers get the most capable model first
model:
  - Claude Opus 4.6 (copilot)
  - Claude Sonnet 4.6 (copilot)
  - GPT-5.4 (copilot)

# Tier 3 — lightweight tasks end with a cheap fallback
model:
  - Claude Sonnet 4 (copilot)
  - GPT-4.1 (copilot)
  - Claude Haiku 4.5 (copilot)
```

Customise the model lists in each worker's `.agent.md` file to match your
subscription and model availability. Check the
[supported models list](https://docs.github.com/en/copilot/reference/ai-models/supported-models)
for current availability and cost multipliers.

## When You're Involved

The coordinator runs autonomously but **escalates** to you for:

- 3rd rejection by any critic (after 2 retries)
- Ambiguous requirements needing domain expertise
- Large plans (6+ subtasks) requiring approval
- New architectural elements (ports, adapters)
- Destructive or security-sensitive actions

Everything else is fully autonomous.

## File Map

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
├── agents/                                # 11 agent definitions
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
│   └── compliance-checker.agent.md        # Worker: workflow compliance watchdog (bookends)
├── hooks/                                 # Agent hooks (deterministic enforcement)
│   ├── README.md                          # Hook documentation and templates
│   ├── agent-hooks.json                   # Active hooks: all 4 lifecycle events
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
│   ├── find-skill.prompt.md               # /find-skill → search skill library by topic
│   ├── onboard-project.prompt.md          # /onboard-project → auto-fill config
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

## Tool Configuration

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

All four hooks work out of the box — no configuration needed.
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
| `/audit-config` | Detect drift between AF config and project |
| `/validate-framework` | Scan AF files for internal consistency |
| `/find-skill` | Search the skill library by topic |
| `/simulate` | Dry-run a task without executing |
| `/onboard-project` | First-time project setup wizard |
| `/retro-summary` | Aggregate past workflow lessons |

Standalone utilities run independently — the coordinator doesn't invoke
them. Use them for framework maintenance and discovery.

## Adopting Incrementally

> **Key lesson:** Don't try to use the full pipeline from day one. Start small.

**Week 1:** Use `@coordinator` for small tasks. See the Quick Fix workflow.
**Week 2:** Try a feature with the full TDD workflow. Watch the subagent calls.
**Week 3:** Customise worker instructions for your project's patterns.
**Week 4:** Review workflow logs in `.github/logs/` for process improvement.

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

## Prerequisites

- VS Code with GitHub Copilot extension
- Python 3.10+ with `pytest`, `hypothesis` (for property-based tests)
- Optional: `radon` (complexity), `ruff` (linting), `mutmut` (mutation testing)

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
