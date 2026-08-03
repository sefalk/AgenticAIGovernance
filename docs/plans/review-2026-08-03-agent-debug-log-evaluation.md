# Review: Agent Debug Log evaluation (#46) and self-logging concept

<!-- copilot:generated | planner | 2026-08-03 -->

- **Created:** 2026-08-03
- **Issue:** [#46](https://github.com/sefalk/AgenticAIGovernance/issues/46)
- **Branch:** `agent/46-debug-log-evaluation`
- **Complexity tier:** Standard (measurement + design evaluation, no production code)
- **Status:** COMPLETED (measurement) / PROPOSAL (self-logging)

## Why this exists

Issue [#28](https://github.com/sefalk/AgenticAIGovernance/issues/28) concluded
that per-turn foreground usage is not recorded well enough to attribute cost to
an AF workflow. That conclusion was true **for the `chatSessions` store** and was
generalised — silently — into "Copilot does not persist this". The VS Code
setting `github.copilot.chat.agentDebugLog.fileLogging.enabled` writes a second,
independent store. #28 never looked at it with the setting switched on, because
with the setting off that store contains nothing but `session_start` spans.

#46 was therefore framed as a **measurement**, not an implementation: answer
coverage first, and stop if coverage fails.

## Measurement

Session `053fc66d-c44e-4fa8-94c4-ca2f2feddede`, VS Code 1.131.0 /
copilot-chat 0.59.0, one `Explore` subagent invocation, 23 model round-trips.
Probe: ad-hoc Node script over the session directory (not committed — see
*Scope discipline*).

| # | Pre-registered question | Result | Evidence |
|---|---|---|---|
| Q1 | One event per turn, or sampled? | **Per request. 23/23.** | `llm_request` count equals `turn_start` count; every one carries `copilotUsageNanoAiu` (100 %) |
| Q2 | Input/cached/output? Billed or list price? | **All three, plus billed cost** | attrs: `inputTokens`, `cachedTokens`, `outputTokens`, `ttft`, `maxTokens`, `model`, `copilotUsageNanoAiu` |
| Q3 | Subagent attribution mechanism? | **Own log file, three redundant joins** | `runSubagent-<agent>-<toolCallId>.jsonl`; `child_session_ref` event; `tool_call` → `subagent` span via `parentSpanId`; child `sid` == tool-call id |
| Q4 | Join to an AF workflow id? | **Yes, via our own hooks** | `hook` events carry `command/input/output`; `SessionStart` output is our `session-context.ps1` payload incl. branch and last commit |

Supporting detail that changes how the numbers must be read:

- `inputTokens` **includes** `cachedTokens` (request *N*'s `cachedTokens`
  matches request *N−1*'s `inputTokens`). Summing both double-counts.
- The subagent runs a **different model** (`claude-haiku-4.5`, `debugName:
  tool/runSubagent-Explore`) than the main agent (`claude-opus-5`). Totals in
  `main.jsonl` **exclude** the child. A collector that reads only `main.jsonl`
  understates every workflow that delegates — which is every AF workflow.
- Measured cost of the measurement session: 23 requests, 1.32 M input /
  1.20 M cached / 15 k output, **104.0 credits ($1.04)** — 86.5 main,
  17.5 subagent.

### Consequence for #28

`copilotUsageNanoAiu` is the same billed ground truth as `total_nano_aiu` in the
`chatSessions` store, but present on **every** request rather than a ~0.35
per-file sample. The `models.json` list-price path — and its measured +10.7 %
overstatement — is obsolete wherever this log exists.

> The repeated failure mode is worth naming, because this is its second
> occurrence in a week: a finding that was correct about *one source* was
> recorded as a fact about *the world*, and then quoted rather than re-measured.
> #28 fixed the instance (the hardcoded "~2 %" now computes at runtime). It did
> not fix the class. The class is fixed only by writing down the scope of a
> negative finding next to the finding itself — "not in store X, untested in
> store Y" — which is what this document does for its own conclusions below.

### Unplanned finding, directly relevant to #44

`generic: "Resolve Customizations"` logs, per request, every instruction file
with a verdict and a reason:

```
[applying] git-workflow.instructions.md — automatically attached as pattern is **
[skipped]  architecture.instructions.md — applyTo 'mpusage/**/*.py' did not match any attached files
```

and `generic: "Custom Instructions"` separates what entered context from what
was offered for on-demand loading. [#44](https://github.com/sefalk/AgenticAIGovernance/issues/44)
was scoped as "model the conditional worst case and tighten `applyTo`". The
conditional set is now **observable per request**, so #44 can measure the actual
attach rate instead of assuming it. The `implementer`'s effective 13,089 tokens
was a computed upper bound; how often that bound is reached is now answerable.

`discovery` events additionally list loaded agents, instructions, skills, slash
commands and hooks with resolution timings. They repeat once per *Resolve
Customizations* pass — deduplicate before counting.

## Proposal: AF logs its own cost basis

The debug log is **transient by design**: `maxRetainedSessionLogs: 50` evicts
the oldest session directories, and `maxSessionLogSizeMB: 100` truncates within
a session. Any analysis that is not extracted at the time of the workflow is
not merely inconvenient later — it is impossible. That is the argument for the
framework keeping its own slim record.

The workflow log `.github/logs/{workflow-id}.yaml` already exists and already
carries `summary.retries`, `summary.escalations`, `summary.total_steps`. The
proposal is an extension of that artifact, not a new one.

### Two tiers, deliberately different in kind

| Tier | Source | Availability | What it answers |
|---|---|---|---|
| **1 — structural** | The coordinator's own workflow | Always. No vendor dependency. | How much *work* did this cost: steps, retries, escalations, subagent invocations per role, wall-clock per phase |
| **2 — monetary** | Agent debug log, harvested at workflow end | Opportunistic | What it actually cost: tokens, cache hit rate, credits, per model |

The important design point is that **Tier 1 is not a degraded copy of Tier 2**.
A rudimentary fallback that measures the same thing worse would inherit all of
Tier 2's failure modes and add error. Tier 1 measures something the framework
knows first-hand and that no vendor setting can take away.

The two connect through **calibration**: where Tier 2 exists, it fits a cost per
unit of structure (credits per subagent invocation, by role and model). Once
enough workflows carry both, a Tier-1-only workflow can be *estimated* — clearly
flagged `estimated: true`, never presented as a measurement. If Tier 2 vanishes
tomorrow, the estimates degrade gradually and visibly rather than the metric
disappearing.

### Shape of the added block

Roughly a dozen numeric fields appended to the existing `summary`:

```yaml
cost:
  schema_version: 1
  collector: "collect-session-cost.py@<version>"
  available: true            # false + reason => Tier 1 only
  coverage: full             # full | partial | truncated
  sessions: ["053fc66d…"]    # provenance, plural by construction
  requests: 23
  tokens: { input_uncached: 122710, cached: 1197463, output: 14941 }
  credits: 104.0
  by_model:
    claude-opus-5:   { requests: 7,  credits: 86.5 }
    claude-haiku-4.5: { requests: 16, credits: 17.5 }
  environment: { vscode: "1.131.0", copilot_chat: "0.59.0" }
```

## Critical evaluation — what can go wrong

| # | Trap | Why it bites | Mitigation |
|---|---|---|---|
| F1 | **Session ≠ workflow** | One chat session can span several workflows; one workflow can span several sessions — the handoff that produced this document is itself an instance. Summing a directory and labelling it "workflow cost" yields an authoritative-looking wrong number. | Select events by time window (workflow start → end) **and** repo cwd; record `sessions` as a list and `coverage: partial` when the window is not fully covered |
| F2 | **Picking the wrong session directory** | Newest-mtime is the obvious heuristic and it breaks exactly where AF is strongest: 3–5 parallel worktrees mean several concurrent sessions. Misattribution is silent. | Content-based match on `hook` event `input.cwd`, never mtime. Note the branch in `SessionStart` is the branch *at session start*, which may precede the workflow's branch |
| F3 | **Silent truncation** | The 100 MB cap drops the **oldest** entries. A long workflow loses plan and Red phases and keeps the expensive Green phase — the total looks complete and is biased downward. | Detect a missing `session_start` span; set `coverage: truncated` and refuse to emit a total (per #12: silence must not read as success) |
| F4 | **Transience** | 50 retained sessions is a rolling window. There is no "analyse it later". | Harvest at the documenter step, in the same workflow. Accept that history before today is unrecoverable — do **not** backfill |
| F5 | **Secrets and PII** | The log contains `userRequest`, full `inputMessages`, tool arguments and results, and absolute paths carrying the user id and corporate storage paths. Anything pasted into chat is in there. | Numeric allowlist only. No text field is ever copied. Raw logs are never copied into the repo, not even temporarily |
| F6 | **The caption problem** | A committed number stops being a measurement and becomes a quotable fact — the exact mechanism that made #28 wrong for four months. | Every block carries `schema_version`, `collector` version, `sessions`, `coverage`, and environment versions. The block is generated, never hand-edited |
| F7 | **Vendor dependency** | The setting is experimental and `onExp` — Microsoft can toggle it server-side without notice. | Collector is opportunistic: absent log ⇒ `available: false` + reason, workflow continues. **Never a HARD gate** — a vendor experiment must not be able to fail our workflows |
| F8 | **Schema drift** | `copilotUsageNanoAiu`, `cachedTokens`, `child_session_ref` are preview-internal names with no compatibility promise. | Missing fields become `null`, never zero. Record `vscodeVersion`/`copilotVersion` from `session_start` so a drift is diagnosable after the fact. One smoke test asserts the expected field set; when it fails, degrade to Tier 1 rather than emitting wrong numbers |
| F9 | **The observer costs more than the observed** | If an *agent* reads log files into context to summarise them, the measurement costs more than what it measures. This session's own subagent file is 1.5 MB. | The collector is a script. Its output is the YAML block. No agent ever reads a raw log file |
| F10 | **Zero is not "free"** | A workflow with `available: false` and a workflow that genuinely cost nothing are indistinguishable if the field is absent or 0. | Absent measurement is `null` + reason, never `0` |

### Scope discipline — what is deliberately not built

- No database, no dashboard, no aggregation service.
- No per-phase (Red/Green/Refactor) attribution in v1. It is feasible via
  timestamps and it roughly doubles the complexity for a question nobody has
  asked yet.
- No committed raw logs (size, and F5).
- No historical backfill — the logs did not exist.
- No quality gate. The block is ADVISORY, permanently.
- The ad-hoc probe used for this measurement stays a temp file. A throwaway
  script that gets committed becomes a maintained script.

### Effort

One script (~150–200 lines, no dependencies, following the exit-code
convention `0 ok / 2 blocked` of the existing checks), one smoke test, one
additional documenter step, ~12 lines of schema. Per workflow the recurring
cost is a single script invocation. Calibration is re-run occasionally, not
per workflow — and only becomes relevant once Tier 2 data actually accumulates.

## Follow-up

- Implementation of the two-tier collector — needs its own issue under
  [#22](https://github.com/sefalk/AgenticAIGovernance/issues/22); not created
  as part of this evaluation.
- [#44](https://github.com/sefalk/AgenticAIGovernance/issues/44) should be
  re-planned against measured attach rates rather than the computed worst case.
- [#43](https://github.com/sefalk/AgenticAIGovernance/issues/43)
  (retry/escalation economy) is Tier 1 by nature and gains a monetary axis it
  was not expected to have.

## Change log

| Date | Agent | Change |
|---|---|---|
| 2026-08-03 | planner | Measurement of Q1–Q4 recorded; self-logging concept evaluated (F1–F10) |
