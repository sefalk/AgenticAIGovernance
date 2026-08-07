---
name: tdd-orchestration
description: The coordinator's execution runbook — workflow state machine, git phase checkpoints, subagent context injection, the Step 1–7b delegation prompts with their retry and escalation policies, and interruption/cancellation recovery.
argument-hint: '[workflow-id] [step]'
metadata:
  activation:
    agents: [coordinator]
    priority: required
---

# TDD Orchestration Runbook

**Domain:** Workflow orchestration / TDD pipeline
**Primary consumer:** coordinator
**When to use:** Before Step 0 of any workflow that will execute steps — that is,
every workflow except Review Only and Plan Only.

`coordinator.agent.md` holds the routing layer: which workflow to select, which
agents it chains, and the always-on policy. This skill holds the executable
detail of those steps — the exact delegation prompts, retry limits, and
escalation branches.

> If this skill is not loaded, the coordinator still knows the agent sequence
> from the Workflow Selection diagrams. What it loses is precision: verbatim
> prompt templates, retry ceilings, and the structural-vs-functional rejection
> split. Read it before Step 1.

---

## 1. Workflow States

Every workflow maintains a current state. Track this internally and record
it in WIP.md on checkpoints.

| State | Description |
|---|---|
| `INVESTIGATION` | Step 1 (Quick Fix) — planner is writing investigation doc |
| `PLANNING` | Step 1 — planner is decomposing the task |
| `RED` | Step 2 — test-writer is creating failing tests |
| `RED_REVIEW` | Step 3 — test-critic is reviewing tests |
| `GREEN` | Step 4 — implementer is making tests pass |
| `REFACTOR` | Step 5 — refactorer is cleaning up |
| `CODE_REVIEW` | Step 6 — code-critic is reviewing implementation |
| `DOCUMENTING` | Step 7 — documenter is writing logs |
| `COMPLIANCE_POST` | Step 7b — compliance-checker post-flight verification |
| `COMPLETED` | All steps finished successfully |
| `FAILED_{step}` | A step failed after exhausting retries (e.g., `FAILED_GREEN`) |
| `SKIPPED_{step}` | A step was intentionally skipped (e.g., `SKIPPED_REFACTOR`) |

**Transitions:** `PLANNING → RED → RED_REVIEW → GREEN → REFACTOR → CODE_REVIEW → DOCUMENTING → COMPLIANCE_POST → COMPLETED`. On retry: state stays, counter increments. On failure (retries exhausted): `FAILED_{step}`, escalate. On skip: `SKIPPED_{step}`, advance.

- **Trivial Fix:** `GREEN → CODE_REVIEW → DOCUMENTING → COMPLIANCE_POST → COMPLETED`.
- **Quick Fix:** `INVESTIGATION → GREEN → CODE_REVIEW → DOCUMENTING → COMPLIANCE_POST → COMPLETED`.

---

## 2. Git Phase Checkpoints

The coordinator **executes** local git operations at these checkpoints. Who may
run git, branch naming, and the commit contract are in
`instructions/git-workflow.instructions.md`; the autonomy boundary table,
integration paths, R-SD-08 association, planning document lifecycle, and
pre-commit guards are in `skills/git-workflow/SKILL.md`.

**Full TDD Workflow:**

1. **Before Step 1:** Create feature branch and worktree (if enabled):
   - Create branch: `git checkout -b agent/{workflow-id}`
   - Bootstrap worktree (if `WORKTREE_ENABLED=true`): see Step 0d for full details
   - If worktrees disabled: proceed in main checkout
   - Or verify current branch relevance (Step 0c)
2. **After Step 1:** Commit the plan: `git add {plan_file}` then
   `git commit -m "[agent:planner] implementation plan: {slug — what is planned}"`
3. **After Step 3 (test-critic APPROVED):** Commit tests:
   `git add {test_files}` then `git commit -m "[agent:test-writer] failing tests: {module/suite — what scenarios are covered}"`
