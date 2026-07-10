# Troubleshooting Guide

Common issues when using the Agent Framework, written for the human project
owner. Symptom → likely cause → fix.

---

## Setup Issues

### Hook fails on session start

**Symptom:** Error mentioning `agent-hooks.json`, `session-context`, or
PowerShell/bash script not found when starting a chat session.

**Cause:** Hook scripts reference paths that don't exist, or the shell
can't execute them (wrong line endings on Linux, missing execute permission).

**Fix:**
1. Check `.github/hooks/agent-hooks.json` — verify all `command` paths are
   correct relative to the workspace root.
2. On Linux/macOS: `chmod +x .github/hooks/scripts/*.sh`
3. On Windows: ensure PowerShell execution policy allows the scripts
   (`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`).
4. Run the hook script manually in a terminal to see the actual error.

### `pytest not found` / stop-tests hook fails

**Symptom:** The Stop hook (`stop-tests.ps1`/`.sh`) errors with "pytest not
found" or exits with a non-zero code.

**Cause:** The virtual environment isn't activated, pytest isn't installed,
or the test path in the script doesn't match your project.

**Fix:**
1. Activate your venv: `. .venv/bin/activate` or `.venv\Scripts\Activate.ps1`
2. Install pytest: `pip install pytest`
3. Check the test path in `hooks/scripts/stop-tests.*` — update if your tests
   aren't in `tests/`.

### Tool not available for an agent

**Symptom:** An agent reports a gate as BLOCKED because a tool (Pylance MCP,
terminal, etc.) is unavailable.

**Cause:** The tool isn't enabled in VS Code, the MCP server isn't running,
or the tool set in `.vscode/toolsets.jsonc` doesn't include it.

**Fix:**
1. Check VS Code settings — the tool/extension must be installed and enabled.
2. For Pylance MCP: ensure the Python extension is active and Pylance is
   responding (check the Output panel → Pylance).
3. Verify the tool set in `.vscode/toolsets.jsonc` includes the needed tool.

---

## Workflow Selection

### Wrong workflow chosen

**Symptom:** The coordinator picks Full TDD for a simple typo fix, or Quick
Fix for a complex feature.

**Cause:** The coordinator infers the workflow from your request description.
Vague descriptions lead to wrong classification.

**Fix:**
- Be explicit: "fix this typo in `helper.py`" → Trivial Fix.
- Or use a specific slash command: `/af-trivial-fix`, `/af-quick-fix`, `/af-tdd-feature`, `/af-review-code`.
- You can also override: "Use Quick Fix workflow for this."

### Coordinator asks for approval on a small task

**Symptom:** The plan has ≤ 3 subtasks but the coordinator still pauses for
approval.

**Cause:** The plan may touch files in > 2 architectural layers, introduce a
new module, or flag a risk as "high" — any of these trigger the approval gate.

**Fix:** This is by design. Review the plan and reply "proceed" or adjust.

---

## Subagent Failures

### Empty or no response from a subagent

**Symptom:** The coordinator reports that a subagent returned nothing, or
the progress narration shows `⚠️ unparseable verdict`.

**Cause:** The subagent may have hit a context limit, the model returned
an error, or the prompt was too large.

**Fix:**
1. Check context budget — if the narration line shows YELLOW/RED, context
   pressure may be the cause. Try `/af-resume` in a fresh session.
2. Reduce the task scope — break it into smaller pieces.
3. Check the model availability — the agent's preferred model may be
   unavailable. The next model in the priority list will be tried
   automatically, but if none are available, the call fails.

### Unparseable verdict (treated as BLOCKED)

**Symptom:** Progress narration shows `⚠️ Step {N}: unparseable verdict —
treating as BLOCKED`.

**Cause:** The critic subagent didn't include a `Verdict:` line with
APPROVED, REJECTED, or ESCALATE in its response. This can happen if the
model deviated from the return format.

**Fix:**
1. This is a **one-off model glitch** in most cases — the coordinator will
   escalate after BLOCKED, and you can re-run the step.
2. If it happens consistently for a specific critic, check that its
   `.agent.md` file includes the Return Format section with the verdict
   template.
3. Run `/af-validate-framework` to check for formatting issues in agent files.

### Subagent timeout / very slow response

**Symptom:** A subagent takes much longer than expected with no output.

**Cause:** Complex task, large codebase context, or model congestion.

**Fix:**
1. Wait — large tasks legitimately take time.
2. If it's stuck, cancel the chat and use `/af-resume` to pick up from the
   last completed step.

---

## Gate Failures

