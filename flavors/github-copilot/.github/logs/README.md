# Workflow Logs

Structured YAML logs for agent workflows. One file per workflow.

## Schema

See the [documenter agent](../agents/documenter.agent.md) for the full YAML schema.

## Conventions

- **Filename:** `<workflow-id>.yaml`
- **Format:** YAML with 2-space indentation
- **Timestamps:** ISO 8601 with timezone (e.g., `2025-01-15T14:30:00Z`)
- **Retention:** 30 days locally, archive if long-term audit needed

## The `cost:` block (ADVISORY)

Appended automatically by the documenter Stop hook
(`hooks/scripts/documenter-stop.ps1`/`.sh`), which runs
[`scripts/collect-session-cost.py`](../scripts/collect-session-cost.py) against
the chat debug log of the current session:

```yaml
cost:
  schema_version: 1
  collector: "collect-session-cost.py@1"
  available: true
  coverage: full            # full | partial | truncated
  sessions: ["<session-id>"]
  requests: 205             # billed requests only
  unbilled_requests: 9
  tokens: { input_uncached: 1259777, cached: 21963581, output: 234002 }
  credits: 2385.082
  by_model:
    claude-opus-5: { requests: 188, credits: 2363.735 }
  environment: { vscode: "1.131.0", copilot_chat: "0.59.0" }
```

Reading it:

- **It is ADVISORY and always will be.** The source is
  `github.copilot.chat.agentDebugLog.fileLogging.enabled`, an experiment-flagged
  vendor setting Microsoft can switch off remotely. A missing block is normal and
  gates on it are forbidden.
- **`available: false` carries a `reason`** (`session_dir_missing`,
  `main_log_missing`, `log_unparseable`, `schema_drift`) and is never an error.
- **`coverage` qualifies the number.** `truncated` means the log lost its start
  (the 100 MB cap drops the *oldest* entries, i.e. the plan and Red phases) and
  no total is emitted at all — a total would look complete while being biased
  downward. `partial` means the session began after the workflow did, so earlier
  phases were never logged.
- **The block is a snapshot taken when the documenter finishes.** The
  coordinator's closing turns are not in it.
- **`requests` counts billed requests only**; requests without the billing
  attribute are counted separately as `unbilled_requests`, never as zero.
- **`input_uncached` excludes cached tokens** — the raw `inputTokens` field
  already includes them, so the two must never be added.
- **The numbers never pass through a language model.** The hook appends the
  script's output verbatim; no agent reads the debug log (a session log reaches
  tens of megabytes and contains every prompt verbatim).

Regression tests: `scripts/test-session-cost.ps1`.

## Never committed

The `.gitignore` in this directory keeps every log out of version control. It is
part of the deployed payload, so the rule arrives with the framework instead of
relying on someone adding it to the project's own `.gitignore` — and being
directory-scoped, it cannot clobber that file.

Two independent reasons, either sufficient on its own:

1. **Sensitivity.** `trigger:` holds the user request verbatim. Anything pasted
   into a prompt — a token, a customer name, an internal path — would be
   committed with it.
2. **Irrelevance.** These logs describe how the framework worked, not what the
   project does. They are neither source, nor documentation, nor audit evidence
   for the product.

A `.gitignore` does not untrack files that were committed before it existed.
If `git ls-files .github/logs` returns anything, removing it is a deliberate,
human-owned step — the framework will not do it for you.

## Generating Summaries

Use the workflow-summary prompt:

```
/af-workflow-summary <workflow-id>
```

Or ask the documenter agent directly.
