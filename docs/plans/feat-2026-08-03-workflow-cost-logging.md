# Feature: two-tier workflow cost logging (#50)

<!-- copilot:generated | planner | 2026-08-03 -->

- **Created:** 2026-08-03
- **Issue:** [#50](https://github.com/sefalk/AgenticAIGovernance/issues/50)
  (child of [#22](https://github.com/sefalk/AgenticAIGovernance/issues/22))
- **Branch:** `agent/50-workflow-cost-logging`
- **Complexity tier:** Standard
- **Status:** IN PROGRESS
- **Predecessor:** `review-2026-08-03-agent-debug-log-evaluation.md` (#46)

## Why this exists

#46 established that the agent debug log records every **billed** model request
with input, cached and output tokens plus the billed cost in
`copilotUsageNanoAiu`, and that subagent turns land in their own file. It also
established that this record is **transient**: `maxRetainedSessionLogs: 50`
evicts whole session directories, `maxSessionLogSizeMB: 100` truncates the
oldest entries inside one. Anything not extracted while the workflow runs is
gone, not merely inconvenient.

So the framework keeps its own slim record — locally, never committed. #49
shipped that storage rule, which was the hard prerequisite: writing a cost
block into a tracked file would commit usage data.

## Measurement that shaped the design

Run before writing code, because it decided the size of the script.

### The session no longer has to be guessed

VS Code exposes a template variable `VSCODE_TARGET_SESSION_LOG` holding the
absolute path of the current session's debug-log directory. Verified twice:

1. **Main agent and subagent both receive it, with the same value.** A probe
   subagent was asked to quote its own template-variable block; it returned the
   **parent** session directory, not a child path. Confirmed in the bundle:
   `getSessionDir` maps a child session id through `_childSessionMap` to
   `_resolveParentSessionDir`.
2. **Child runs land in that same directory** as
   `runSubagent-<agent>-<toolCallId>.jsonl`. The probe's own file appeared
   there within ~30 s (38 KB). One directory, one glob — no cross-directory
   join.

This dissolves trap **F2** (never pick the session by mtime, because parallel
worktrees write concurrently). The documenter is handed the path; nothing is
discovered heuristically, so nothing can be misattributed silently.

### But the variable is a pointer, not evidence

From `dist/extension.js`: `_getDebugLogsDir()` joins `storageUri` with the
debug-logs folder name **unconditionally** — it is not gated on
`agentDebugLog.fileLogging.enabled` — and `getSessionDir` falls back to
`joinPath(debugLogsDir, sessionId)` **without checking that the directory
exists**. A resolvable variable therefore says nothing about whether a log was
written.

**Consequence:** the collector validates for itself — directory exists,
`main.jsonl` exists, is non-empty, and parses. `available: false` plus a reason
is a normal outcome, not an error.

### Volume

`main.jsonl` for this session reached **25 MB** in about two and a half hours.
The collector streams line by line and never holds the file in memory, and no
agent ever reads a raw log into context (trap **F9**).

## Design

Two tiers measuring **different things**. Tier 1 is not a degraded copy of
Tier 2 — a fallback measuring the same thing worse inherits every failure mode
of what it replaces and adds error.

| Tier | Source | Availability | Answers |
|---|---|---|---|
| 1 — structural | The coordinator's own workflow | Always | How much *work*: steps, retries, escalations, subagent invocations per role |
| 2 — monetary | Agent debug log, harvested at the documenter step | Opportunistic | What it *cost*: tokens, cache rate, credits, per model |

They connect by **calibration**, not substitution: where Tier 2 exists it fits a
cost per unit of structure, so a Tier-1-only workflow can be estimated and
flagged `estimated: true` — never presented as a measurement.

### Boundaries settled before implementation

- **The script emits, the documenter writes.** `collect-session-cost.py` prints
  a YAML fragment to stdout and touches no log file. The documenter stays the
  only writer of `.github/logs/{workflow-id}.yaml`, and the script stays
  testable without a workflow.
- **Exit codes:** `0` whenever a block was emitted — including
  `available: false`. `2` only for a usage error (missing or unreadable
  argument). A vendor setting being off is not a failure of this framework.
- **Permanently ADVISORY.** A missing block never warns. The underlying setting
  is tagged `onExp`, so Microsoft can switch it off remotely; a gate hanging on
  a vendor flag produces exactly the wrong signal (trap **F7**).
- **Numeric allowlist only.** No field is copied from the log unless it is on an
  explicit allowlist of numbers and short identifiers. `inputMessages`,
  `userRequest` and tool arguments carry whatever was pasted into chat
  (trap **F5**).

## Subtasks

### 1. Session validation and coverage classification

Given a session directory, decide whether it can be totalled at all.

**Acceptance criteria**

- Missing directory, missing `main.jsonl`, or zero parseable lines →
  `available: false` with a distinct `reason`, exit `0`.
- Missing `session_start` span → `coverage: truncated` and **no** totals; the
  cap drops the oldest entries, i.e. exactly the plan and Red phases, so a total
  would look complete while biased downward (trap **F3**).
- Session's first event later than the workflow start passed in →
  `coverage: partial`.
- Otherwise `coverage: full`.

### 2. Aggregation

**Acceptance criteria**

- Parent and every `runSubagent-*.jsonl` in the same directory are summed
  (trap **F8** — subagent cost is absent from `main.jsonl`).
- `input_uncached = inputTokens - cachedTokens`; the two are never added
  (trap **F7** in the issue: `inputTokens` includes `cachedTokens`).
- Per-model breakdown of requests and credits — a session mixes opus, sonnet,
  haiku and gpt models.
- Requests without `copilotUsageNanoAiu` are counted as `unbilled_requests`,
  never dropped and never treated as `0`. Measured across 22 sessions: 133/136
  requests carry it, and all three exceptions are `backgroundTodoAgent`
  infrastructure calls with `status: ok`. Absent means *not billed*
  (trap **F10**).
- Compaction needs no special case — it is an ordinary `llm_request` with
  `debugName: summarizeConversationHistory`.

### 3. Emission

**Acceptance criteria**

- Output matches the shape in #50, plus `unbilled_requests`.
- `schema_version`, collector version, `sessions`, `coverage` and the
  `vscode`/`copilot_chat` versions from `session_start` are always present, so a
  committed number cannot outlive the conditions it was measured under
  (trap **F6**).
- A test asserts the emitted keys against the allowlist and fails on any key not
  on it.
- Unknown or missing attributes become `null`, never `0`.

### 4. Drift smoke test

**Acceptance criteria**

- One test asserts the expected attribute set (`copilotUsageNanoAiu`,
  `cachedTokens`, `inputTokens`, `outputTokens`, `model`).
- On failure the collector degrades to `available: false, reason: schema_drift`
  rather than emitting wrong numbers (trap **F8** in the issue).

### 5. Documenter integration and documentation

**Acceptance criteria**

- The collector runs once per workflow against the session of the run, with the
  workflow start time passed in.
- MANIFEST and `logs/README.md` describe the block and its ADVISORY status.
- CHANGELOG entry.

**Revised during implementation.** The plan assumed the documenter agent would
invoke the collector. It does not: its **Stop hook** does, after the artifact
gate passes, appending the script's output verbatim.

Two findings forced the change, both measured against the real log:

1. The hook input JSON carries `session_id` and `transcript_path`, and both name
   the **parent** session even when the hook fires inside a subagent. The
   session directory is therefore derivable
   (`<ws>/GitHub.copilot-chat/debug-logs/<session_id>`) without the
   `VSCODE_TARGET_SESSION_LOG` template variable — which the documenter, having
   no terminal tool, could not have acted on anyway.
2. Numbers routed through the documenter would be transcribed by a language
   model. The hook writes them verbatim, so they cannot drift.

The workflow start is the oldest commit on the branch, so a session that began
after the workflow yields `coverage: partial` without anyone having to pass a
timestamp. The block is a snapshot at documenter-stop time; the coordinator's
closing turns are not in it.

## Conventions

- Script: `.github/scripts/collect-session-cost.py`, dependency-free, standard
  library only — matching `check-context-budget.py`.
- Tests: `.github/scripts/test-session-cost.ps1`, matching
  `test-context-budget.ps1`. Fixtures are synthetic JSONL, never a copied real
  log.

## Risks

| Risk | Mitigation |
|---|---|
| The template variable is undocumented and could disappear | Collector also accepts an explicit path; absence yields `available: false`, not an error |
| A workflow spans several chat sessions | `sessions` is a list; earlier sessions the documenter cannot see produce `coverage: partial` |
| 25 MB and growing per session | Stream line by line; never load, never copy |
| Field names carry no compatibility promise | Drift smoke test degrades to Tier 1 |

## Out of scope

No database, no dashboard, no per-phase attribution, no historical backfill, no
committed usage data. `analyze-copilot-usage.py` stays **frozen, not deleted**
(verdict recorded in the #46 plan document) and `docs/metrics/usage-baseline.json`
is not regenerated.

## Change log

| Date | Change |
|---|---|
| 2026-08-03 | Created. Pre-implementation measurement of `VSCODE_TARGET_SESSION_LOG` folded into the design. |
| 2026-08-03 | Subtasks 1-4 implemented (32 checks green). Subtask 5 revised: the documenter's Stop hook appends the block, not the documenter — hook stdin carries the parent `session_id` and `transcript_path`, and a hook writes the numbers verbatim instead of via a language model. |
