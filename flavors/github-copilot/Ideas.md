# Ideas for Future Improvements / Features

## Status Legend

- ✅ **DONE** — Completed and verified
- 🔄 **IN PROGRESS** — Currently being worked on
- ⬜ **TODO** — Not yet started
- 🟡 **PARTIAL** — Some progress, more work needed

---

## 1) ✅ DONE — AF should not reference AAIG (2026-03-09)

AF should not reference to AAIG. The content must be integrated into AF fully. Can AF integrate any additional information into agents/skills/hooks. Note that core principles should be considered.

**What was done:**
- GOVERNANCE.md fully rewritten — inlined all L1 Core Principles, Meta-Rules, Framework Architecture, all 27 R-SD Domain Rules. Zero external AAIG references.
- MANIFEST.md updated to reference GOVERNANCE.md instead of AAIG.
- workflow-lifecycle.instructions.md — 2 AAIG mentions removed.
- 28 AAIG skills extracted as AF-native SKILL.md files (37 total skills now).
- Verified: zero "AAIG" references in any AF operational file.

---

## 2a) ✅ DONE — Proper git flow with atomic commits (2026-03-09)

Proper git flow? Atomic commits. During each task there should be a proper git flow (if applicable). There should be a new branch following a clear naming convention. The plan should be the first commit (see 2b).

**What was done:**
- Created `instructions/git-workflow.instructions.md` (`applyTo: '**'`) — consolidates all git flow rules in one auto-applied instruction:
  - Cardinal rule: "Git is human-controlled" — agents suggest, humans execute.
  - Branch lifecycle: `agent/{workflow-id}`, planner suggests name, human creates.
  - Atomic commit strategy with phase-to-commit mapping table (plan → tests → implementation → refactor → docs).
  - Commit message format: `[agent:{name}] {description}`.
  - Human commit format: conventional commits.
- Updated coordinator workflow with 6 explicit commit checkpoints (after plan, after tests, after green, after refactor, after docs, final).
- Updated MANIFEST.md §7 with atomic commit protocol reference.

---

## 2b) ✅ DONE — Persisted, reviewed planning document as first commit (2026-03-09)

Each task should start with a persisted, but living planning document, which was reviewed properly, i.e., only minor findings are left after peer review. Leftover findings are to be documented. The document should be updated during and after implementation also.

**What was done:**
- Created `templates/PLAN.md` — structured planning document template with:
  - Workflow metadata (type, branch, status).
  - Context / problem statement.
  - Scope assessment (files, layers, size, risks).
  - Subtasks with acceptance criteria, test refs, dependencies, status.
  - Implementation sequence, quality gates, review section, change log.
- Updated planner agent return format to follow PLAN.md template structure.
- Coordinator creates PLAN.md file from planner's output (planner is read-only).
- Updated documenter responsibilities: PLAN.md finalisation (status → COMPLETED, metrics, closing change log entry) is first responsibility.
- Added "Planning Documents" subsection to MANIFEST.md §7.
- Added `git-workflow.instructions.md` and `templates/` directory to README.md file map.

---

## 3) ✅ DONE — Thorough peer review of AF structure (2026-03-09)

Review AF in a thorough peer review. Are all files necessary, especially on a high level. We have agents, hooks, instructions, prompts, skills, and templates. Are all of these necessary. Is there potential to simplify (but not to cut content!). Does everything follow the structure of the GitHub Copilot agent customization documentation?

**Priority:** 1st — Foundation work before adding features.

**What was done:**
- Full structural audit of all AF file types (agents, instructions, prompts, skills, hooks, templates, governance docs, support dirs).
- **Verdict: All file types are necessary.** No files to remove. Every type serves a distinct purpose.
- **CRITICAL finding — content duplication:** Architecture rules, provenance marking, test methodology, and quality gates are each duplicated in 3-5 files (agents, instructions, MANIFEST). This is a maintenance hazard where a threshold change requires updating multiple files. **Deferred to Idea 7** (agent/skill separation).
- **Fixed: coordinator.agent.md** — removed duplicate "Final Report" section (two versions existed, merged into one).
- **Fixed: README.md** — added missing `workflow-lifecycle.instructions.md` to the file map; updated skills listing to reflect 37 skills.
- **Corrected false findings** from previous analysis: `agents:` YAML attribute is valid (documented in copilot-authoring §2); `copilot-customization-reference.md` dangling reference does not exist.

---

## 4) ✅ DONE — Automate project onboarding/customization (2026-03-09)

The README states the user has to do customization manually. Can we automate that. If there is an existing project, those customizations can be derived automatically.

**What was done:**
- Created `/onboard-project` slash command (`prompts/onboard-project.prompt.md`) that:
  1. Discovers project metadata (name, tech stack, repo URL) from `pyproject.toml`, `setup.py`, `README.md`, `.git/config`
  2. Scans directory tree and builds annotated structure
  3. Analyses imports to classify modules into architecture layers (domain, ports, adapters, orchestrators, mixed)
  4. Detects configured tools (formatter, linter, test runner, type checker)
  5. Discovers project-specific conventions and anti-patterns
  6. Presents findings for human confirmation before writing changes
  7. Auto-fills `copilot-instructions.md`, `architecture.instructions.md`, and `quality-gates.json`
- Updated README Quick Setup: `/onboard-project` is now step 3 (replacing 3 manual customization steps). Manual setup preserved in a collapsible `<details>` section.
- Added prompt to the README file map.

---

## 5) ✅ DONE — Use Pydantic for Python projects (2026-03-09)

In case of Python use Pydantic.

**What was done:**
- Created `skills/pydantic/SKILL.md` — comprehensive skill covering:
  - When to use Pydantic vs dataclasses (decision table)
  - Domain models with `BaseModel(frozen=True)` for immutability
  - Field validation with `Field()` constraints and `field_validator`
  - Configuration with `pydantic-settings` / `BaseSettings`
  - Serialization (`model_dump`, `model_validate`)
  - Integration with hexagonal architecture (domain models, DTOs, adapter pattern)
  - Testing Pydantic models (validation errors, frozen enforcement)
  - Common mistakes table (v1 → v2 migration pitfalls)
- Updated `copilot-instructions.md` template — added Pydantic preference to Code Style: "Use Pydantic `BaseModel` for domain models, value objects, and DTOs."
- Updated `architecture.instructions.md` template — domain core example references Pydantic models.
- Added Pydantic skill reference to implementer agent (creates models) and refactorer agent (converts dataclasses/dicts to Pydantic).
- Skills count: 37 → 38.

---

## 6) 🚫 WONTFIX — Dynamic agent creation not needed (2026-03-09)

Allow the coordinator agent to define a new agent if need be (with corresponding skills, hooks, etc.). Note that the core principles and rules have to be considered! Is that a good idea? We want to avoid that the coordinator rewrites already present files, but allow to extend on capabilities.

**Priority:** 4th (requires idea 7 first — generic agents)

**Decision: Do not implement.** Peer review by planner + code-critic (both AGREE).

**Rationale:**
- Post-Idea 7, all 8 workers are generic shells that specialize via coordinator prompts + skill references at runtime. The only reason to create a new agent is a new tool combination, which is an infrastructure concern requiring human review.
- Dynamic agent creation violates L1 governance: Review (no maker-checker for agent files), Separation of Concern (implementer creating agents is out-of-scope), Identity & Least Privilege (unaudited tool permissions).
- The coordinator already crafts specialized prompts per-invocation — this IS the specialization mechanism.
- For genuinely novel tool needs, the coordinator escalates to the human, who creates the agent manually. This preserves human authority over infrastructure (Meta-Rule 2).
- Skills (SKILL.md) remain the correct extensibility point for domain knowledge gaps — any agent can reference any skill at runtime, and new skills follow the normal review workflow.

**What was done instead:**
- Added "task requires a tool combination not available on any existing agent" to coordinator's mandatory escalation triggers.
- Added "When No Workflow Fits" subsection to coordinator's workflow selection — explicit guidance to escalate with details on what's missing.

---

## 7) ✅ DONE — Agents generic; skills invoked as needed (2026-03-09)

Agents should be as generic as possible (maybe even able to tackle non-software-development tasks). Skills should be invoked by the individual agents as need be and suitable to the task they get. Review if this separation of concern is given.

**Priority:** 2nd (natural follow-up to structural review)

**What was done:**
- All 8 worker agents refactored to generic shells + skill references.
- Removed inline domain-specific content that duplicated instruction files or skills:
  - Provenance marking sections removed from test-writer, implementer, refactorer (covered by `provenance.instructions.md` with `applyTo: **`).
  - Code example templates removed from test-writer (70+ lines → 6 brief principles + skill refs).
  - Architecture rules compacted in implementer (18 lines → 4-line summary + skill ref).
  - Refactoring technique tables compacted in refactorer (28 lines → 4-line summary + skill ref).
  - Metrics thresholds table + security review + anti-gaming detail compacted in code-critic (35+ lines → brief + skill refs).
- Skill references increased from 16 → 27 across all agents (added hexagonal-architecture, unit-testing, task-decomposition, risk-management, human-escalation, secure-coding).
- Agent line counts reduced significantly:

| Agent | Before | After | Reduction |
|---|---|---|---|
| test-writer | 248 | 69 | 72% |
| implementer | 246 | 72 | 71% |
| refactorer | 144 | 60 | 58% |
| code-critic | 235 | 93 | 60% |
| test-critic | 140 | 78 | 44% |
| arbiter | 56 | 63 | +7 (skills section added) |
| planner | 74 | 76 | +2 (skills added) |
| documenter | 96 | 96 | 0 (wording only) |
| coordinator | 352 | 233 | 34% (Idea 3 fix) |

**What remains:**
- Coordinator retains its TDD workflow inline (this IS its core orchestration logic, not domain content). Making the coordinator workflow-agnostic would be a larger redesign — potentially Idea 6 territory.

---

## 8) ✅ DONE — Documentation/logging streamlining and contracts (2026-03-09)

I found that there are various kinds of documentation and logging on the high level. The documenter orders an yaml format, at some other point there are adrs mentioned. We have to review that throughout the AF. Documentation is important for transparancy and tracability, but it must tbe structured and not clutering. Furttheer clear documentation also may serve as contracts between agents.
I remember requesting that each mid to high complex task given by the user should produce some kind of implementation plan persisted in an document, which is updated throughout the task (e.g., and adr or feat plan). What else do we need? THere should be clear contracts between agents, which also should leave an artifact. Should those the log yamls? Whats the best format? Do those two kinds suffice? Do we need more or less? Discuss in a group of peers. Make a plan to make suure the AF follows your results.

**What was done:**

Peer discussion between planner and code-critic agents produced consensus on 10 design decisions:

1. **Artifact count reduced from 7 → 5 per-workflow types**: PLAN.md, WIP.md, YAML log, provenance markers, plus ADRs/retros as permanent docs. ESCALATION.md template **removed** — escalations now handled through chat format + WIP.md context + YAML log recording.
2. **MANIFEST.md §13 Inter-Agent Contracts added** — single source of truth for:
   - Handoff data requirements table (From → To, Required Input, Required Output) for all 9 agent pairs.
   - Unified verdict format spec (parseable `## {Type} Verdict: {APPROVED|REJECTED|ESCALATE}` header).
   - Test & metrics reporting format (4 standard fields).
   - Dependency change reporting rule (one sentence, low overhead).
   - Escalation data format (structured fields for chat presentation).
   - Artifact lifecycle summary table.
3. **WIP.md template updated** — added `Escalation Context` section for session-death recovery during escalation.
4. **workflow-lifecycle.instructions.md updated** — replaced "create ESCALATION.md file" with "present in chat + capture in WIP.md/YAML log."
5. **Coordinator escalation format** now references MANIFEST §13 contracts, explicitly states "no separate file."
6. **Quick Fix = no PLAN.md** — made explicit in coordinator workflow selection.
7. **Documenter YAML schema extended** — optional `escalation:` section for workflows involving escalation/arbiter.
8. **Format split confirmed** — Markdown = living docs, YAML = audit records, in-code comments = provenance. No change needed.
9. **No per-step handoff files** — coordinator chat relay is sufficient.
10. **Skipped** — metrics baseline template (premature) and dependency tracking template (one sentence in contracts suffices).

## 9) ✅ DONE — Quality gates: General, omni-present, generic quality gates (2026-03-09)

It seems, the only quality gates are for code testing. However, it is important, that there are quality gates for as many aspects as possible throughout all levels. E.g. if for a skill there are a selection of suitable quality gates, they shoudl be included (documenter: from doc-string coverage to correctness and completness). This is especially important for the worflows agents follow. Each agent should now what quality gates to suffice to be allowed to hand over his work. If there are no definable qualitty gates there must be a critical, independent peer review with relevant experts. For simpler tasks this would be overkill, but for simple task it should be possible to define quality gates.
Of course, those quality gates should be integrated as generically as possible and also flexible usable (some qualiity gates may be usable by different agents...). Whats the best strategy here. How can this idea be implemented? Discuss with peers.

**What was done:**

Peer discussion between planner and code-critic produced consensus on the design:

1. **Created `instructions/quality-gates.instructions.md`** (`applyTo: '**'`) — auto-applied to all agents, defines:
   - **Gate taxonomy:** HARD (automated, blocks handoff) / SOFT (judgment, reviewer decides) / ADVISORY (informational, never blocks)
   - **Maker-Checker rule:** Self-checks are always SOFT, never HARD — only a different agent or automated tool can enforce a HARD gate
   - **BLOCKED state:** When a tool required for a HARD gate is unavailable, report as BLOCKED (not PASS/FAIL) — triggers escalation
   - **Complexity tiers:** Trivial (≤ 2 files, no critics) / Standard (3–5 files, critics review) / Deep (6+ files or new arch elements, full gates)
   - **Layer override:** Domain core or ports touched → minimum Standard tier regardless of file count
   - **Per-agent exit gate tables** for all 8 agents (planner, test-writer, test-critic, implementer, refactorer, code-critic, arbiter, documenter)
   - **Agent exit protocol:** 6-step checklist every agent follows before returning
   - **Gate Summary format:** Standardised reporting section appended to every agent return
2. **Updated MANIFEST § 5** — added gate taxonomy header (HARD/SOFT/ADVISORY labels per gate), complexity tier table, single-source-of-truth note for metric thresholds
3. **Updated MANIFEST § 13** — added Gate Summary Reporting subsection to inter-agent contracts (coordinator uses gate summaries to decide next actions)
4. **Updated `templates/PLAN.md`** — added `Complexity tier` field to Scope Assessment
5. **Updated coordinator** — Quick Fix tier assignment, BLOCKED gate escalation trigger (9th trigger), gate summary in final report
6. **Updated README** — file map entry for `quality-gates.instructions.md`

**Key design decisions from peer review:**
- Agent files not bloated — instruction is auto-applied via `applyTo: '**'`
- Self-check = SOFT (Maker-Checker principle from § 4) — prevents cognitive bias
- Metric thresholds stated once in MANIFEST § 5, referenced everywhere else
- Non-code agents (planner, documenter, arbiter) get structural gates where automatable, judgment gates otherwise
- Scope limited to Phase 1 (~6 files) — skill gate section reformatting deferred to future batch

---

## 10) ✅ DONE — AF Self-Validation (`/validate-framework`) (2026-03-09)

Scan all AF files for internal consistency: broken skill references in agent files, invalid YAML frontmatter, threshold divergence between MANIFEST §5 and instruction files, cross-references pointing to non-existent sections. Output a structured PASS/WARN/FAIL report. Scope: structure and references only, not semantic correctness.

**What was done:**
- Created `prompts/validate-framework.prompt.md` — 8-step validation scan:
  1. Agent skill references → verify `skills/{name}/SKILL.md` exists
  2. YAML frontmatter → required fields, valid glob patterns
  3. Cross-file references → `MANIFEST §{N}`, `templates/{name}`, etc.
  4. Metric threshold consistency → compare all files against MANIFEST § 5
  5. Governance layer files → R-SD rules in GOVERNANCE.md
  6. Template completeness → placeholder markers, referenced templates exist
  7. Skill directory structure → SKILL.md exists + has heading
  8. Hook configuration → valid JSON/JSONC
- Output: structured FAIL/WARN/INFO report with file-level detail
- Added to README file map

---

## 11) ✅ DONE — Workflow Memory & Auto-Retro (pull model) (2025-07-16)

After each workflow, the documenter auto-generates a retro snippet from the YAML log + gate summaries. Snippets accumulate in `retros/auto/`. A `/retro-summary` prompt lets the human or coordinator pull recent history on-demand (pull model — no auto-injection into SessionStart to avoid context budget pressure).

**What was done:**
- Updated `documenter.agent.md` — added responsibility #5: "Generate retro snippet", added Retro Snippet Generation section with format template, updated write permissions to include `retros/auto/`, added retro snippet line to return format
- Created `prompts/retro-summary.prompt.md` — 4-step pull-model aggregator: discover snippets → read & aggregate → identify patterns → present summary with outcomes table, recurring patterns, and actionable lessons
- Added to README file map

---

## 12) ✅ DONE — Config Drift Detection (`/audit-config`) (2026-03-09)

Re-run the `/onboard-project` discovery logic but diff against current config instead of writing. Report: new unclassified modules, modules that changed layers, thresholds not matching actual metrics, stale README sections. Advisory only — no auto-fix.

**What was done:**
- Created `prompts/audit-config.prompt.md` — 4-step drift detection:
  1. Read current AF config files
  2. Discover actual project state (metadata, structure, imports, tools, deps)
  3. Compute drift across 4 categories: architecture, thresholds, dependencies, conventions
  4. Version comparison (if VERSION file exists)
- Output: structured drift report with per-category tables and prioritised recommendations
- Explicitly advisory — never auto-fixes (human may have intentional customisations)
- Added to README file map

---

## 13) ✅ DONE — CI/PR Integration (`/draft-pr-description`) (2026-03-09)

Generate a PR title, description, and gate checklist from PLAN.md + YAML workflow log + gate summary. Output text only — never create or push a PR. Name explicitly signals it doesn't interact with the remote.

**What was done:**
- Created `prompts/draft-pr-description.prompt.md` — 4-step PR text assembly:
  1. Gather artifacts (PLAN.md, YAML log, git log, changed files)
  2. Extract key information (title, context, changes, metrics, ADRs, breaking changes)
  3. Generate structured PR description with quality gate results table + reviewer focus areas
  4. Present as copy-paste-ready code block