4. **After Step 4 (code-critic APPROVED in Step 6):** Commit implementation:
   `git add {source_files}` then `git commit -m "[agent:implementer] make tests pass: {what was implemented, key changes}"`
5. **After Step 5 (if changes made):** Commit refactoring:
   `git add {refactored_files}` then `git commit -m "[agent:refactorer] cleanup: {what was refactored and why}"`
6. **After Step 7:** Commit docs:
   `git add {log_files}` then `git commit -m "[agent:documenter] workflow log: {workflow-id}"`
7. **After Step 7b (if remediation occurred):** Commit remediated artifacts:
   `git add {remediated_files}` then `git commit -m "[agent:compliance-checker] remediated artifacts: {what was remediated}"`

**Trivial Fix:** Single commit `[agent:coordinator] trivial fix: {description}`.

**Quick Fix:** After planner returns investigation output, delegate file
creation to the **documenter** (same pattern as Step 1 plan persistence).
Then commit:
1. `git add {investigation_file}` then `git commit -m "[agent:planner] investigation doc"`
2. `[agent:implementer] fix: {description}`

**After final commit:** Narrate to the human:
`"All local commits complete on branch agent/{id}. Ready for git push when you are."`

---

## 3. Subagent Context Injection

When invoking any subagent, prepend this **context block** to the prompt:

> "Context: Complexity tier = {tier}. Target layers: {layers}.
> Quality thresholds: coverage ≥ {line_cov}% line, ≥ {branch_cov}% branch;
> complexity ≤ {cc_limit}.
> Work location: {work_location}. Branch: agent/{workflow-id}.
> Output verbosity: {output_verbosity} — apply it to your success path only;
> return full detail on any failure, rejection, or BLOCKED gate.
> Retro lessons (if any): {retro_lessons_or_none}.
> Before starting, read your relevant skills (listed in your Skills section)
> by calling read_file on each SKILL.md that applies to this task."

Where `{work_location}` is:
- `Worktree: {absolute_worktree_path}` (if `WORKTREE_ENABLED=true`)
- `Main checkout (worktrees disabled)` (if `WORKTREE_ENABLED=false`)

`{output_verbosity}` is `OUTPUT_VERBOSITY` from `af-env.conf` (default `full`).
Read it once at Step 0 and reuse the value for every subagent in the workflow —
mixing modes across steps makes returns inconsistent for no benefit.

Fill placeholders from the plan (or defaults from MANIFEST § 5 if no plan yet).
For Trivial Fix / Review Only where no plan exists, use: tier = Trivial,
default thresholds from MANIFEST § 5, layers = as determined from file list.
For Quick Fix where an investigation doc exists, use: tier = Standard minimum,
thresholds from the investigation doc or MANIFEST § 5 defaults.

---

## 4. Step 1: Plan

Use the **planner** agent as a subagent to decompose the user's request:

> "{context_block}
> Analyse the following request and create a detailed implementation plan.
> Follow the structure in `.github/templates/PLAN.md`.
> Include acceptance criteria, file list, and test requirements: {user_request}"

**After receiving the plan:** Delegate file creation to the **documenter** agent:

> "Persist the following plan as `{type}-{YYYY-MM-DD}-{slug}.md` in the plan
> directory (`{plan_dir}`). Create the directory if needed. Content:
>
> {planner_output}"

where: Type = `feat`/`fix`/`refactor`/`adr`/`review`.
Slug = branch name slug (e.g., `agent/fix-alignment-nulls` → `fix-alignment-nulls`).

Commit: `git add {plan_file}` then `git commit -m "[agent:planner] implementation plan: {slug — what is planned}"`.

**Decision gate:** Count the subtasks in the plan. If **any** of these are true,
present the plan to the human for approval BEFORE proceeding:

- 4 or more subtasks
- Introduces a new module, port, adapter, or orchestrator
- Touches files in more than 2 architectural layers
- Planner flags any risk as "high"

For plans with ≤ 3 subtasks, no new architectural elements, and no high risks,
proceed automatically.

