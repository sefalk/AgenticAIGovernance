# Implementation Plan

**Workflow:** Feature Development  
**Branch:** `agent/554-ask-override-notice`  
**Status:** IN_PROGRESS  
**AF Version:** 2.0.0

## Context

Issue #554 requires an agent-facing notice when an AF PreToolUse gate returns
`ask` and the tool call nevertheless executes. The notice must not claim that
the IDE auto-approved the call: hook stdin does not expose the decision source.
It must name the gate and reason, state that either host policy or a human may
have approved, recommend aligning IDE and AF permissions, and remind the agent
to preserve traceability when applicable.

The approved design records a short-lived receipt from each AF `ask` emitter
and consumes it in the existing PostToolUse hook. Receipt failures do not alter
an existing gate verdict. SessionStart permission detection is out of scope.

## References

- [Issue #554](https://github.com/sefalk/AgenticAIGovernance/issues/554)
- [Owner decision](https://github.com/sefalk/AgenticAIGovernance/issues/554#issuecomment-6942558344)
- `flavors/github-copilot/.github/hooks/scripts/_guard_receipt.py`
- `flavors/github-copilot/.github/hooks/scripts/_field_guard.py`
- `flavors/github-copilot/.github/hooks/scripts/_body_guard.py`

## Scope Assessment

- **Files affected:** approximately 15 source, test, and documentation files.
- **Layers touched:** hooks/adapters and framework documentation.
- **Complexity tier:** Deep (new shared helper and multiple hook entry points).
- **Estimated size:** large (6 subtasks).
- **Not in scope:** changing gate policy, SessionStart detection, Claude flavor,
  live changes to the main checkout, and MP Usage XP.
- **Risks:**
  1. **PARTIALLY VERIFIED:** One `block-dangerous` PowerShell call correlated
     for each of the parent and a subagent. Other emitters and raw hook-command
     stdin shapes have not been independently measured live.
  2. **VERIFIED FOR PROBE:** PostToolUse context reached both the parent and a
     general-purpose subagent for the simulated PowerShell calls.
  3. **PARTIALLY VERIFIED:** Copilot delivered `additionalContext` in this
     probe; this does not separately establish which emitted JSON shape it used.
  4. A missed ask emitter would silently omit a notice; an inventory test must
     cover the full hook source tree.
  5. A notice also follows human-approved calls; wording must remain neutral.
- **Rollback plan:** revert the feature branch. Receipts are temporary files
  with a bounded lifetime; disabling the PostToolUse consumer silences notices.

## Subtasks

### 1. Inventory ask emitters and add regression tests

- **Action:** Add tests for source coverage, receipt correlation, notice wording,
  context merging, and both supported shell dialects.
- **Files:** `.github/scripts/test-ask-receipt.ps1`,
  `.github/scripts/suite-scope.json`.
- **Layer:** Adapter (test).
- **Acceptance criteria:**
  - Tests fail before implementation for missing receipt behavior.
  - Every source that can emit `ask` is listed and instrumented; unrelated
    deny/allow paths do not record a receipt.
  - Test fixtures cover snake_case and camelCase IDs without assuming that
    Copilot command stdin uses either shape.
- **Exit criterion:** Targeted tests fail for the expected missing behavior.
- **Tests needed:** the new regression suite.
- **Dependencies:** none.
- **Status:** DONE — inventory and focused regression tests added; Red-phase
  failure was recorded before implementation.

### 2. Implement the shared receipt helper

- **Action:** Add a stdlib helper for safe correlation, short-lived storage,
  recording, and one-time receipt consumption. Support an environment override
  only for isolated tests; use a temp-directory default in production.
- **Files:** `.github/hooks/scripts/_ask_receipt.py`.
- **Layer:** Adapter support utility.
- **Acceptance criteria:**
  - A receipt is keyed by both session and tool-call IDs; unsafe or missing IDs
    are not used to construct paths.
  - The notice includes the gate and original reason, states the call ran
    despite an AF `ask`, and does not assert an approval source.
  - The notice recommends `deny` or `declared-strict` when unattended, or
    restoring default IDE permissions to require a human; it mentions
    `System.History` or an issue comment for applicable traceability.
  - Duplicate, expired, corrupt, or unrelated receipts do not produce a false
    notice. Receipt failures never change a gate's verdict.
- **Exit criterion:** The helper passes the focused test cases on Windows.
- **Tests needed:** key isolation, ID aliases, expiry, one-time consumption,
  corrupt receipt, and write/consume failure behavior.
- **Dependencies:** 1.
- **Status:** DONE — focused receipt tests passed on Windows with both shell
  wrappers exercised.

### 3. Record receipts at all AF ask-producing hooks

- **Action:** Instrument the shared `block-dangerous` ask funnel, its
  foreign-guard passthrough, the work-item owner dispatcher, and the scoped
  coordinator/researcher ask paths. Keep `.ps1` and `.sh` behavior equivalent.
- **Files:** `block-dangerous.ps1/.sh`, `work-item-owner.py`,
  `coordinator-pretooluse.ps1/.sh`, `researcher-pretooluse.ps1/.sh`.
- **Layer:** Adapter.
- **Acceptance criteria:**
  - Only `ask` outcomes record receipts; existing stdout verdicts and exit
    codes remain unchanged.
  - Receipt failure leaves the existing verdict JSON valid and unchanged.
  - An inventory test fails if an ask emitter is added without receipt support.
- **Exit criterion:** Existing decision, field/body guard, foreign-guard, and
  dialect-parity tests pass.
- **Tests needed:** one exercised ask path per emitter family plus no-receipt
  allow/deny cases.
- **Dependencies:** 2.
- **Status:** IN_PROGRESS — emitters instrumented and targeted decision,
  foreign-guard, work-item-owner, and dialect suites passed. The broader
  `test-hooks.ps1` run remains unresolved and a direct isolation attempt was
  policy-denied.

### 4. Emit the correlated notice in PostToolUse

- **Action:** Consume receipts from `scan-secrets.py` and merge the notice with
  existing context without dropping other hook messages.
- **Files:** `.github/hooks/scripts/scan-secrets.py`.
- **Layer:** Adapter.
- **Acceptance criteria:**
  - A matching post-tool payload emits both top-level and nested
    `additionalContext`; unmatched payloads preserve prior output.
  - Multiple contexts compose with the existing long-line, subagent, secret,
    and provenance outputs.
  - Both supported command-payload dialects are tested; a live session must
    confirm the actual Copilot correlation and delivery before claiming it.
- **Exit criterion:** Offline tests pass and live-validation caveats are
  accurately recorded.
- **Tests needed:** matching/missing IDs, context composition, and write-tool
  and non-write-tool paths.
- **Dependencies:** 2 and 3.
- **Status:** DONE for the tested `block-dangerous` path — offline receipt and
  context-merging tests passed, and parent and subagent live delivery was
  observed. Other emitters remain covered offline, not live.

### 5. Document behavior and release note

- **Action:** Document the notice, neutral wording, fail-open receipt behavior,
  and live-validation caveat; add the issue changelog fragment.
- **Files:** `.github/hooks/README.md`,
  `changelog.d/554-ask-override-notice.md`.
- **Layer:** Documentation.
- **Acceptance criteria:**
  - Documentation matches implemented behavior and names no unsupported
    setting or unmeasured permission source.
  - Changelog headings satisfy the repository validator.
- **Exit criterion:** Documentation tests pass.
- **Tests needed:** changelog-heading and rule-drift suites.
- **Dependencies:** 4.
- **Status:** DONE — hook documentation and changelog updated; changelog-heading
  and rule-drift checks passed.

### 6. Verify in the disposable Copilot probe and report limits

- **Action:** When a safe AF probe session is available, deploy the feature
  there and verify receipt correlation and context delivery for parent and
  subagent calls. Do not interact with MP Usage XP.
- **Files:** no framework files; keep any probe-only artifacts in the disposable
  probe workspace.
- **Layer:** Verification.
- **Acceptance criteria:**
  - Record observed stdin key names and whether IDs correlate, without copying
    prompts or user paths.
  - Confirm whether `additionalContext` reaches the parent and subagent, or
    mark that delivery as unverified.
  - Do not claim a live pass without the actual session evidence.
- **Exit criterion:** Live results are recorded in the PR description, or the
  limitation is explicitly reported as BLOCKED.
- **Tests needed:** local Copilot hook integration procedure.
- **Dependencies:** 4.
- **Status:** DONE for one safe `block-dangerous` scenario in a separate
  Copilot session. A non-destructive `Remove-Item -WhatIf` call reached both
  parent and general-purpose subagent; the fixture remained present. Their
  PreToolUse and PostToolUse session-event call IDs matched, and both agents
  reported the notice. The parent permission was recorded as `human_response`;
  the subagent hook permission was recorded as `host_policy`, despite the
  recorded permission mode being `manual`. This does not establish why the host
  approved or prove other gates. The event envelopes are not raw command stdin.

  Evidence: local Copilot session `7e47212a-a4f4-4b7b-961f-15a752141600`,
  2026-11-19 07:33–07:36 UTC. The prior loopback fetch was blocked and was not
  retried. The output-channel integration script cannot be attested from these
  session events alone; it expects a VS Code hook output-channel log, and the
  newest discovered such logs predate the probe.

## Implementation Sequence

1. Emitter inventory and failing tests.
2. Shared receipt helper.
3. Instrument every ask emitter.
4. Merge notice into the existing PostToolUse output.
5. Update documentation and changelog.
6. Attempt live verification only in a safe AF probe session.

## Quality Gates

| Gate | Target | Type |
|---|---|---|
| Regression suites | All targeted hook suites pass | HARD |
| Shell parity | `.ps1` and `.sh` ask outcomes remain equivalent | HARD |
| Notice source claims | No unmeasured host/human decision-source assertion | HARD |
| Live context delivery | Parent and subagent behavior measured in the probe | SOFT |
| Architecture | Receipt persistence remains isolated in one helper | SOFT |

- **Suggested workflow:** Full TDD.
- **Skills consulted:** `tdd-orchestration`, `unit-testing`,
  `secure-coding`, `test-execution`.

## Plan Approval

**Approved by:** human (scope approved in chat on 2026-11-18)  
**Verdict:** APPROVED-WITH-FINDINGS

### Open Findings

- Live raw hook-command stdin shapes and correlation for other ask emitters
  remain unverified.
- The broad `test-hooks.ps1` regression is resolved (644 passed, 0 failed;
  `test-ask-receipt.ps1` 46/46). Root cause, confirmed from `$Error` behind the
  suite's rethrowing `trap`: ID-less legacy fixtures made the receipt helper
  write `AF ask receipt not recorded.` to stderr, which aborts
  `Invoke-HookScript` under `ErrorActionPreference=Stop`. Missing correlation
  ids are now a silent skip (CLI exit 3); storage failures still warn. Two
  follow-on failures were fixed: three new duplicate top-level names in
  `_ask_receipt.py` (renamed to `_receipt_key`, `record_ask`, `_cli`) and a
  credential-URL assertion that still expected the old `***` echo.
- Output-channel integration was attested on 2026-11-19 15:25 with a fresh
  Local-harness session in the probe workspace after deploying this branch
  (`test-hooks-integration.ps1`: 9 passed, 0 failed). The Copilot harness does
  not write that log; replacing the check is #553.
- Code review of the final delta found a backslash-authority allowlist bypass
  in the researcher fetch hook; fixed in both shells with a regression test.

## Change Log

| Date | Agent | Change |
|---|---|---|
| 2026-11-18 | planner | Initial implementation plan drafted and approved with findings |
| 2026-11-19 | coordinator | Record offline verification and isolated live-probe blocker |
| 2026-11-19 | coordinator | Record parent and subagent Copilot live-probe results and remaining gates |
| 2026-11-19 | coordinator | Narrow the regression failure from recorded output without rerunning the denied probe |
| 2026-11-19 | coordinator | Resolve the hook-suite regression: silent skip for missing ids, unique helper names, updated redaction assertion |
| 2026-11-19 | coordinator | Record integration attestation and the backslash-authority fix from review |
| 2026-11-20 | coordinator | Fix PR #561 CI: assemble the secret-scan fixture at run time, rename marker variables, add the suite budget |