- Handles missing artifacts gracefully (Quick Fix = no PLAN.md → derive from commits)
- Added to README file map

---

## 14) 🔜 DEFERRED — Custom Workflow Definitions

Introduce a `workflows/` directory with project-specific agent sequences. Deferred until the existing TDD and Quick Fix workflows have been exercised end-to-end at least 3 times. Revisit after retro item #2 is resolved.

**Deferral reason:** Code-critic correctly argued this is premature — the current 4 workflow types (Full TDD, Quick Fix, Review Only, Plan Only) haven't been exercised yet. Building custom workflow support before validating the base workflows would be speculative engineering.

---

## 15) ✅ DONE — Context Budget Awareness (2025-07-16)

Coordinator self-assesses context health (GREEN/YELLOW/RED) after each subagent return. On YELLOW: compress completed phases. On RED: checkpoint to WIP.md (HARD gate — not advisory). Prevents the most common silent failure mode: context exhaustion causing subtle quality degradation.

**What was done:**
- Added "Context Budget Awareness" section to `coordinator.agent.md` — GREEN/YELLOW/RED protocol with heuristic-based assessment (subagent call count, retry detection, confusion signals)
- GREEN: continue normally. YELLOW (≥5 calls): compress prior phases. RED (≥7 calls or confusion): HARD gate — checkpoint to WIP.md immediately
- Integrated with existing Session Interruption protocol

---

## 16) ✅ DONE — Workflow Resume (`/resume`) (2025-07-16)

List all branches with WIP.md files and their status/phase. Let the human pick which workflow to resume. Discovery only — branch switching stays human-controlled.