---

## 5. Step 2: Write Tests (Red Phase)

Use the **test-writer** agent as a subagent (apply the Delegation Contract):

> "{context_block}
> Objective: write failing tests for this subtask.
> Acceptance criteria (verbatim): {criteria}.
> In-scope test files: {file_list}. Non-goals: no production code, no tests for
> other subtasks.
> Pay special attention to skills: unit-testing, property-testing.
> Create tests in the appropriate tests/ subdirectory.
> Run the tests and confirm they FAIL for the right reason.
> If blocked, return your partial tests and the specific blocker — do not guess."

---

## 6. Step 3: Review Tests

Use the **test-critic** agent as a subagent:

> "{context_block}
> Review the test suite for quality and meaningfulness.
> Test files created: {file_list}. Plan context: {plan_summary}.
> Produce an APPROVED, REJECTED, or ESCALATE verdict."

**On REJECTED:** Re-invoke **test-writer** with the critic's feedback:

> "The test-critic rejected your tests. Feedback: {feedback}.
> Fix the issues and re-run tests to confirm they still fail."

Then re-invoke **test-critic** to review again. Maximum 2 retries.

**On 3rd REJECTION:** Stop and escalate to the human with full context.

---

## 7. Step 4: Implement (Green Phase)

Use the **implementer** agent as a subagent (apply the Delegation Contract —
delegate **one subtask at a time**, not the whole plan):

> "{context_block}
> Objective: make the failing tests pass for this subtask.
> Acceptance criteria (verbatim): {criteria}.
> In-scope files: {file_list}. Non-goals: do not refactor unrelated code, add
> features beyond the acceptance criteria, or touch other subtasks' files.
> Test files: {test_files}. Follow architecture rules.
> Pay special attention to skills: hexagonal-architecture, error-handling.
> Run tests after implementation to confirm all pass.
> If blocked after a reasonable attempt, return your partial work and the
> specific blocker — do NOT widen scope or guess."

**If tests still fail:** Re-invoke **implementer** with the failure details:

> "Tests are still failing after your implementation. Failures: {test_failures}.
> Fix the issues and run tests again."

Maximum 2 attempts total. **On 2nd failure:**

- If failures suggest a **plan or test design issue**, re-invoke **planner**
  to re-decompose the problematic subtask.
- Otherwise, escalate to the human with full context.

---

## 8. Step 5: Refactor

Use the **refactorer** agent as a subagent (apply the Delegation Contract):

> "{context_block}
> Objective: clean up the implementation without changing behaviour.
> In-scope files: {file_list}. Non-goals: no behaviour changes, no new
> features, no new files.
> Run tests to confirm they still pass.
> If a cleanup step breaks tests, undo it and continue — never leave tests red."

Skip this step if the implementation is already clean (implementer reports
no cleanup needed).

**If refactorer reports tests broke:** The refactorer should undo and retry
internally (max 3 attempts). If it returns FAILED after 3 attempts, skip
refactoring and proceed to code review with the un-refactored code.
Do NOT block the workflow on refactoring failures.

---

## 9. Step 6: Code Review

Use the **code-critic** agent as a subagent:

> "{context_block}
> Review the implementation for architecture compliance, code quality,
> and quality gate metrics. Files changed: {file_list}.
> Plan context: {plan_summary}. Produce a verdict.
> Prior test results from implementer: {test_passed}/{test_total} passed,
> {line_cov}% line / {branch_cov}% branch coverage.
> If no code changed since Step 4, you may skip re-running the full suite."

**On REJECTED:** Determine whether the feedback is primarily **structural**
(code belongs in wrong layer, extract module, move function) or **functional**
(logic errors, missing tests, metric failures).

- **Structural feedback:** Re-invoke **refactorer** with the critic's feedback:

  > "The code-critic identified structural issues. Feedback: {feedback}.
  > Refactor to address these issues. Run tests to confirm they still pass."

  Then re-invoke **code-critic**.

