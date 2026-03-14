---
name: smoke-test
description: 'Run a canned task through the full TDD pipeline to verify framework plumbing. No user input needed — just run it.'
agent: coordinator
tools:
  - agent
  - todo
  - search
  - read
  - edit
  - execute/runInTerminal
  - execute/getTerminalOutput
  - read/terminalLastCommand
  - read/terminalSelection
---

# Smoke Test — Framework Health Check

Run a **trivially simple, pre-defined task** through the full TDD pipeline
to verify that every framework component works end-to-end.

## Canned Task

> "Create a pure function `clamp(value, lo, hi)` in the domain core that
> constrains a numeric value to the range [lo, hi]. Include unit tests
> and property-based tests."

**Do NOT ask the user for a task.** Use the canned task above. The purpose
is to test framework plumbing, not task complexity.

## Instructions

1. **Create a disposable branch:** Suggest `agent/smoke-test` to the human.
2. **Run the Full TDD Workflow** (all 7 steps) using the canned task.
3. **Instrument every step** — after each subagent returns, report a
   structured health line in addition to the normal progress narration:

```
[Smoke] Step {N} ({agent}): invoked={Y/N} | response={Y/N} | verdict={APPROVED/REJECTED/BLOCKED/N-A} | gate_summary={Y/N}
```

4. **On any FAIL** (subagent not invoked, no response, unparseable verdict,
   missing gate summary): include the first 10 lines of the subagent's raw
   output (or the error message) for diagnosis.
5. **Do NOT retry excessively** — if Step 2 (test-writer) fails, still
   attempt Step 3 (test-critic) to test critic invocation separately. If
   a step cannot run at all (no input from prior step), mark it SKIPPED.

## Health Report

After the workflow completes (or fails), present a summary:

```markdown
## 🔬 Smoke Test Health Report

| Step | Agent | Invoked | Response | Verdict | Gate Summary | Status |
|------|-------|---------|----------|---------|-------------|--------|
| 1 | planner | ✅ | ✅ | N/A | ✅ | PASS |
| 2 | test-writer | ✅ | ✅ | N/A | ✅ | PASS |
| 3 | test-critic | ✅ | ✅ | APPROVED | ✅ | PASS |
| 4 | implementer | ✅ | ✅ | N/A | ✅ | PASS |
| 5 | refactorer | ✅ | ✅ | N/A | ✅ | PASS |
| 6 | code-critic | ✅ | ✅ | APPROVED | ✅ | PASS |
| 7 | documenter | ✅ | ✅ | N/A | ✅ | PASS |

### Overall: {PASS | PARTIAL | FAIL}
- Steps passed: {N}/7
- Steps failed: {N}/7
- Steps skipped: {N}/7

### Failures (if any)
- **Step {N} ({agent}):** {what went wrong + raw output snippet}

### Recommendations
- {What to investigate or fix before running real workflows}
```

## After Completion

- If PASS: The framework is validated — recommend the human try a real task.
- If PARTIAL/FAIL: List specific failures and reference `TROUBLESHOOTING.md`
  for diagnosis steps.
- **Clean up:** Suggest the human delete the `agent/smoke-test` branch
  (the `clamp` function was never meant to be kept).