**What was done:**
- Created `prompts/resume.prompt.md` — 4-step discovery: search for WIP files + agent/* branches → read & extract status → present table with resumable workflows → guidance on how to resume (coordinator Step 0 auto-detects)
- Mentions stale WIP detection (>7 days → consider cancelling)
- Added to README file map

---

## 17) ✅ DONE — Skill Discovery Index (`/find-skill`) (2025-07-16)

Auto-generate `skills/INDEX.md` listing each skill's name, one-line description, and which agents reference it. Add a `/find-skill <topic>` prompt for semantic search. Index generation can be a side-effect of `/validate-framework` (Idea 10).

**What was done:**
- Created `skills/INDEX.md` — 38-row table with skill name, description, and referencing agents + Agent Skill Matrix + Unassigned Skills list
- Created `prompts/find-skill.prompt.md` — 4-step semantic discovery: read index → match skills → present ranked results → usage hint
- Added both to README file map

---

## 18) ✅ DONE — Framework Versioning & Changelog (2026-03-09)

Add `VERSION` (semver) and `CHANGELOG.md` at the AF root. Breaking changes bump major, new skills/instructions bump minor, fixes bump patch. Prerequisite for multi-project adoption and safe upgrades. `/audit-config` (Idea 12) should compare project AF version against source.

**What was done:**
- Created `VERSION` file — initial version `1.0.0`
- Created `CHANGELOG.md` — Keep a Changelog format, semver rules documented, full 1.0.0 release entry covering Ideas 1–10
- Added both files to README file map

---

## 19) ✅ DONE — Dry-Run / Simulation (`/simulate`) (2026-03-09)

Run only the planner, then coordinator walks through its decision tree (workflow selection, tier, plan approval gate, parallelisation, escalation triggers) without invoking subagents. Outputs: predicted workflow steps, files to touch, agents to invoke, potential escalation points. De-risks first real workflow runs.

**What was done:**
- Created `prompts/simulate.prompt.md` — 7-step read-only simulation:
  1. Analyse task type and keywords
  2. Discover affected files and layers
  3. Select workflow (Full TDD / Quick Fix / Review Only / Plan Only)
  4. Assign complexity tier with layer override
  5. Predict step sequence with agent responsibilities
  6. Check all 8 mandatory escalation triggers
  7. Identify parallelisation opportunities
- Output: structured simulation result with file impact, risk assessment, and recommendation
- Added to README file map

## 20) ✅ DONE — Autonomy Review & Knowledge Injection (2026-03-09)

Autonomy review. User wasn't sure what of the AF is autonomous vs on-demand vs
user-only. Intent: AF should be as autonomous as possible with coordinator as
single entry point.

**Peer review:** Planner + code-critic analysed all AF components (9 agents,
7 instructions, 12 prompts, 38 skills, 4 hooks, 2 templates, 2 governance docs).

**Core Verdict:** AF has excellent *infrastructure* for autonomy (hooks, tool sets,
instructions, coordinator-worker pattern) but the *knowledge injection* layer was
weak — subagents ran under-informed because skills weren't delivered and the
coordinator didn't inject sufficient context.

**Key contradictions found:**
1. "Single entry point" claim vs 8 standalone prompts bypassing coordinator
2. Skills "assigned" to agents but never delivered (no injection mechanism)
3. Coordinator claims "pass all needed context" but passed ~30%
4. Retro consultation implemented twice (coordinator inline + `/retro-summary`)

**Correctly human-controlled (no change):** Git operations, plan approval for
non-trivial tasks, 3rd-rejection escalation chain, governance document changes.

**6 recommendations implemented:**

| # | Recommendation | Status |
|---|---|---|
| A1 | Coordinator injects skill-read reminders into subagent prompts | ✅ All 7 steps |
| A2 | Coordinator injects context block (tier, thresholds, layers, retro lessons) | ✅ `{context_block}` prepended |
| A3 | Document prompt taxonomy in README (entry points vs utilities) | ✅ 3-tier table |
| A4 | Retro consultation unconditional (all workflows, not just Full TDD) | ✅ Step 0 updated |
| A5 | `/resume` routes through coordinator (`agent: coordinator`) | ✅ Frontmatter updated |
| A6 | `/validate-framework` flags uncustomized `applyTo` defaults | ✅ Step 2 updated |

**Not implemented (by design):**
- A7: Do NOT auto-inject GOVERNANCE.md — 300+ lines, too expensive in context.
  Current approach (embedding relevant rules in agent prompts + critic checklists)
  is correct. Risk is drift, which `/validate-framework` detects.

**Files modified (4):**
- `agents/coordinator.agent.md` — context block, skill reminders in all prompts,
  unconditional retro consultation, updated description
- `prompts/resume.prompt.md` — added `agent: coordinator`
- `prompts/validate-framework.prompt.md` — uncustomized `applyTo` detection
- `README.md` — prompt taxonomy (3 tiers: entry points, reporting, utilities)

---

## 21) ✅ DONE — Governance Audit & Enforcement Hardening (2026-03-09)

Full team review of the AF against all 9 L1 Core Principles from GOVERNANCE.md.
Three subagents (planner, code-critic, test-critic) reviewed 3 principles each
in parallel. All 9 scored PARTIALLY ENFORCED. 12 recommendations produced和
implemented:

| # | Recommendation | Status |
|---|---|---|
| R1 | Activate Stop hook (test gate) | ✅ `stop-tests.ps1/.sh` + registered |
| R2 | Activate PostToolUse hook (secret scan) | ✅ `scan-secrets.ps1/.sh` + registered |
| R3 | Persist critic findings in YAML log | ✅ `review_details` field in documenter schema |
| R4 | Worker Uncertainty Protocol | ✅ BLOCKED format in test-writer, implementer, refactorer |
| R5 | Human-escalation skill for all producers | ✅ Assigned to test-writer, implementer, refactorer |
| R6 | Retro snippet as HARD gate for documenter | ✅ Added to quality-gates.instructions.md |
| R7 | Coordinator retro consultation | ✅ Step 0 reads `retros/auto/` for Full TDD |
| R8 | Fix R-SD-26 — remove ESCALATION.md reference | ✅ GOVERNANCE.md updated |
| R9 | Trivial tier minimal doc path | ✅ Coordinator Step 7 skips documenter |
| R10 | Remove `web/fetch` from implementer | ✅ Removed from frontmatter |
| R11 | Document credential scoping gap | ✅ Added to MANIFEST Least Privilege |
| R12 | Over-engineering check for code-critic | ✅ Added to Step 4 checklist |

**Files modified (14):**
- `hooks/agent-hooks.json` — added PostToolUse + Stop hooks (4 active total)
- `hooks/scripts/stop-tests.ps1/.sh` — new Stop hook scripts
- `hooks/scripts/scan-secrets.ps1/.sh` — new PostToolUse hook scripts
- `hooks/README.md` — updated to reflect 4 active hooks
- `MANIFEST.md` — hooks table + credential gap documentation
- `README.md` — hooks tree + summary table
- `GOVERNANCE.md` — R-SD-26 fix
- `coordinator.agent.md` — Step 0 retro consultation + Step 7 trivial path
- `documenter.agent.md` — YAML log schema `review_details` field
- `code-critic.agent.md` — over-engineering check
- `test-writer.agent.md` — uncertainty protocol + human-escalation skill
- `implementer.agent.md` — uncertainty protocol + human-escalation skill + web/fetch removal
- `refactorer.agent.md` — uncertainty protocol + human-escalation skill
- `quality-gates.instructions.md` — retro snippet HARD gate
- `skills/INDEX.md` — human-escalation references updated

---

## 22) ✅ DONE — Smoke Test Playbook (`/smoke-test`)

**Source:** All 3 agents (unanimous #1 priority)
**Impact:** CRITICAL | **Effort:** MEDIUM

Run a trivially simple, pre-defined canned task (e.g., "add a `clamp(value, lo, hi)` function with tests") through the full TDD pipeline. The task is intentionally minimal so any failure is attributable to framework plumbing, not task complexity.

**Problem:** The AF has never been exercised end-to-end on a real task (retro #2, open since 2026-02-18). 21 ideas implemented on an unvalidated foundation. `/validate-framework` checks structural integrity. `/simulate` predicts the workflow path. Neither proves the coordinator can actually invoke a subagent, receive a verdict, handle a rejection, or produce a YAML log.

**Proposed solution:** Create a `/smoke-test` slash command that:
1. Defines a canned task (no user input needed beyond "run it")
2. Instruments each coordinator step to report: subagent invoked, response received (Y/N), verdict parsed (Y/N), gate summary received (Y/N)
3. Produces a per-step **PASS / FAIL / SKIPPED** health report
4. On any FAIL, includes raw subagent output snippet for diagnosis
5. All changes on a disposable `agent/smoke-test` branch

**Risk:** May surface cascading failures — but that is the most valuable information the project can get right now.

---

## 23) ✅ DONE — Progress Narration

**Source:** Planner
**Impact:** HIGH | **Effort:** LOW

**Problem:** During a Full TDD workflow the user sees nothing between "I'm starting" and either the final report or an escalation. The coordinator runs 7+ subagent calls silently. If something goes wrong at Step 4, the user has waited through Steps 1-3 with no feedback.

**Proposed solution:** Mandatory progress narration protocol in the coordinator — after each subagent returns, emit a structured one-line status update before invoking the next subagent:

```
[Step 2/7] ✅ test-writer — 6 tests created, all FAIL (expected) | Next → test-critic
[Step 3/7] ✅ test-critic — APPROVED | Next → implementer
[Step 4/7] ❌ implementer — 2/6 tests still failing | Retrying (attempt 2/3)
```

On verdicts: show APPROVED / REJECTED (reason) / ESCALATE. On retries: show attempt count. On context budget YELLOW/RED: include in the narration line.

---

## 24) ✅ DONE — Supervised Execution Mode

**Source:** Planner
**Impact:** HIGH | **Effort:** MEDIUM

**Problem:** The gap between `/simulate` (read-only prediction) and `@coordinator` (full autonomous execution) is too large for a framework that has never run end-to-end. A wrong decision at Step 2 cascades through Steps 3-7.

**Proposed solution:** Add a supervised mode activated via keyword (e.g., `@coordinator --supervised <task>`). In supervised mode:
1. Each step executes normally (real subagent calls, real file changes)
2. After each step, pause and present result to the human: output summary, verdict, gate summary, and "Proceed to Step {N+1}? Reply **continue** or provide feedback."
3. If the human provides feedback, incorporate before invoking the next subagent
4. After 2-3 successful supervised workflows, recommend switching to autonomous

Creates a trust-building ramp: simulate → supervised → autonomous.

---

## 25) ✅ DONE — Verdict & Contract Parsing Hardening

**Source:** Planner + Test-Critic
**Impact:** MEDIUM | **Effort:** LOW

**Problem:** The coordinator parses critic responses by looking for `## {Type} Verdict: {APPROVED|REJECTED|ESCALATE}`. But subagents are LLMs — they may use different formatting, omit the verdict, bury it mid-response, or use unexpected words. If parsing fails silently, a REJECTED verdict might be treated as APPROVED. The coordinator has no fallback for unparseable verdicts.

**Proposed solution:** Defensive parsing protocol in the coordinator:
1. Search case-insensitively for `verdict:` anywhere (not just the first heading)
2. Accept APPROVED/REJECTED/ESCALATE regardless of surrounding formatting
3. If no verdict keyword found → treat as BLOCKED (not APPROVED). Narrate: `⚠️ Step {N}: unparseable verdict — treating as BLOCKED`
4. If Gate Summary missing → log warning, proceed with verdict only
5. If metrics missing → use `N/A` rather than hallucinating values

---

## 26) ✅ DONE — Rejection Feedback Quality Standard

**Source:** Test-Critic
**Impact:** HIGH | **Effort:** LOW

**Problem:** When a critic rejects work, the quality of that rejection feedback determines whether the retry succeeds. But there is no standard for actionable feedback. Current failure mode: critic says "tests are not meaningful" without specifics. Retry produces the same result. After 2 retries → escalation. Vague rejections waste context budget.

**Proposed solution:** Add a Rejection Feedback Contract to §13:
- Every REJECTED verdict must include: `findings` (list with file, location, severity BLOCKING/SHOULD-FIX/ADVISORY, suggestion), `blocking_count` (≥1 for REJECTED), `retry_guidance` (1-2 sentences)
- Coordinator validates the 3 fields before re-invoking the maker
- If findings are missing or non-specific → coordinator requests re-review with specifics
- Arbiter benefits: can compare specific findings against specific changes

---

## 27) ✅ DONE — Partial Failure State Machine

**Source:** Test-Critic
**Impact:** MEDIUM | **Effort:** LOW

**Problem:** The coordinator has ad-hoc per-step recovery logic with inconsistent failure handling. "Skip refactoring" is a silent quality degradation never flagged in the final report. WIP.md doesn't capture retry count or which attempts failed. Cascading failures are unhandled.

**Proposed solution:**
1. Define a workflow state enum: PLANNING, RED, RED_REVIEW, GREEN, REFACTOR, CODE_REVIEW, DOCUMENTING, COMPLETED, FAILED_{step}, SKIPPED_{step}
2. WIP.md captures: current state, retry count per step, failed attempt reasons, skipped steps with rationale
3. Final report includes a Workflow Health Summary: skipped steps, failed retries, degraded quality gates
4. State transitions documented in `workflow-lifecycle.instructions.md`

---

## 28) ✅ DONE — Skill Compliance Gate

**Source:** Code-Critic
**Impact:** MEDIUM | **Effort:** LOW

**Problem:** Idea 20 added skill injection ("read your relevant skills") but this is a polite request to an LLM. Under context pressure, LLMs skip optional preliminary reads. The entire skill system (38 files, INDEX.md, agent matrix) relies on agents voluntarily reading files. The AF's own lesson: "instructions without gates are suggestions."

**Proposed solution:** Add a SOFT gate to quality-gates.instructions.md for producer agents (test-writer, implementer, refactorer):
- Agent must include `Skills Read: [list]` in its Gate Summary
- If the line is missing or empty, the critic flags it as a SOFT gate failure
- If the producer claims no skills were relevant, that's acceptable — but must be explicit, not silent

---

## 29) ✅ DONE — Prune Unassigned Skills

**Source:** Code-Critic
**Impact:** MEDIUM | **Effort:** LOW

**Problem:** 20 of 38 skills (53%) are unassigned to any agent. They were bulk-extracted from AAIG during Idea 1 without evaluating per-project relevance. Examples: `ml-pipeline-design`, `model-evaluation`, `feature-engineering` — ML/MLOps skills in a data engineering project. They add scanning overhead, inflate INDEX.md, create cognitive load, and accumulate staleness.

**Proposed solution:**
1. Move unassigned skills to `skills/_available/` (library)
2. Active skills (referenced by ≥1 agent) stay in `skills/`
3. `/onboard-project` evaluates `_available/` against the project tech stack and recommends activating relevant ones
4. INDEX.md splits into "Active Skills" and "Available for Activation"
5. `/validate-framework` only deeply scans active skills

---

## 30) ✅ DONE — Non-Destructive `.github/` Installation

**Source:** Code-Critic
**Impact:** HIGH | **Effort:** MEDIUM

**Problem:** README step 1: "Copy the `.github/` folder into your project root." Every GitHub-hosted project already has `.github/` with workflows, CODEOWNERS, dependabot.yml, etc. Copying overwrites existing files. Additionally, AF's `copilot-instructions.md` is a template with `TODO:` placeholders — if the project had a working one, it's now gone.

**Proposed solution:**
1. Document clear file ownership boundary: AF owns agents/, hooks/, instructions/, prompts/, skills/, templates/, logs/, retros/, MANIFEST.md, GOVERNANCE.md. AF does NOT own workflows/, CODEOWNERS, dependabot.yml, etc.
2. `/onboard-project` checks for existing `.github/` — enumerates files, shows what AF will add, shows conflicts, offers to merge copilot-instructions.md
3. Add `.github/.af-manifest` listing AF-owned files for safe future updates

---

## 31) ✅ DONE — Token Budget Feasibility Pre-Flight

**Source:** Code-Critic
**Impact:** HIGH | **Effort:** MEDIUM | **Depends on:** Idea 22

**Problem:** Context Budget Awareness (Idea 15) uses heuristic thresholds: ≥5 calls → YELLOW, ≥7 → RED. A Full TDD workflow invokes minimum 7 subagents. Every non-trivial Full TDD will hit RED by completing its normal flow. The framework's flagship workflow is structurally incompatible with its own context budget system. The heuristics have never been validated.

**Proposed solution:**
1. Recalibrate heuristics after smoke test (Idea 22) provides real data
2. `/simulate` gains a "Context Feasibility" section: SINGLE-SESSION / MULTI-SESSION / AT-RISK
3. Coordinator Step 0 assesses feasibility: if plan has 5+ subtasks AND retries likely → suggest phased approach
4. Make feasibility advisory (SOFT), not blocking (HARD)

---

## 32) ✅ DONE — Human Troubleshooting Guide

**Source:** Planner
**Impact:** MEDIUM | **Effort:** LOW

**Problem:** When the first real workflow fails, the user has no documentation for diagnosis or recovery. The AF has extensive agent-facing docs but nothing for the human: "The coordinator escalated — what do I do?", "The stop-tests hook fails — how do I fix it?"

**Proposed solution:** Create `TROUBLESHOOTING.md` with symptom → cause → fix table:
- Setup issues (hook errors, tool-not-found)
- Workflow selection (wrong workflow chosen)
- Subagent failures (empty response, timeout, unparseable verdict)
- Gate failures (HARD gate BLOCKED, pytest not found)
- Escalation (coordinator escalates on first attempt)
- Resume issues (`/resume` finds no WIP, stale WIP.md)
- Hook issues (secret scan false positives)

Written for the human project owner — no agent jargon.

---

## 33) ✅ DONE — Quality Gate Audit Trail

**Source:** Test-Critic
**Impact:** MEDIUM | **Effort:** MEDIUM

**Problem:** Gate summaries are self-reported. The implementer says "HARD gates: 5/5 passed" but there's no evidence it actually ran pytest. The stop-tests hook only verifies the final state. Maker-Checker principle is violated at the meta-level: the gate summary itself is a self-check.

**Proposed solution:**
1. PostToolUse hook logs tool invocations to `gate-audit.jsonl` (session-scoped, not committed)
2. Coordinator cross-references audit trail against gate claims: if "tests pass" but no pytest call found → BLOCKED, not PASS
3. Only activate for Standard+ tiers (Trivial already skips critics)

---

## Implementation Priority

```
Phase 1 — Pre-flight (before first real run):
  25 (verdict hardening) → 26 (rejection feedback) → 23 (narration)

Phase 2 — First real run:
  22 (smoke test) → 32 (troubleshooting guide)

Phase 3 — Trust building:
  24 (supervised mode) → 27 (state machine) → 28 (skill compliance)

Phase 4 — Maturity:
  29 (skill pruning) → 30 (install safety) → 31 (token feasibility) → 33 (audit trail)
```

## 34) ✅ DONE — AF Deployment Scripts (2026-03-10)

Currently the readme states to COPY the .github and .vscode content into the project. That is sensible, but with that there are now two idenpendent copies. One in the project and one in the idependent AF. We want to avoid to clutter the project with the AF content (AF relates here to both the original AF and to its copy in the Project). On default, AF related documents must be separated for the project. E.g. logs concering the AF stay in the AF, plans are Project related and should find a specifed place there.
Is there a better approach for the AF deployment/integration into a project? There are to use cases i think:
1) one time deployment and continous usage of the AF copy in the project without the intent to feed back and improve the original AF.
2) Coupled deployment: integration into the project, but with feedback for improvement in the original AF

**Design decisions:**
- Evaluated 4 approaches: (A) Copy & Own, (B) Git Submodule, (C) Git Subtree,
  (D) Deploy Script + Manifest. Selected **Option D** — best balance of
  simplicity, safety, and both use cases.
- Git Submodule rejected: VS Code requires `.github/` at workspace root, but
  submodules checkout to a subdirectory. Path mismatch is unsolvable.
- Git Subtree rejected: viable but merges AF history into project, complex
  conflict resolution.

**What was done:**
1. Created `deploy.ps1` (Windows) and `deploy.sh` (macOS/Linux) at AF root
2. Both scripts support 4 modes:
   - **Install** (default): Copies AF-owned files to project `.github/` + `.vscode/`
   - **`-DryRun`/`--dry-run`**: Preview what would change without writing
   - **`-Diff`/`--diff`**: Bidirectional comparison (AF source ↔ project copy).
     Shows `→ project` (new in AF), `← AF` (added in project), `↔` (modified).
     Supports both UC1 (update check) and UC2 (feedback collection).
   - **`-Force`/`--force`**: Overwrite even customized files
3. **Customizable files protected**: `copilot-instructions.md` and
   `architecture.instructions.md` are never overwritten on update unless
   `-Force` is used (they contain project-specific customizations)
4. **Version tracking**: Deploy writes `.github/.af-version` with version +
   timestamp + source path. Diff mode compares versions.
5. Updated `.af-manifest` — added `.af-manifest` and `.af-version` as
   deployment metadata entries
6. Updated README Quick Setup — now references deploy scripts. Manual copy
   preserved in `<details>` fallback. Added "Updating the AF" subsection.
7. Non-AF files (`workflows/`, `CODEOWNERS`, etc.) are never touched.

**Files created (2):** `deploy.ps1`, `deploy.sh`
**Files modified (2):** `README.md`, `.github/.af-manifest`

## 35) ✅ DONE -- Project artefacts PLAN.md and WIP.md (2026-03-10)
I am not sure those artefacts follow my intent fully. If I am wrong say so.
1) Naming: the PLAN.md should be a template, there should not be a PLAN.md itself, the naming must associate to the corresponding (mandatory) git branch and should have an orderly naming format. R.g. it should sorty chrnologically either by starting with en enumeration or a date. Do we differentiate between feat/bugs/adrs? Then this should be a prefix to the file name. idealy the name of the branch should be represented also in the plans naming. In other words, there shluld not be a single file named PLAN.md, br for each task which would produce a PLAN.md there should be an individual plan, which will stay as human readable documentation.
Can we apply same thoughts to WIP? Or is it better to have a littereally names WIP.md file for easier reference as it only is a fail safe and keeps track of current work items.
2) location: project source is not a good location, i think project root /docs/<plans or somthing descriptive like it>/*
same for the WIP. However, this should not be hard enforced, the responsible agent should explore the exiting project (if present) for already present conventions!

**Design decisions (team consensus):**
1. **Plan naming:** `{type}-{YYYY-MM-DD}-{slug}.md` -- type prefix (`feat`/`fix`/`refactor`/`adr`/`review`), date for chronological sorting, slug from branch name.
2. **Plan location:** `docs/plans/` (default). Coordinator discovers existing project conventions at Step 0.
3. **WIP naming:** Keeps literal `WIP.md` -- ephemeral fail-safe, easy wildcard discovery.
4. **WIP location:** `docs/plans/WIP.md` -- co-located with plans, not cluttering project root.
5. **Coordinator determines filename** -- it creates the file, knows the date and branch name.
6. **Archival eliminated** -- plans already in their final location from creation. Removed the unimplemented "archives to `.github/logs/`" step.
7. **Convention discovery** -- coordinator Step 0 checks for existing `docs/` structure before defaulting.

**What was done:**
- Updated coordinator Step 0 with convention discovery (check `docs/plans/`, then alternative `docs/` conventions, then default).
- Updated coordinator Step 1 with plan filename composition: type prefix + date + slug from branch name.
- Updated coordinator Session Interruption: WIP.md now goes to `docs/plans/WIP.md`.
- Updated planner return format to mention coordinator determines filename.
- Updated documenter: references plan file path instead of literal `PLAN.md`.
- Rewrote git-workflow.instructions.md Planning Document section: naming convention, location, WIP checkpoint, archival removed.
- Updated MANIFEST.md: Planning Documents section, Artifact Lifecycle table, Handoff Data table.
- Updated quality-gates.instructions.md: plan file references instead of `PLAN.md`.
- Updated resume.prompt.md: WIP discovery in `docs/plans/`.
- Updated draft-pr-description.prompt.md: plan file in `docs/plans/`.
- Updated simulate.prompt.md: plan file reference and location.
- Updated TROUBLESHOOTING.md: WIP.md location guidance.
- Updated PLAN.md template: naming convention comments in header.
- Updated WIP.md template: added `Plan File` reference field, location comments.
- Updated README.md file map: template descriptions updated.

**Files modified (12):** `coordinator.agent.md`, `planner.agent.md`, `documenter.agent.md`, `git-workflow.instructions.md`, `quality-gates.instructions.md`, `MANIFEST.md`, `resume.prompt.md`, `draft-pr-description.prompt.md`, `simulate.prompt.md`, `TROUBLESHOOTING.md`, `templates/PLAN.md`, `templates/WIP.md`

## 36) ✅ DONE — Researcher Agent (2026-03-10)

While looking through the agents I realized, none have web/browsing capabilities. But often tasks should and must be researched! Either we add this capability to a suitable agent, or we add an agent specifically for that, a researcher and domain expert. The separation of concern principle may favor the second approach. What's the verdict of the team?

**Peer discussion:** Planner + code-critic (unanimous verdict).

**Verdict: Option B — Dedicated `researcher` agent (10th agent).**

Option A (adding `fetch` to planner or implementer) was rejected because:
- `fetch` was explicitly removed from implementer in Idea 21 (R10) under Least Privilege. Reverting is governance regression.
- Mixing research + task decomposition in the planner splits focus and makes outputs harder to audit.
- No existing agent's scope naturally absorbs "general external research" without violating Separation of Concerns.

Option B aligns with all governance principles:
- **Separation of Concerns** — research is pure information retrieval + synthesis, distinct from planning, coding, and reviewing.
- **Least Privilege** — `fetch` is held by exactly one agent, not scattered. Every web request is attributable to a single, auditable identity.
- **Maker-Checker** — research output can be reviewed by human or planner before influencing downstream work.
- **Precedent** — the arbiter is the structural analog: on-demand lateral agent, narrow scope, structured output, invoked outside the normal pipeline.

**Key design decisions:**
1. **Named `researcher`**, not "domain expert" — avoids scope creep from ambiguous "domain expert" framing.
2. **Read-only + fetch** — no write tools. Most constrained agent in the framework.
3. **User-invocable AND subagent** — standalone domain questions + coordinator pre-flight research.
4. **Conditional pre-flight** — coordinator invokes researcher only when the task mentions an external API, library, or standard not covered by existing skills.
5. **Anti-invocation rule** — coordinator must NOT invoke researcher for topics covered by skills, training data, or the codebase.
6. **Structured artifact output** — findings, citations, relevance assessment. Never raw fetched content (prevents prompt injection from adversarial web content reaching downstream agents).
7. **Human review gate (Standard+ tiers)** — research brief presented to human before proceeding to planner, mirroring the plan-review gate.
8. **Single invocation per workflow** — at the start, not mid-workflow.
9. **Skills assigned:** data-pipeline-design, data-modeling, data-quality (domain research context).

**Security mitigations (blocking prerequisites per code-critic):**
- Sandboxed output format: researcher produces structured brief in its own words, never verbatim quotes.
- No tool chaining: output returns to coordinator, which decides next steps.
- Source scope constraints: official docs, GitHub, standards bodies. No arbitrary blog crawling.
- No autonomous URL following from fetched content.

**What was done:**
- Created `agents/researcher.agent.md` — 10th agent with `fetch` + read-only tools, structured research brief return format, quality gates, anti-scope rules, prompt injection mitigations.
- Updated `agents/coordinator.agent.md` — added researcher to `agents:` list, Worker Agents table, workflow diagram. Added "Research Pre-Flight" section with invocation criteria + anti-invocation rules.
- Updated `MANIFEST.md` — added researcher to Worker Agent Roles table + Handoff Data Requirements table.
- Updated `skills/INDEX.md` — added researcher to Agent Skill Matrix.
- Updated `instructions/quality-gates.instructions.md` — added Researcher exit gates (3 HARD, 1 SOFT, 1 ADVISORY).
- Updated `README.md` — agent count 9→10, added researcher to file map.

**Files created (1):** `researcher.agent.md`
**Files modified (5):** `coordinator.agent.md`, `MANIFEST.md`, `skills/INDEX.md`, `quality-gates.instructions.md`, `README.md`

## 37) ✅ DONE — Programmatic Process Gates by Hooks (2026-03-10)

We defined a very elaborate agent framework. However, there are no very good measures to enforce those processes — the agent knows them, but may not follow them because some of the information drifted out of focus (there is lots of text). The idea is to implement gatekeepers programmatically, which ensure that important steps in the process are followed, e.g., git branch creation, creation of a plan, etc. Furthermore, the idea is to utilize the hook system. Discuss with peers and the team. Is that a good idea, are the hooks a good place to start. What gates should be defined. How to ensure no drifts, and so on ...

### Peer Discussion Results

**Planner assessment: APPROVED (scoped)** — The core insight is correct: there is a real gap between instructions-as-suggestions and enforcement-as-code. Hooks are the right mechanism for *stateless, file-level checks*. 5 of 9 mandated process steps are hookable; 2 are already implemented (test pass at Stop, dangerous command blocking). Proposed 6 subtasks across 3 phases, with Idea 33 (Audit Trail) as a prerequisite for the more advanced gates.

**Code-critic verdict: REJECTED (general proposal)** — Hooks are *tool-event processors*, not *workflow-state machines*. 7 of 10 proposed gates require workflow-state awareness that hooks structurally cannot have (phase ordering, conversational events, LLM-to-LLM communication). Only provenance marker enforcement (Gate 5) is a genuine, clean win. The correct enforcement layer for workflow-level compliance is the coordinator (which has context), not hooks. Adding stateful hooks would make the AF more brittle without meaningfully improving compliance.

### Synthesis & Verdict

Both peers **agree** on the core diagnosis (process drift is real) and on the fundamental limitation (hooks are stateless, single-event boundary enforcers — not orchestrators). The disagreement is on scope: how many gates are worth implementing via hooks.

**Resolution — Narrow scope, layered enforcement:**

The AF already has the right enforcement at the right layers for most process steps:

| Gate | Correct Home | Status |
|---|---|---|
| Dangerous commands | PreToolUse hook | ✅ DONE |
| Secrets in files | PostToolUse hook | ✅ DONE |
| Tests pass at session end | Stop hook | ✅ DONE |
| Session context injection | SessionStart hook | ✅ DONE |
| **Provenance markers** | **PostToolUse hook** | **⬜ TODO — extend scan-secrets** |
| **Branch advisory** | **SessionStart hook** | **⬜ TODO — extend session-context** |
| Plan creation / naming | Coordinator sequence | Already enforced by coordinator |
| Plan review gate (≥4 subtasks) | Coordinator pause | Already enforced (conversational) |
| Red-before-Green ordering | Coordinator phase state | Cannot enforce statelessly |
| Commit suggestions | Human-controlled | Unhookable by design |
| WIP on interruption | Emergency failsafe | Not a per-session hook target |
| Gate Summary / Skills Read | LLM text output | Invisible to hooks — critic layer |
| Workflow log (YAML) | Documenter agent gate | Already in quality-gates |

### Key Insight

> Hooks are good at: single-event boundary enforcement (secrets, dangerous commands, final-state verification, file content patterns).
> Hooks cannot: observe workflow phase, infer agent intent, inspect LLM-to-LLM communication, or enforce cross-event ordering without external state.

### Live Project Finding: Coordinator Drift Confirmed

During real project usage, the coordinator consistently dropped late-workflow steps:
- **Plan not discovered** — Step 0 convention discovery skipped
- **Plan not updated** — documenter never invoked to mark plan COMPLETED
- **No workflow log YAML** — documenter step forgotten entirely
- The "creative middle" (Steps 2–6: tests, implementation, review) executed reliably; the "bookkeeping bookends" (Steps 0, 7) were victims of context drift in the ~950-line coordinator.

This confirmed the code-critic's analysis: soft gates (instructions) alone are insufficient for bookkeeping tasks under LLM context pressure.

### Solution: The Bookend Pattern (Option D)

Evaluated 4 approaches:

| Option | Verdict | Rationale |
|---|---|---|
| A. Watchdog agent only | ❌ | Same single-point-of-failure: coordinator must remember to invoke it |
| B. Documenter role expansion | ❌ | Documenter already has broad scope; adding compliance checking splits focus |
| C. Enhanced Stop hook only | ❌ | Can detect but cannot create missing artifacts |
| **D. Bookend Pattern (hybrid)** | **✅** | 3-layer defense: coordinator → compliance-checker → Stop hook |

**Implemented: Bookend Pattern with 3 enforcement layers:**

```
Layer 1: Coordinator instructions → may drift under context pressure (SOFT)
Layer 2: Compliance-checker agent → mandatory bookend checkpoints (resilient SOFT)
Layer 3: Stop hook artifact check → cannot be bypassed (HARD advisory)
```

Each layer catches failures the previous layer missed:
- If coordinator follows its instructions → Layer 1 sufficient
- If coordinator forgets Step 7 → compliance-checker post-flight catches and remediates via documenter
- If coordinator forgets BOTH Step 7 AND compliance-checker → Stop hook emits warning the LLM sees

### What Was Done

1. **Created `compliance-checker.agent.md`** — 11th agent. Lightweight **read-only** watchdog with two modes:
   - **Pre-flight** (Step 0b): branch guard, plan directory verification, WIP state check
   - **Post-flight** (Step 7b): artifact verification (plan status, log YAML, retro snippet, provenance markers). Reports missing artifacts to the coordinator — does NOT invoke the documenter itself.
   - Tools: read-only only (most constrained agent in the framework). No subagent invocation — the compliance-checker cannot provide the rich context (step summaries, critic findings, metrics) that the documenter needs. That context exists only in the coordinator's conversation history.
   - **Design insight:** detect here, remediate there. The compliance-checker detects gaps; the coordinator — which has full workflow context — handles remediation by invoking the documenter.

2. **Enhanced Stop hook** (`stop-tests.ps1`, `stop-tests.sh`) — Layer 3 safety net:
   - Detects `agent/*` branch → checks for workflow log YAML, retro snippet, plan file COMPLETED status
   - Emits advisory WARNING (does not block session — that would be disruptive)
   - Message guides the LLM: "Was the documenter invoked? Run compliance-checker post-flight."

3. **Updated coordinator** (`coordinator.agent.md`):
   - Added compliance-checker to agents list and Worker Agents table
   - Updated workflow diagrams: both Full TDD and Quick Fix now show compliance-checker bookends
   - Added `COMPLIANCE_POST` workflow state
   - Added Step 0b (pre-flight) and Step 7b (post-flight) sections
   - Updated phase checkpoints with post-remediation commit
   - Updated narration examples to show 9-step flow

4. **Updated MANIFEST.md** — compliance-checker in Worker Agent Roles + Handoff Data tables
5. **Updated quality-gates.instructions.md** — compliance-checker exit gates (5 HARD, 2 SOFT)
6. **Updated README.md** — agent count 10→11, compliance-checker in file map
7. **Updated skills/INDEX.md** — compliance-checker (no skills — process checkpoint agent)

**Files created (1):** `compliance-checker.agent.md`
**Files modified (7):** `coordinator.agent.md`, `stop-tests.ps1`, `stop-tests.sh`, `MANIFEST.md`, `quality-gates.instructions.md`, `README.md`, `skills/INDEX.md`

### Remaining from Original Analysis

The 2 minor hook extensions identified in the initial discussion remain deferred:
- **Provenance marker check** in scan-secrets — ⬜ TODO (trivial, low priority)
- **Branch advisory** in session-context — ⬜ TODO (pure advisory)

## 38) ✅ DONE — Autonomous Local Git Execution (2026-03-10)

During live project work, discovered that no agent can actually execute git commands — they all only "suggest" them, requiring the human to manually run every `git checkout -b`, `git add`, `git commit` between phases. This creates excessive friction; 3–5 manual interventions per workflow for deterministic, reversible shell commands.

The user's stated intent: agents should autonomously handle routine local git (branch creation, staging, committing). The human retains control of merges into main, deletions, hard resets, and force pushes.

### Peer Discussion Results

**Planner assessment: Option A — Coordinator executes all local git (APPROVED)**

**Code-critic verdict: Option A APPROVED (with conditions) / Options B, C, D REJECTED**

**Unanimous consensus.** Both peers independently arrived at the same conclusion and the same architectural justification.

### Options Evaluated

| Option | Verdict | Rationale |
|---|---|---|
| **A. Coordinator (centralised)** | **✅ APPROVED** | Only agent with workflow context + terminal + output inspection. Commits are phase checkpoints, coordinator owns phases. |
| B. Each worker commits its own phase | ❌ REJECTED | Breaks Maker-Checker: workers commit before critic reviews. SoC violation: test-writer shouldn't touch commit history. |
| C. Coordinator + documenter split | ❌ REJECTED | Documenter lacks `getTerminalOutput` — blind execution. Dual git authority creates coordination overhead. |
| D. New dedicated agent | ❌ REJECTED | Over-engineering. Three deterministic shell commands require no domain expertise. |

### Design: The Local/Remote Principle

The unifying principle that replaces the Cardinal Rule:

> **Agents own the local working tree. The coordinator executes branch creation, staging, and commits at reviewed checkpoints. The remote (push) and all destructive operations (merge to main, branch delete, hard reset, rebase, force push) remain human-controlled.**

| Operation | Who | Rationale |
|---|---|---|
| `git checkout -b agent/{id}` | Coordinator (autonomous) | Local, fully reversible |
| `git add <specific-files>` | Coordinator (autonomous) | Explicit files only, never `git add .` or `-A` |
| `git commit -m "..."` | Coordinator (autonomous) | Local, reversible via `git reset --soft` |
| `git status`, `git diff` | Coordinator (autonomous) | Read-only |
| `git push` (any form) | **Human** | Crosses local→remote boundary |
| `git merge` | **Human** | Topology change; main protection |
| `git branch -d / -D` | **Human** | Irreversible deletion |
| `git reset --hard` | **Human** | Destructive state rewrite |
| `git rebase` | **Human** | History rewrite risk |

### Why Coordinator (Not Workers)

Key insight from both peers: **commits are post-review checkpoints, not per-worker outputs.** The commit `[agent:implementer] make tests pass` is triggered after the code-critic APPROVES, not when the implementer finishes. Only the coordinator knows a phase has cleared its gates. Worker agents should remain oblivious to version control.

The coordinator already has:
- Full workflow context (knows which phase completed, which critic approved)
- Terminal execution + output inspection (can diagnose failures)
- Error handling loops (can retry or escalate on git failures)
- Phase sequencing (knows exactly when each checkpoint is appropriate)

### Guard Rails (Prerequisites Before Implementation)

1. **Block `git push` in hook** — `block-dangerous.ps1` currently only catches `--force`. Must add `git\s+push\b` as a standalone pattern. This is a **HARD prerequisite** — without it, the safety boundary has a gap.

2. **Explicit permitted-command list** — Coordinator instructions must enumerate exactly: `git checkout -b`, `git add <files>`, `git commit -m`, `git status`, `git diff`, `git branch --show-current`. Any other git command is out of scope.

3. **Branch guard** — Before any commit, coordinator verifies it is NOT on `main`/`master`. Abort and escalate if so.

4. **Explicit staging only** — Never `git add .` or `git add -A`. Always `git add <specific expected files>`. Coordinator knows exactly which files each worker changed.

5. **Post-command verification** — After every git command, coordinator inspects terminal output to confirm success before proceeding.

### Files to Change (6)

| File | Change |
|---|---|
| `instructions/git-workflow.instructions.md` | Replace Cardinal Rule with local/remote principle. Update Commit Rules: remove "suggest" language for local ops. |
| `agents/coordinator.agent.md` | Git Workflow section: replace "suggest" with "execute". Add permitted-command list, branch guard, explicit staging rule, post-command verification. |
| `MANIFEST.md` | §7 Git Conventions: update git-is-human-controlled statement. Add two-tier model (local=coordinator, remote=human). |
| `hooks/scripts/block-dangerous.ps1` | Add patterns: `git push` (standalone), `git merge`, `git branch -[dD]`, `git rebase`. |
| `hooks/scripts/block-dangerous.sh` | Same additions for Unix. |
| `agents/documenter.agent.md` | Remove git commit suggestion responsibility (coordinator owns all checkpoints). |

### Quick Fix Simplification

Under autonomous git, Quick Fix becomes significantly cleaner:
1. Coordinator: `git checkout -b agent/{slug}`
2. After code-critic APPROVED: `git add <files>` + `git commit -m "[agent:implementer] fix: ..."`
3. After documenter: `git add <logs>` + `git commit -m "[agent:documenter] workflow log"`
4. Human's only git action: `git push` + merge review

For **Trivial** tier: collapse to single commit `[agent:coordinator] trivial fix: {description}`.

### Risk Assessment

| Risk | Mitigation |
|---|---|
| Coordinator stages wrong files (`git add .`) | Explicit file list only + scan-secrets hook as secondary defence |
| Commit before critic gate clears | Commit instructions tied to post-critic checkpoint, not post-worker |
| Commit on main branch | Branch guard pre-commit check |
| `git commit` fails (lock file, conflict) | Coordinator inspects output, retries or escalates |
| Prompt drift expands git authority | Permitted-command list in coordinator + `git push` hook blocks unauthorized push |
| Worker agent runs git commands directly | Workers have no git instructions; hook blocks push/merge regardless |

### Relationship to Other Ideas

- **Idea 37 (Process Gates)**: Branch advisory hook (extend `session-context.ps1` for main-branch warning) complements the branch guard here.
- **Idea 33 (Audit Trail)**: git commands logged in `gate-audit.jsonl` would provide evidence of actual commit execution.
- **Idea 27 (State Machine)**: Commit checkpoints naturally align with workflow state transitions (`RED → RED_REVIEW → GREEN` etc.).

---

## 39) ✅ DONE — Agent-Scoped Hooks for Phase Gate Enforcement (2026-03-11)

VS Code now supports **agent-scoped hooks** — hooks defined in `.agent.md`
frontmatter that only fire when that specific agent is active or invoked as a
subagent. Key detail: an agent's `Stop` hook also fires as `SubagentStop` when
invoked as a subagent. Also new: `SubagentStart`, `SubagentStop`, `PreCompact`
events.

### Peer Discussion (planner + code-critic)

**Planner** proposed 8 items (P1a–P4). **Code-critic** reviewed each critically.

| Proposal | Planner | Code-Critic | Consensus |
|---|---|---|---|
| **P1b** `implementer:Stop` (Green gate) | HIGH/LOW | APPROVE — highest ROI, real gap | **DO IT** (iteration 1) |
| **P1a** `test-writer:Stop` (Red gate) | HIGH/LOW | APPROVE w/ conditions (inverted logic) | DO IT (iteration 2) |
| **P1c** `documenter:Stop` (artifact gate) | HIGH/LOW | APPROVE w/ conditions (strict scope) | DO IT (iteration 2) |
| **P4** `coordinator:PreCompact` (checkpoint) | HIGH/MED | APPROVE w/ conditions (recovery aid) | DO IT (iteration 3) |
| **P2a** `coordinator:SubagentStart` (context injection) | HIGH/MED | DEFER (depends on P4) | DEFER |
| **P1d** `critic:Stop` (verdict check) | MED/LOW | REJECT (infeasible — verdict is conversational) | REJECT |
| **P2b** `coordinator:SubagentStop` (phase gates) | MED/HIGH | REJECT (redundant with P1a-P1c) | REJECT |
| **P3** Narrow compliance-checker | MED/MED | REJECT (creates coverage gap) | REJECT |

### Key Insights

1. **Per-agent Stop hooks fire as SubagentStop** when invoked by the coordinator —
   this gives us machine-verified phase gates at subagent exit, not at session end.
2. **Global Stop hook Gate 1 (pytest) must be retired atomically** with per-agent
   hook adoption — otherwise pytest runs 3x per workflow.
3. **P1d infeasible** — critic verdicts are conversational output, not file artifacts.
4. **P3 creates coverage gap** — compliance-checker keeps post-flight until all checks
   are mechanically covered elsewhere.
5. **PreCompact is a recovery aid, not automatic recovery** — post-compaction LLM
   reliability too low for self-guided checkpoint reload.
6. **SubagentStart `additionalContext` goes to coordinator**, not subagent — P2a's
   design assumption was incorrect.

### What Was Implemented (Iteration 1 — P1b)

| Item | Details |
|---|---|
| **New script** | `hooks/scripts/implementer-stop.ps1` + `.sh` — runs pytest, blocks if tests fail |
| **Agent hook** | `implementer.agent.md` gets `hooks.Stop` in frontmatter |
| **Global hook retired** | Gate 1 (pytest) removed from `stop-tests.ps1/.sh` — now artifact-only |
| **Settings** | `chat.useCustomAgentHooks: true` required in `.vscode/settings.json` |

### ⚠️ VS Code Bug — `Stop` Event Crashes in Agent-Scoped Hooks

**Discovered 2026-03-11:** Agent-scoped hooks (in `.agent.md` YAML
frontmatter) work correctly for 7 of 8 lifecycle events. The `Stop`
event alone crashes subagent invocations with `Cannot read properties
of undefined (reading 'length')`.

**Systematic test results (all 8 events):**

| Hook Event | Subagent Invocation |
|---|---|
| `Stop` | ❌ CRASHES |
| `SubagentStop` | ✅ Works |
| `PostToolUse` | ✅ Works |
| `PreToolUse` | ✅ Works |
| `SessionStart` | ✅ Works |
| `SubagentStart` | ✅ Works |
| `UserPromptSubmit` | ✅ Works |
| `PreCompact` | ✅ Works |

**Root cause:** VS Code docs state that an agent's `Stop` hook "is also
treated as `SubagentStop`" when the agent runs as a subagent. However,
the runtime crashes during initialisation before the event can fire.
Even a minimal agent with just `hooks: { Stop: [{ type: command, command: 'echo test' }] }`
crashes on subagent invocation.

**Workaround:** Use `SubagentStop` instead of `Stop` in `.agent.md`
frontmatter. Since all our hooked agents are subagents (`user-invocable: false`),
this is functionally equivalent.

**Current state:** All 4 agents (implementer, test-writer, refactorer,
documenter) use `SubagentStop` and have been verified working. The `hooks`
field is present in both AF source and project copies.

### Implementation Order (remaining)

```
Iteration 2:  ✅ DONE (see below)
Iteration 3:  P4 (PreCompact checkpoint) → verify across 2+ workflows
              H3 (researcher:PreToolUse credential-URL scan)
Future:       P2a (SubagentStart) → only after P4 proves stable
              H8 (planner:Stop plan quality gate) — evaluate
```

### What Was Implemented (Iteration 2 — P1a, H1–H5, P1c)

Second peer review (planner + code-critic) produced 6 new proposals.
4 approved, 1 approved with conditions, 1 rejected.

| ID | Agent:Event | What | Status |
|---|---|---|---|
| **P1a+H5** | `test-writer:Stop` | Red gate (tests must FAIL) + provenance marker check | ✅ DONE |
| **H2** | `test-writer:PreToolUse` | TDD phase isolation — blocks editing `mpusage/` | ✅ DONE |
| **H1** | `refactorer:Stop` | Tests must pass + no new `.py` files created | ✅ DONE |
| **H4** | `refactorer:PreToolUse` | Blocks `createFile`/`createDirectory` calls | ✅ DONE |
| **P1c** | `documenter:Stop` | Artifact gate — workflow log + retro must exist | ✅ DONE |
| **H6** | `documenter:SubagentStart` | Context injection — REJECTED (routing unverified) | ❌ REJECTED |

**Code-critic conditions applied:**
- H1: `git status` scoped to `.py` files under `mpusage/`/`tests/` (avoids false positives)
- H2: Broad tool-name pattern (`edit|create|write|file`), `deny` not `ask`
- H5: Only checks newly created files (not pre-existing test files)
- Global Gate 2 retained as session-end safety net (not retired atomically)

### Relationship to Other Ideas

- **Idea 37**: Bookend compliance pattern remains — per-agent hooks complement
  (not replace) the compliance-checker.
- **Idea 38**: Autonomous git unaffected — hooks enforce phase gates, git execution
  stays in coordinator.

---

## 40) ✅ DONE — Deploy Mechanism Improvements (2026-03-11)

Comprehensive overhaul of `deploy.ps1` and `deploy.sh` based on peer review
(planner proposed 10 improvements, code-critic evaluated each).

### Peer Review Summary

| ID | Proposal | Planner | Code-Critic | Result |
|---|---|---|---|---|
| D1 | Auto-detect merge baseline | LOW | REJECT (already implemented) | ❌ |
| D2 | Fix `-Diff` exit code bug | HIGH | APPROVE (critical) | ✅ DONE |
| D3 | Manifest annotations | MED | APPROVE (design with D9) | ✅ DONE |
| D4 | Content diff on CONFLICT | MED | APPROVE | ✅ DONE |
| D5 | Manifest validation | MED | APPROVE | ✅ DONE |
| D6 | Ephemeral backup | MED | RE-APPROVED (user refined) | ✅ DONE |
| D7 | JSON hash file | LOW | REJECT (jq dependency) | ❌ |
| D8 | Bash parity | HIGH | APPROVE (critical gap) | ✅ DONE |
| D9 | Absorb .vscode special case | MED | APPROVE (with D3) | ✅ DONE |
| D10 | Selective deploy | LOW | DEFER | ⬜ |

### What Was Implemented

**D2 — Fix -Diff exit code bug:**
- `-Diff` mode wrapped in `try/catch` (PowerShell).
- Explicit `exit 0` added at end of both Diff and Deploy modes.
- Root cause: `$ErrorActionPreference = 'Stop'` could convert non-terminating
  errors into exit code 1. Now handled gracefully.

**D3+D9 — Manifest annotation system:**
- `.af-manifest` supports annotations: `path  [annotation1, annotation2]`
- Three annotations: `[customizable]`, `[optional]`, `[vscode]`
- Eliminates hardcoded `$CustomizableFiles` array in deploy scripts.
- Eliminates hardcoded `.vscode/toolsets.jsonc` special case in both Diff
  and Deploy modes — now driven entirely by manifest.
- Files within manifest directories (e.g., `instructions/architecture.instructions.md`)
  are treated as annotation-only entries, avoiding duplicate processing.

**D4 — Content diff on CONFLICT:**
- `Show-ContentDiff` / `show_content_diff` helper displays up to 15 lines
  of diff output when CONFLICT detected.
- Uses `git diff --no-index` (preferred) or `Compare-Object`/`diff -u` fallback.

**D5 — Manifest validation:**
- After parsing, warns about manifest entries pointing to missing dirs/files.
- `[optional]` entries (dirs or files) silently skipped.
- Catches manifest drift (e.g., removed directory, renamed file).

**D6 — Ephemeral backup:**
- Creates `.af-backup-{timestamp}/` in project root before overwriting files.
- Backup created lazily (only when first file is about to be overwritten).
- Clean deploy (0 conflicts) → backup auto-deleted.
- Conflicts present → backup persists, path printed in summary.
- User refinement: supports non-git-tracked projects where git history
  isn't available as a recovery mechanism.

**D8 — Bash parity (deploy.sh full rewrite):**
- Previous deploy.sh (~238 lines) had NO 3-way merge. Code-critic flagged
  this as a **data loss risk** — UC2 on Linux/macOS silently overwrote
  project customizations.
- New deploy.sh (~590 lines) matches deploy.ps1 feature-for-feature:
  - Full 3-way merge via `.af-hashes` (associative arrays)
  - `--update-hashes` mode
  - PRESERVE / CONFLICT / PROTECT states
  - Manifest annotation parsing (`[customizable]`, `[optional]`, `[vscode]`)
  - Content diff on conflict (`git diff --no-index` or `diff -u`)
  - Manifest validation with optional suppression
  - Ephemeral backup with auto-cleanup

**Improved customizable file handling:**
- Customizable files now participate in 3-way merge instead of blanket PROTECT.
- AF changed, project unchanged → `PROTECT (AF has changes -- review manually)`
- AF unchanged, project changed → `PRESERVE (project customization)`
- Both changed → `CONFLICT` with content diff shown.

### Key Design Decisions

1. **Annotation syntax**: `path  [ann1, ann2]` — parseable, backward-compatible
   (plain entries still work), and self-documenting.
2. **Files within directories as annotation-only**: When a file like
   `instructions/architecture.instructions.md` appears in the manifest with
   `[customizable]`, it's for annotation only — the file is deployed via the
   `instructions/` directory traversal, not as a separate root file entry.
3. **Hash keys for vscode files**: Prefixed with `vscode/` to avoid collisions
   (e.g., `vscode/toolsets.jsonc` in `.af-hashes`).
4. **Backup is ephemeral by design**: Temp directory deleted on clean deploy.
   Only persists when conflicts require manual resolution.

### Relationship to Other Ideas

- **Idea 37**: Compliance-checker unaffected — operates on workflow artifacts.
- **Idea 38**: Autonomous git unaffected — hooks enforce phase gates only.
- **Idea 39**: Agent-scoped hooks unaffected — deployed via manifest directory
  traversal like all other agent files.