- **Functional feedback:** Re-invoke **implementer** with the critic's feedback:

  > "The code-critic rejected the implementation. Feedback: {feedback}.
  > Fix the issues and run tests to confirm they still pass."

  Then re-invoke **code-critic**.

Maximum 2 retries total (across both structural and functional paths).

**On 3rd REJECTION:** Invoke the **arbiter** agent:

> "The implementer and code-critic cannot agree after 2 retries.
> Implementer's position: {implementer_summary}.
> Critic's objection: {critic_feedback}.
> Provide a binding recommendation or escalate to human."

If the arbiter returns ESCALATE, stop and present full context to the human.

### Gate Audit Trail (Standard+ tiers)

Cross-reference producer Gate Summary claims against actual subagent output
(test output present? coverage number visible? syntax check mentioned?).
If a HARD gate claim cannot be corroborated, downgrade to **BLOCKED** and
narrate: `⚠️ Step {N}: gate claim '{gate}' unverifiable — treating as BLOCKED`.
SOFT enforcement for Standard tier, HARD for Deep tier.

---

## 10. Step 7: Document

**Trivial tier:** Skip the documenter subagent. Instead, include
a single-line entry in the Final Report: "Trivial change — no
workflow log or retro snippet generated." Provenance markers are still
the implementer's responsibility (verified via their auto-check gate).

**Standard+ tier:** Use the **documenter** agent as a subagent:

> "Write the workflow log for this completed workflow.
> Steps taken: {step_summaries}. Files changed: {all_files}.
> Metrics: {final_metrics}. Verify provenance markers.
> Finalise the plan file at {plan_file_path}: update status to COMPLETED,
> fill in metrics, add final change log entry,
> **mark all completed subtask checkboxes as `[x]`**,
> and **add a Follow-Up section with unresolved critic findings
> (SHOULD-FIX / ADVISORY items not addressed during this workflow)**.
> **Critic findings:** Include review_details in the YAML log for each
> critic step. Findings: {critic_findings_summary}."

**If documenter returns FAILED or PARTIAL** (log not written, markers missing):

- Do NOT mark the workflow as fully complete.
- Present the issue to the human:

  > "Workflow code changes are complete, but documentation failed:
  > {documenter_error}. Manual action needed: {missing_items}."

---

## 11. Step 7b: Compliance Post-Flight (mandatory)

After Step 7 (or after Step 6 if the documenter was skipped or failed),
invoke the **compliance-checker** with `mode=post-flight`:

> "Run post-flight compliance checks.
> Workflow ID: {workflow_id}. Plan file: {plan_file_path}.
> Files changed: {all_files}. Complexity tier: {tier}."

The compliance-checker verifies plan file, workflow log YAML, retro snippet,
and provenance markers exist. It is **read-only** — detects gaps only.

**On PASS:** Proceed to final report and commit.

