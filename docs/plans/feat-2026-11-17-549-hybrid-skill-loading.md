<!-- copilot:generated | coordinator | 2026-11-17 -->

# Implementation Plan: hybrid skill loading for Copilot workers

**Workflow:** Feature Development
**Branch:** `agent/549-hybrid-skill-loading`
**Status:** IN_PROGRESS
**AF Version:** 2.0.0

## Context

Implement the owner-approved hybrid skill-loading policy in [AF #549](https://github.com/sefalk/AgenticAIGovernance/issues/549). Core skills should preload; conditional skills should remain on demand through the native `skill` tool. Usage reporting remains a separate #556 follow-up.

## References

- [AF #549 owner decision](https://github.com/sefalk/AgenticAIGovernance/issues/549#issuecomment-6943550873)
- [AF #447 Copilot skill/tool-loading measurements](https://github.com/sefalk/AgenticAIGovernance/issues/447#issuecomment-6942994174)
- `flavors/github-copilot/.github/skills/copilot-authoring/SKILL.md` — skill loading and managed regions

## Scope Assessment

- **Files affected:** approximately 25 (agent definitions, skill metadata, validators, tests, suite registration, budgets, changelog)
- **Layers touched:** Copilot agent configuration and validation/test tooling
- **Complexity tier:** Deep
- **Estimated size:** large (3 coordinated subtasks)
- **Not in scope:** Copilot session usage-reporting script; issue #556 review matrix; changes inside project-owned curated-skill managed regions
- **Risks:** High — the measured coordinator payload with two core skills is approximately 21,659 estimated tokens against the existing 9,450 per-agent ceiling. Any re-baselining must measure the actual new payload and preserve a documented margin; do not broaden the limit without human review.
- **Rollback plan:** revert the feature commits on this branch; no migration-time project data is rewritten by the change.

## Current Baseline

- Inventory: 64 skill directories, 30 active skills, 13 with `disable-model-invocation: true`.
- Copilot measurement: `skills:` preloads a skill; `tools: [skill]` exposes lazy loading; `deferred-tool-loading: false` has no effect.
- Current `check-context-budget.py` measures agent and always-on text, but does not add preloaded skill bodies to each agent's total.
- Current `check-curation-consistency.py` recognizes body skill paths as base skills; it must also recognize the new frontmatter representation.
- Coordinator's source-size estimate with `tdd-orchestration` and `git-workflow` preloaded: 21,659 estimated tokens versus the 9,450 ceiling. This is a conservative estimate to remeasure after the implementation.

## Subtasks

### 1. Assign core and conditional skills

- **Action:** Move mandatory role-core skills into `skills:` frontmatter; name conditional skills in `## Conditional Skills` and grant the native `skill` tool only to agents that need conditional loading. Audit all 13 invocation-disabled skills and remove the flag only where conditional use is required. Fix or remove stale framework-owned skill path references.
- **Files:** `flavors/github-copilot/.github/agents/*.agent.md`; affected `flavors/github-copilot/.github/skills/*/SKILL.md`
- **Layer:** Copilot agent configuration
- **Acceptance criteria:**
  - Every core preload and conditional name resolves to an active `SKILL.md`.
  - Conditional skills are not marked `disable-model-invocation: true`; preload-only and coordinator-only skills keep the flag where applicable.
  - Only agents with conditional skills receive the native `skill` tool.
  - No obsolete framework-owned `skills/<name>/SKILL.md` body reference remains; curated managed-region content is preserved.
- **Exit criterion:** The role-to-skill mapping is explicit in agent files and passes the skill-loading drift tests.
- **Tests needed:** Drift-check tests for valid and missing skills, disabled conditional skills, tool grants, and preservation of managed regions.
- **Dependencies:** none
- **Status:** TODO

### 2. Validate skill loading and curation consistency

- **Action:** Extend the existing skill validator or add a focused drift check for agent preloads and conditional skills; teach the curation consistency check to recognize frontmatter base skills without treating managed-region entries as framework-owned.
- **Files:** `flavors/github-copilot/.github/scripts/validate-skills.py` (or focused checker); `check-curation-consistency.py`; focused PowerShell test suite; `suite-scope.json`; `suite-budgets.json`
- **Layer:** Validation and test tooling
- **Acceptance criteria:**
  - A missing active skill and a disabled conditional skill fail with the responsible agent and skill named.
  - A valid preload and conditional skill pass.
  - Curated-region entries are excluded from framework validation; promoted base skills in `skills:` are not reported as curation drift.
  - The focused suite is registered and passes, and existing curation/skill-validation suites remain green.
- **Exit criterion:** All positive and negative drift cases pass deterministically using temporary fixtures.
- **Tests needed:** New checker cases plus `test-curation-consistency.ps1` and the existing skill-validation suite.
- **Dependencies:** Subtask 1
- **Status:** TODO

### 3. Count preloaded skill bodies in context budgets

- **Action:** Include each agent's preloaded skill bodies in the per-agent context estimate; measure the post-change maximum and update the configured ceiling only with a documented, reviewed margin.
- **Files:** `flavors/github-copilot/.github/scripts/check-context-budget.py`; `test-context-budget.ps1`; `flavors/github-copilot/.github/af-env.conf`; suite metadata; changelog
- **Layer:** Validation and configuration
- **Acceptance criteria:**
  - The guard adds only skills listed in that agent's `skills:` field, uses the existing character-based estimator, and reports missing or unreadable preloads as blocked/errors rather than silently undercounting.
  - Tests cover no preloads, one preload, multiple preloads, missing skill files, and line-ending/BOM invariance.
  - The measured maximum and selected ceiling/margin are reported before the budget value is changed.
  - Report declared conditional skill bodies separately: individual size, unique aggregate inventory (deduplicated across agents), and per-agent declared upper bounds. Optional positive AF/project individual and aggregate limits must enforce when set, and say UNBUDGETED otherwise.
  - Do not confuse static upper bounds with actual usage frequency or allocate billed session credits to individual skills.
- **Exit criterion:** `test-context-budget.ps1` and the focused regression selection pass with the measured post-change payload inside the approved ceiling.
- **Tests needed:** Focused context-budget cases; run the affected regression suites after each TDD phase.
- **Dependencies:** Subtasks 1 and 2
- **Status:** TODO

## Implementation Sequence

1. Subtask 1 → Subtask 2 → Subtask 3

## Quality Gates

| Gate | Target | Type |
|---|---|---|
| Skill-loading drift suite | All positive and negative cases pass | HARD |
| Curation consistency | Existing and new frontmatter cases pass | HARD |
| Context budget | Preloaded skill text counted; measured max within the approved ceiling | HARD |
| Agent configuration | Conditional grants match conditional-skill declarations; managed regions preserved | SOFT |

- **Suggested workflow:** Full TDD
- **Skills consulted:** `copilot-authoring`, `task-decomposition`, `git-workflow`, `tdd-orchestration`

## Plan Approval

**Approved by:** human (2026-11-17)
**Verdict:** APPROVED-WITH-FINDINGS

### Open Findings

- Measure the final post-change maximum and return the proposed ceiling/margin to the human before changing `AF_AGENT_CONTEXT_BUDGET_TOKENS`.

## Follow-Up

- Add a separate report over Copilot session `events.jsonl` for conditional skill invocation frequency under #556. Mandatory preloads cannot be evaluated by invocation frequency.
- Verified coverage gap: `collect-session-cost.py` reads Local `main.jsonl` debug spans and counts delivered skill catalogue definitions, not native skill activations. `report-skill-reads.py` counts workflow-level `read_file` evidence; it does not count native Copilot `skill` calls. Neither supplies conditional skill invocation frequency. #556 must report per-agent skill activation counts with log coverage and distinguish requests after loading/cache effects from one-off body size; per-skill credits are not observable from request-level billing.
- Static measurement after optimization: AF always-on 2,728 tokens; maximum agent/preload baseline 15,476 (`ado-work-item-manager`); largest conditional skill 5,954 (`tdd-orchestration`); unique declared conditional inventory 41,132; coordinator conditional sum 28,947 and baseline + declared skills 37,661. These are characters/4 estimates, not billed counts.
- Budget decision: human approved preload baseline 18,600; individual conditional skill 7,150; unique conditional inventory 49,400 (+~20%, rounded up). The agent default/config and AF conditional skill config now use those values. Unset conditional skill limits remain explicitly UNBUDGETED in upgraded/custom configurations. The inventory ceiling does not replace a runtime context monitor.
- Verification at the decision checkpoint: context-budget regression 127/128 checks pass; only the real-payload check fails against the unchanged 9,450 ceiling. Native skill-loading and suite-selection suites pass; validator passes all 64 skills; changelog fragments validate; whitespace checks pass. Strict lint reports two pre-existing complexity findings (`_catalogue` and `main`); new parser complexity and formatting findings were fixed. No phase commit or budget override was attempted while the real-payload gate is red.
- Verification after budget approval: context-budget regression passes 128/128 checks, including staged conditional enforcement and the real payload. Skill-loading, curation-consistency, suite-selection and suite-budget suites pass; 64-skill validation, changelog fragments and whitespace checks pass. Strict lint is format-clean with only the same two pre-existing complexity findings. The implementation remains uncommitted on the feature worktree, pending the wider workflow review/delivery; no main-checkout changes, push or merge were made.

## Change Log

| Date | Agent | Change |
|---|---|---|
| 2026-11-17 | coordinator | Initial draft based on #549 owner decision and measured payload estimates |
| 2026-11-17 | coordinator | Optimized preloads; added separate conditional skill inventory gates and declared per-agent bounds; verified legacy usage-reporting gap; owner approved 18,600 / 7,150 / 49,400 limits |