### HARD gate BLOCKED

**Symptom:** Gate Summary shows `BLOCKED gates: ...` and the coordinator
escalates.

**Cause:** A tool required for a HARD gate (pytest, Pylance, coverage tool)
is unavailable.

**Fix:**
1. Read the BLOCKED reason — it tells you which tool is missing.
2. Install or enable the tool.
3. Re-run the workflow (or `/af-resume` if a WIP checkpoint was saved).

### HARD gate FAILED after retries

**Symptom:** The coordinator reports a gate failure and escalates after 2
retry attempts.

**Cause:** The code genuinely doesn't meet the threshold (coverage too low,
complexity too high, tests still failing).

**Fix:**
1. Read the escalation details — they include specific failures and the
   metric values vs. thresholds.
2. Fix the underlying issue manually or adjust thresholds in MANIFEST.md
   § 5 if they're too strict for your project.
3. Re-run with `/af-resume`.

---

## Escalation

### Coordinator escalates on the first attempt

**Symptom:** The coordinator stops and escalates to you immediately, even
though it should retry.

**Cause:** The escalation may be triggered by a non-retryable condition:
ambiguous requirements, new architectural element, destructive action, or
security concern. Check the escalation trigger.

**Fix:**
1. Read the `### Recommended Options` in the escalation — the coordinator
   provides 2-3 options with trade-offs.
2. Choose an option and reply in chat.
3. If the escalation was wrong (e.g., a false positive on "new architectural
   element"), clarify: "This is an existing pattern, proceed."

### 3rd rejection escalation

**Symptom:** A critic rejected the maker's work 3 times and the coordinator
escalates.

**Cause:** The maker and critic genuinely disagree, or the task is too
complex for the current approach.

**Fix:**
1. Review the `### Attempts Summary` — each attempt shows what was tried
   and why it was rejected.
2. Options: (A) manually fix the issue and re-run, (B) adjust the approach,
   (C) simplify the task scope.
3. If the critic is being unreasonable, say so: "Override the critic, the
   implementation is acceptable because..."

---

## Resume Issues

### `/af-resume` finds no WIP

**Symptom:** `/af-resume` reports no paused workflows.

**Cause:** No `WIP.md` file exists in the plan directory (default:
`docs/plans/WIP.md`). Either the previous session completed normally,
or it ended without checkpointing.

**Fix:**
1. If you expected a WIP: check you're on the correct branch
   (`git branch --show-current`) and that `docs/plans/WIP.md` exists.
2. If the session crashed without checkpointing: start a new workflow.

### Stale WIP.md

**Symptom:** `/af-resume` finds a WIP.md but it references files or tests
that no longer exist.

**Cause:** Manual changes were made after the WIP checkpoint.

**Fix:**
1. Delete the stale `WIP.md` (in `docs/plans/` or wherever located)
   and start a fresh workflow.
2. Or update `WIP.md` manually to reflect the current state, then `/af-resume`.

---

## Hook Issues

### Secret scan false positives

**Symptom:** The PostToolUse secret scan hook flags a string that isn't
actually a secret (e.g., a test fixture, a hash constant, a base64 example).

**Cause:** The regex patterns in `scan-secrets.ps1`/`.sh` are broad by
design — they err on the side of flagging.

**Fix:**
1. Review the flagged string — if it's genuinely not a secret, proceed.
2. To reduce false positives: edit the scan script and add an ignore
   pattern for your specific case (e.g., `# nosecret` comment).
3. Do NOT disable the hook entirely — secrets in source code are a real risk.

### Hooks not running

**Symptom:** No hook output appears (no session context, no secret scan, no
test gate on stop).

**Cause:** Hooks may not be configured in VS Code, or `agent-hooks.json`
is not being picked up.

**Fix:**
1. Verify `.github/hooks/agent-hooks.json` exists and is valid JSON.
2. Check VS Code settings — agent hooks must be enabled.
3. Run `/af-validate-framework` — it checks for hook configuration issues.

---

## Quick Reference

| Problem | First Thing to Try |
|---|---|
| Hook error on start | Run the hook script manually in terminal |
| Wrong workflow | Use explicit `/af-tdd-feature`, `/af-quick-fix`, or `/af-trivial-fix` |
| Empty subagent response | Check context budget, try `/af-resume` in new session |
| Unparseable verdict | Usually transient — re-run the step |
| BLOCKED gate | Install the missing tool |
| Escalation surprise | Read the trigger reason in the escalation |
| No WIP found | Check you're on the right branch |
| Secret false positive | Review and add `# nosecret` if safe |