**On FAIL (missing artifacts):** The coordinator remediates:
1. **Confirm each reported path is genuinely absent on disk** — you have a
   terminal, the compliance-checker does not. `Test-Path` / `test -f` the
   resolved path. If the file is there and non-empty, the verdict was a false
   negative: record that in the final report and skip the rest.
   **Never overwrite an existing, non-empty artifact** in the name of
   recreating it — the documenter cannot tell "write fresh" from "replace
   verified content", so remediating a false negative destroys evidence
   rather than restoring it (issue #87).
2. If documenter never ran → invoke it now with the Step 7 prompt.
3. If documenter produced incomplete output → re-invoke for missing items only.
4. Optionally re-invoke compliance-checker to confirm.
5. If remediation fails after 1 retry → escalate to human.

This is a **mandatory bookend**. The Stop hook provides a third safety net
at session end.

---

## 12. Interruption and Recovery

### Session Interruption

If the workflow cannot be completed in the current session (token budget,
user departure, blocking issue), commit a `WIP.md` checkpoint:

1. Commit all in-progress code changes (even if tests are failing)
2. Create or update `WIP.md` in the plan directory discovered in Step 0
   (e.g., `docs/plans/WIP.md`) using the template from `.github/templates/WIP.md`.
   Include the plan filename in WIP.md so `/af-resume` can locate it.
3. Include **step history** in WIP.md: current state, retry count per step,
   failed attempt reasons, and skipped steps with rationale
4. Commit with: `git add docs/plans/WIP.md` then
   `git commit -m "[agent:coordinator] WIP checkpoint -- {phase}"`
5. Report the checkpoint to the human
6. Delete `WIP.md` when the workflow completes successfully

### Early-Exit Logging

If a workflow fails or is interrupted **before Step 7 (Document)**, the
coordinator writes a minimal log entry so steps 1–6 are not lost:

1. Create `.github/logs/{workflow-id}.yaml` with available data:
   - `workflow_id`, `status: FAILED | INTERRUPTED`, `timestamp`
   - `steps_completed`: list of steps with agent, verdict, outcome
   - `failure_reason`: why the workflow stopped
2. This partial log ensures traceability even when the documenter never runs.
3. The documenter, if later invoked via `/af-resume`, appends to this log
   rather than creating a new one.

### Task Cancellation

If the human User cancels a task mid-workflow:

1. Update `WIP.md` with `Status: CANCELLED` and the reason
2. Commit: `git add docs/plans/WIP.md` then
   `git commit -m "[agent:coordinator] task cancelled -- {reason}"`
3. Suggest to the human: if remote tracking exists, consider creating a PR
   titled `[ABANDONED] {branch-name}` and closing it without merging
4. Clean up: the human decides on branch deletion (local and remote)
5. The `CANCELLED` status prevents future agents from accidentally
   picking up this branch via `/af-resume`

---

## 13. Per-Return Protocols

These run **after every subagent returns**, in this order: parse the verdict,
narrate, then self-assess context health.

### Verdict Parsing

Parse critic/arbiter verdicts defensively: search case-insensitively for
`verdict:` anywhere in the response. Accept `APPROVED`, `REJECTED`,
`ESCALATE`, `RESOLVED`, `COMPROMISE`. If no verdict found → treat as
**BLOCKED** (never default to APPROVED). Missing Gate Summary → warn but
proceed. Missing metrics → record `N/A`.

### Rejection Feedback Validation

Before retrying after REJECTED, validate the critic provided `findings`
(file, location, severity, suggestion), `blocking_count` ≥ 1, and
`retry_guidance` per the Rejection Feedback Contract (MANIFEST § 13).
If missing or non-specific, re-invoke the **same critic** requesting
actionable detail — this does NOT count as a retry attempt.

### Progress Narration

Emit a structured one-line status update:

```
[Step {N}/{total}] {emoji} {agent_name} — {outcome_summary} | Next → {next_agent}
```

**Emoji key:** ✅ succeeded, ❌ failed/REJECTED, ⚠️ anomaly/BLOCKED,
🔄 retry. Append context budget status on YELLOW/RED.

Examples:
```
[Step 1/9] ✅ planner — 3 subtasks, tier=Standard | Next → test-writer
[Step 3/9] ❌ test-critic — REJECTED (2 trivial assertions) | Next → test-writer 🔄
[Step 4/9] ✅ implementer — 6/6 tests passing | Next → refactorer
[Step 7b/9] ✅ compliance-checker — post-flight PASS | ⚠️ Context: YELLOW
```

Do NOT skip narration — this is the user's only visibility into multi-step workflows.

### Context Budget Awareness

Self-assess context health:

- 🟢 **GREEN** — plenty of room → continue normally.
- 🟡 **YELLOW** — context pressure building → compress prior summaries to single lines.
- 🔴 **RED** — quality degradation risk → **HARD gate**: checkpoint to `WIP.md`, report, stop.

**Heuristics** (tokens not directly measurable): ≥ 7 subagent calls → YELLOW;
≥ 10 calls (incl. retries) → RED; context-confusion errors → RED.
