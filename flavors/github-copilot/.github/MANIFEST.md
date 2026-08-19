# Agent Team Manifest

> Governing principles for the AI agent team. All agents must follow these rules.
> This is the condensed, generic version — no project-specific content.
>
> **Governance Layer:** This manifest operationalizes the Core Principles and
> Domain Rules defined in [GOVERNANCE.md](GOVERNANCE.md). All principles and
> meta-rules defined there are binding.

---

## 1. Autonomous Orchestration

The agent team uses the **Coordinator-Worker pattern**:

- **Coordinator** — the only user-facing agent. Receives tasks, invokes workers
  as subagents, manages flow, handles retries, escalates when needed.
- **Workers** — specialised subagent-only agents. Each has its own tools,
  instructions, and isolated context window. Workers return results to the
  coordinator.

### Worker Agent Roles

| Agent | Role | Phase |
|---|---|---|
| `planner` | Decompose tasks, acceptance criteria | Planning |
| `test-writer` | Write failing tests | TDD Red |
| `test-critic` | Review test quality | Review |
| `implementer` | Make tests pass | TDD Green |
| `refactorer` | Clean up, no behaviour change | TDD Refactor |
| `code-critic` | Architecture + metrics review | Review |
| `arbiter` | Resolve maker-critic disputes | Dispute resolution |
| `documenter` | Workflow logs, doc updates | Documentation |
| `researcher` | Fetch & synthesize external docs | Research (pre-flight) |
| `compliance-checker` | Verify workflow process gates | Compliance (bookends) |
| `ado-work-item-manager` | Optional provider worker for Azure DevOps work item lifecycle | Optional integration |
| `ado-wiki-manager` | Optional provider worker for Azure DevOps wiki lifecycle | Optional integration |
| `ado-pr-manager` | Optional provider worker for Azure DevOps pull request integration (request-based merges) | Optional integration |
| `ado-pipeline-manager` | Optional provider worker for Azure DevOps pipelines (PR build-validation gate) | Optional integration |

### Subagent Execution

- Each subagent runs in an **isolated context window** — no conversation history
- The coordinator passes **all needed context** in the subagent prompt
- Subagents are **synchronous** — the coordinator waits for results
- Independent subtasks can run as **parallel subagents**
- Subagent results are **summaries only** — intermediate steps stay isolated

---

## 2. Test-Driven Development

All code changes follow **Red → Green → Refactor** as discrete subagent steps.

| Phase | Worker | Action | Exit Criterion |
|---|---|---|---|
| **Red** | test-writer | Write failing tests | Tests exist and FAIL |
| **Green** | implementer | Write minimal passing code | All tests PASS |
| **Refactor** | refactorer | Clean up, no behaviour change | All tests still PASS |

### Three Test Tiers

| Tier | Type | When Run | Purpose |
|---|---|---|---|
| 1 | Unit tests | Every iteration | Verify functions in isolation |
| 2 | Property-based tests | Per feature | Verify invariants with generated inputs |
| 3 | Mutation tests | Final quality gate only | Verify test sensitivity to real faults |

> **Note:** Mutation testing (Tier 3) is aspirational. No agent or hook
> currently runs a mutation tool (`mutmut`, `cosmic-ray`). When tooling is
> integrated, the code-critic or a dedicated hook will enforce it.

### Anti-Gaming Rules

These are explicitly prohibited and cause automatic rejection:

- **Trivial tests** — `assert True`, `assert x == x`
- **Coverage padding** — calling a function without asserting on the result
- **Mutation suppression** — marking mutants as equivalent without justification

---

## 3. Architecture & Separation of Concerns

Code is organised into layers. Business logic is isolated from I/O.

```
┌─────────────────────────────────────────┐
│            Orchestrators                │  Wire adapters to core, manage flow
├─────────────────────────────────────────┤
│            Adapters (I/O)               │  External systems, files, APIs
├─────────────────────────────────────────┤
│            Ports (Interfaces)           │  Protocol classes defining contracts
├─────────────────────────────────────────┤
│            Domain Core                  │  Pure logic, no I/O, fully testable
└─────────────────────────────────────────┘
```

**Dependency Rule:** Dependencies point inward only.

- Domain Core → imports nothing from other layers
- Ports → may import from Domain Core
- Adapters → may import from Ports and Domain Core
- Orchestrators → may import from all layers

> Customise the architecture map in `instructions/architecture.instructions.md`
> with your project's specific modules and classification.

---

## 4. Maker-Checker Pattern

No agent's output is accepted without review. The coordinator enforces this
by invoking critic subagents after every maker subagent.

| Maker | Critic | Review Focus |
|---|---|---|
| test-writer | test-critic | Test meaningfulness, edge cases |
| implementer | code-critic | Architecture, metrics, quality |
| refactorer | code-critic | Behaviour unchanged, tests green |

### Retry & Escalation

| Attempt | Action |
|---|---|
| 1st rejection | Coordinator re-invokes maker with critic's feedback |
| 2nd rejection | Coordinator re-invokes maker (final attempt) |
| 3rd rejection | Coordinator invokes **arbiter** or **escalates to human** |

The coordinator manages all retry logic — no human intervention needed
until escalation.

---

## 5. Quality Gates

Every gate is classified as **HARD** (automated, blocks handoff),
**SOFT** (judgment-based, reviewer decides), or **ADVISORY** (informational,
never blocks). See `instructions/quality-gates.instructions.md` for the
full gate system and complexity tiers; each agent's own exit gate table is
in `agents/{agent}.agent.md`.

### Complexity Tiers

| Tier | When | Gate Behaviour |
|---|---|---|
| **Trivial** | ≤ 2 files, no logic changes | Gate 1 only, no critics |
| **Standard** | 3–5 files, within existing architecture | Gates 1–3 + skill gates, critics invoked |
| **Deep** | 6+ files or new architectural elements | All gates at full thresholds, arbiter available |

If any file in domain core or ports is touched, minimum tier is **Standard**.
The human can override the tier at plan approval.

### Gate 1: Auto-Check (All Changes) — HARD

- [ ] Syntax valid
- [ ] No unused imports
- [ ] Type checking passes
- [ ] All existing tests pass

### Gate 2: Test Quality (After test-writer) — SOFT

- [ ] Tests express real requirements (not trivial)
- [ ] Edge cases covered (nulls, empty, boundaries)
- [ ] Property tests cover domain invariants
- [ ] Tests are deterministic

### Gate 3: Implementation Quality (After implementer) — HARD + SOFT

- [ ] All tests pass — HARD
- [ ] Coverage thresholds met — HARD
- [ ] Architecture boundaries respected — SOFT
- [ ] Public API typed and documented — SOFT
- [ ] Complexity within limits — SOFT (Standard), HARD (Deep)

### Gate 4: Security (All Changes) — R-SD-11, R-SD-12, R-SD-13 — HARD

- [ ] No secrets, credentials, or API keys in source code or config
- [ ] No new dependencies with known critical/high CVEs
- [ ] User input validated and sanitized at system boundaries
- [ ] No SQL injection, command injection, or template injection vectors

Enforced by the code-critic during review. Use project-configured tools
(e.g., `bandit`, `pip-audit`, `trivy`) where available.

### Metric Thresholds (Customise for Your Project)

| Module Type | Line Coverage | Branch Coverage | Mutation Score | Max Complexity |
|---|---|---|---|---|
| Domain core | ≥ 90% | ≥ 85% | ≥ 80% | ≤ 10 |
| Ports | ≥ 80% | ≥ 75% | ≥ 70% | ≤ 5 |
| Adapters | ≥ 60% | ≥ 50% | N/A | ≤ 15 |
| Utilities | ≥ 85% | ≥ 80% | ≥ 75% | ≤ 8 |

These thresholds are the **single source of truth**. All agents and
skills reference this table — never duplicate these numbers elsewhere.

---

## 6. Human-in-the-Loop Escalation

The coordinator escalates to the human for:

- 3rd maker-critic rejection
- Ambiguous or contradictory requirements
- New architectural elements (new port, new adapter pattern)
- Destructive actions (file deletion, schema changes)
- Security-sensitive changes
- Metric thresholds unmet after 2 attempts
- Task scope exceeds estimate by > 50%

Everything else is handled autonomously.
See § 13 Inter-Agent Contracts for the structured escalation data format.

---

## 7. Traceability — R-SD-08, R-SD-09, R-SD-23

### AI Provenance Markers

All AI-generated files carry parseable markers (see `instructions/provenance.instructions.md`):

```
copilot:generated | <agent-name> | <YYYY-MM-DD>
copilot:modified  | <agent-name> | <YYYY-MM-DD> | <brief description>
```

### Agent Identity — R-SD-23

Every agent operates under a distinct, verifiable identity:

- Each agent's `name` field in its `.agent.md` frontmatter is its identity
- All commits, logs, and provenance markers attribute actions to the agent name
- No "shadow agents" — every autonomous action is traceable to a named agent
- Agents must not impersonate other agents or the human user
- Provider-scoped workers should use `{provider}-{capability}-{role}` naming
  (for example `ado-work-item-manager`, `ado-wiki-manager`, `ado-pr-manager`)

### Least Privilege — R-SD-21, R-SD-22

Agents receive only the tools and permissions needed for their role:

- Tool sets in `.vscode/toolsets.jsonc` scope each agent's capabilities
- Read-only agents (critics, arbiter) cannot edit files
- The planner writes exactly one file, its own plan document; every other path
  is denied by `planner-pretooluse` (issue #130)
- No agent is granted credentials capable of mutating production environments
  unless following a certified deployment workflow
- Scoped, temporary credentials are preferred over long-lived tokens

> **Open gap:** Credential scoping (GOVERNANCE L1 §7c — R-SD-21, R-SD-22) is
> currently aspirational. No credential management system (Vault, OIDC, token
> rotation) is configured. This will be operationalized when CI/CD integration
> is implemented. Until then, agents operate under the human user's session
> credentials with tool-level restrictions as the only access control.

### Git Conventions

- Agent branches: `agent/{workflow-id}`
- Agent commits: `[agent:{agent-name}] {action summary}`
- Human commits: conventional commits format
- **Local git is coordinator-executed** — the coordinator creates branches,
  stages specific files, and commits at reviewed checkpoints
- **Integration follows the configured path** — pure git by default (push and
  merge human-controlled); or, when a PR/MR provider capability is enabled,
  request-based: the coordinator pushes the feature branch and `ado-pr-manager`
  manages the request (integration branch autocompletes; protected branch is
  human-completed)
- **Destructive git is human-controlled** — branch deletion, hard reset,
  rebase, force push, and pushes to protected branches require human action
- The `block-dangerous` hook enforces the destructive/protected boundary as a
  three-tier classifier (auto-approve safe / prompt durable / hard-deny
  destructive), tuned via `AUTONOMY_LEVEL` / `AUTONOMY_CAT_*` in `af-env.conf`
- One atomic commit per workflow phase (plan, tests, implementation, docs)
- See `instructions/git-workflow.instructions.md` for the core rules and
  `skills/git-workflow/SKILL.md` for the full protocol

### Planning Documents

Every mid-to-high complexity task produces a persisted plan file using the
template in `templates/PLAN.md`. Plan files use unique, descriptive names:
`{type}-{YYYY-MM-DD}-{slug}.md` (e.g., `feat-2026-03-10-bucketing-v2.md`).
They are stored in the project's plan directory (default: `docs/plans/`)
and remain permanently as human-readable documentation. The plan is the
first commit on the feature branch and is updated throughout the workflow
as a living document.

### Workflow Logs

The documenter writes one YAML log per workflow to `.github/logs/{workflow-id}.yaml`
(schema in `agents/documenter.agent.md`). Logs are local instrumentation: the
directory ships a `.gitignore`, because `trigger:` holds the user request
verbatim.

The documenter Stop hook then appends an **ADVISORY** `cost:` block measuring
what the workflow actually cost — billed requests, tokens and credits for the
parent session *and* its subagents, broken down by model. It comes from the chat
debug log via `scripts/collect-session-cost.py`; the hook appends the script's
output verbatim, so the numbers never pass through a language model and no agent
ever reads the log (tens of megabytes, every prompt verbatim).

Its source is an experiment-flagged vendor setting, so the block **may be absent
or `available: false` at any time, and nothing may gate on it**. A `coverage`
field qualifies every total; when the log lost its start, no total is emitted
rather than a number that looks complete but is biased downward. Details:
`logs/README.md`.

## 8. Agent Hooks (Deterministic Enforcement)

Hooks execute shell commands at lifecycle points during agent sessions.
Unlike instructions that _guide_ behaviour, hooks _enforce_ it with code.
Configuration lives in `.github/hooks/*.json`.

### Active Hooks (all registered in `agent-hooks.json`)

| Event | Hook | What It Does |
|---|---|---|
| `SessionStart` | Session Context | Injects git branch, last commit, Python version |
| `SessionStart` | ADO MCP Readiness | Reports ADO capability availability and fallback state |
| `PreToolUse` | Safety Gate | Three-tier classifier: auto-approve safe commands, prompt durable changes, hard-deny `rm -rf`/`DROP TABLE`/force push/etc. |
| `PostToolUse` | Secret Scan | Scans edited files for hardcoded secrets (gitleaks or regex fallback) |
| `Stop` | Test Gate | Runs `pytest tests/ -q --tb=line` before session ends |
| `SubagentStop` | Documenter Artifact Gate | Blocks on a missing workflow log or retro snippet, then appends the ADVISORY `cost:` block to the log |

### Hook Output Control

- Exit code `0` → success, parse stdout JSON
- Exit code `2` → blocking error, stop processing
- `permissionDecision: "allow"` → auto-approve a tool call (no prompt)
- `permissionDecision: "ask"` → prompt user to confirm a tool call
- `permissionDecision: "deny"` → block a specific tool call
- `decision: "block"` (in `Stop` hook) → prevent session from ending

Hooks are deterministic — they run your code, not AI-generated suggestions.
See `hooks/README.md` for configuration format, script documentation, and templates.

---

## 9. Model Prioritization

Workers can specify a prioritized model list. VS Code tries each in order
until one is available. This optimises cost and speed:

| Worker Type | Model Strategy | Rationale |
|---|---|---|
| Analysis (planner, critics, arbiter) | Fast/efficient models first | No code edits |
| Editing (test-writer, implementer, refactorer) | Most capable model | Code quality matters |
| Documenter | Efficient model | Structured log writing |

```yaml
model:
  - Claude Sonnet 4 (copilot)
  - GPT-4.1 (copilot)
```

If no model is specified, the user's currently selected model is used.

---

## 10. Custom Tool Sets

Tool permissions are managed via **named tool sets** defined in
`.vscode/toolsets.jsonc`. Agents reference set names instead of listing
individual tools, reducing duplication and making permission changes atomic.

| Tool Set | Contents | Purpose |
|---|---|---|
| `codebase-reader` | search/*, read/*, todo | Universal read + navigate |
| `test-runner` | runTests, testFailure | Test execution + inspection |
| `file-editor` | editFiles, createFile, createDirectory | File mutations |
| `terminal` | runInTerminal, getTerminalOutput | Shell commands |
| `pylance-lint` | pylanceFileSyntaxErrors, pylanceImports | Python diagnostics |
| `pylance-refactor` | pylanceInvokeRefactoring, pylanceRunCodeSnippet | Refactoring tools |

**Rule:** To grant or revoke a capability across multiple agents, edit the
tool set definition once — all referencing agents update immediately.

---

## 11. Pre-Delivery Checklist (Hard Gate)

> Every worker agent must verify these before returning results to the
> coordinator. This is not aspirational — it is a mandatory gate.
>
> **Single source of truth:** The checklist items are defined in
> `copilot-instructions.md` § Pre-Delivery Checklist. All agents receive
> that file automatically. Do not duplicate the checklist here — refer
> to the canonical copy to prevent drift.

---

## 12. Governing Rules (L2 Domain Rules Cross-Reference)

This framework operationalizes the Software Development domain rules defined
in [GOVERNANCE.md](GOVERNANCE.md). Each rule is mapped to the AF element that
enforces it.

| Rule | Statement | Enforced By |
|---|---|---|
| R-SD-01 | All code reviewed before integration | § 4 Maker-Checker, code-critic agent |
| R-SD-02 | ADRs for structural / cross-cutting decisions | planner agent, documenter agent |
| R-SD-03 | Code review assesses maintainability, testability, security, conventions | code-critic Steps 1–7 review checklist |
| R-SD-04 | All production code has automated tests (≥ 60%) | § 2 TDD, § 5 Quality Gates |
| R-SD-05 | Static analysis with zero errors before integration | § 5 Gate 1 Auto-Check, pylance-lint tools |
| R-SD-06 | Quality gates enforced programmatically | § 5 Quality Gates, § 8 Agent Hooks |
| R-SD-08 | Changes linked to tracked work items (or fallback traceability when tracker is optional/unavailable) | planner + optional ado-work-item-manager |
| R-SD-09 | Structured commit messages | § 7 Git Conventions |
| R-SD-11 | No secrets in source code | § 5 Gate 4 Security |
| R-SD-12 | Dependencies scanned for known CVEs | § 5 Gate 4 Security, code-critic `pip-audit` |
| R-SD-13 | User input validated at system boundaries | § 5 Gate 4 Security, code-critic |
| R-SD-14 | Error handling: recoverable vs unrecoverable | implementer agent |
| R-SD-16 | Application layers separated | § 3 Architecture & Separation of Concerns |
| R-SD-20 | Rule of Three for deduplication | refactorer agent |
| R-SD-21 | Scoped API tokens, no global PATs | § 7 Least Privilege |
| R-SD-22 | No production-mutation credentials without deployment workflow | § 7 Least Privilege |
| R-SD-23 | Agent commits attributed to Agent ID | § 7 Agent Identity |
| R-SD-24 | Proof of Failure — failing test before fix | § 2 TDD Red phase, quick-fix prompt |
| R-SD-25 | Iteration limits — no open-ended loops | § 4 Retry & Escalation, § 6 Escalation |
| R-SD-26 | Escalation protocol — halt and request human help | § 6 Human-in-the-Loop Escalation |
| R-SD-27 | Dependency upgrade policy with rollback plan | Escalate to human (manual) |

Rules not listed (R-SD-07, R-SD-10, R-SD-15, R-SD-17, R-SD-18,
R-SD-19) are applicable but not yet explicitly operationalized.
They apply through general coding standards and project configuration.
Full rule statements are in [GOVERNANCE.md § Domain Rules](GOVERNANCE.md).

---

## 13. Inter-Agent Contracts

Every subagent invocation follows a defined contract. The coordinator
passes required inputs and expects structured outputs.

### Handoff Data Requirements

| From → To | Required Input | Required Output |
|---|---|---|
| User → Coordinator | Task description | Workflow result summary |
| Coordinator -> Planner | User request, codebase context | Plan-structured output (per `templates/PLAN.md`) |
| Coordinator → Test-writer | Plan summary, acceptance criteria, file list | Test files, test run results |
| Coordinator → Test-critic | Test file list, plan context | Structured verdict |
| Coordinator → Implementer | Plan summary, test files, failure details | Changed files, test run results |
| Coordinator → Refactorer | Changed file list | Changed files, test run results |
| Coordinator → Code-critic | Changed file list, plan context | Structured verdict + metrics |
| Coordinator → Arbiter | Both positions (maker + critic), relevant rules | Decision + reasoning |
| Coordinator -> Documenter | All step summaries, all files, final metrics | Plan file update, YAML log |
| Coordinator -> Researcher | Research questions, task context | Structured research brief with citations |
| Coordinator -> Compliance-checker | Branch, plan dir, files changed, tier | Pre-flight or post-flight verdict (PASS/FAIL + missing artifact list) |

### Verdict Format (Critics + Arbiter)

All verdict-producing agents return a parseable header as the first
`##`-level heading of their response:

```markdown
## {Review Type} Verdict: {APPROVED | REJECTED | ESCALATE}
```

The coordinator parses the verdict defensively (see coordinator's Verdict
Parsing Protocol): case-insensitive search for `verdict:` anywhere in the
response, accepts the keyword regardless of formatting. If no verdict
keyword is found, the result is treated as **BLOCKED** (never silently
defaulted to APPROVED).

| Agent | Review Type | Possible Verdicts |
|---|---|---|
| test-critic | Test Review | APPROVED, REJECTED, ESCALATE |
| code-critic | Code Review | APPROVED, REJECTED, ESCALATE |
| arbiter | Arbiter Decision | RESOLVED, COMPROMISE, ESCALATE |

### Rejection Feedback Contract

Every REJECTED verdict must include structured, actionable feedback so the
maker's retry has the best chance of success. Vague rejections waste context
budget and lead to identical retries.

**Required fields (REJECTED verdicts only):**

| Field | Content | Example |
|---|---|---|
| `findings` | List of issues, each with: file, location (line/function), severity (`BLOCKING` / `SHOULD-FIX` / `ADVISORY`), suggestion | `tests/test_foo.py:42` — BLOCKING — assert True is trivial; replace with behaviour assertion |
| `blocking_count` | Integer ≥ 1 (count of BLOCKING findings) | `blocking_count: 2` |
| `retry_guidance` | 1–2 sentences of actionable direction for the retry | "Focus on edge-case assertions for the `clamp()` boundary values." |

If the coordinator receives a REJECTED verdict missing any of these fields,
it re-requests the review with specifics before counting a retry attempt.

### Test & Metrics Reporting Format

Agents that run tests include these fields in their response:

```
tests_total: <N>
tests_passed: <N>
tests_failed: <N>
line_coverage: <N>%
```

The code-critic additionally reports:

```
branch_coverage: <N>%
complexity_max: <N>
```

### Gate Summary Reporting

Every agent appends a **Gate Summary** to their return format
(see `instructions/quality-gates.instructions.md` for per-agent gates):

```markdown
### Gate Summary
- **Tier:** {Trivial | Standard | Deep}
- **HARD gates:** {passed}/{total} passed
- **SOFT gates:** {count} evaluated (reviewer decides)
- **ADVISORY:** {metric_name} = {value}
- **BLOCKED gates:** {list, or "none"}
- **Failed HARD gates:** {list, or "none"}
- **Skills Read:** {list of SKILL.md files read, or "none — no applicable skills"}
```

The coordinator uses this summary:
- All HARD passed → proceed to next step
- Any HARD failed → treat as implicit REJECTED (retry or escalate)
- Any HARD BLOCKED → escalate to human

### Dependency Changes

When adding or upgrading a dependency, the implementer must include
package name, version, and justification in the handoff to code-critic.

### Escalation Data

When the coordinator escalates to the human, it presents these fields
in chat (no separate file — see § 6):

- **Step:** current workflow step
- **Trigger:** why escalation occurred
- **Context:** what was attempted
- **Attempts:** summary of each retry
- **Options:** recommended actions with trade-offs
- **Files:** involved file list

If the session is interrupted during escalation, WIP.md captures the
escalation context (see `templates/WIP.md` § Escalation Context).

### Artifact Lifecycle Summary

| Artifact | Created | Consumed By | Lifetime |
|---|---|---|---|
| Plan file (`docs/plans/{type}-{date}-{slug}.md`) | Planner -> Coordinator | Implementer, Documenter | Permanent (human-readable documentation) |
| WIP.md (`docs/plans/WIP.md`) | Coordinator (on interrupt) | Coordinator (on resume) | Branch-scoped, deleted on completion |
| Workflow YAML log | Documenter | Human, audit | Local only, never committed; 30-day retention |
| Provenance markers | All producing agents | Documenter (verification) | Permanent in source |
| ADRs | Human / Code-critic | All agents | Permanent in docs/ |
