# Workflow Logs

Structured YAML logs for agent workflows. One file per workflow.

## Schema

See the [documenter agent](../agents/documenter.agent.md) for the full YAML schema.

## Conventions

- **Filename:** `<workflow-id>.yaml`
- **Format:** YAML with 2-space indentation
- **Timestamps:** ISO 8601 with timezone (e.g., `2025-01-15T14:30:00Z`)
- **Retention:** 30 days locally, archive if long-term audit needed
- **Coverage:** `AF_WORKFLOW_LOG_COVERAGE` (`af-env.conf`) decides which
  workflows write one. At the default `all`, every workflow does — Review Only
  and Plan Only get a log-only documenter pass — so the cost series below has
  no holes. A missing log then means a workflow that was never recorded, which
  is a defect, not a cheap run.

## The `cost:` block (ADVISORY)

Appended automatically by the documenter Stop hook
(`hooks/scripts/documenter-stop.ps1`/`.sh`), which runs
[`scripts/collect-session-cost.py`](../scripts/collect-session-cost.py) against
the chat debug log of the current session:

```yaml
cost:
  schema_version: 3
  collector: "collect-session-cost.py@3"
  available: true
  coverage: full            # full | partial | truncated
  sessions: ["<session-id>"]
  requests: 205             # billed requests only
  unbilled_requests: 9
  tokens: { input_uncached: 1259777, cached: 21963581, output: 234002 }
  credits: 2385.082
  rate_card: "models.json"  # null when the dump is absent or unusable
  credits_by_kind: { input_uncached: 852.1, cache_read: 602.7, output: 480.2, unexplained: 450.082 }
  by_model:
    claude-opus-5: { requests: 188, credits: 2363.735 }
  by_agent:                 # most expensive first; null when truncated
    main:
      totals: { invocations: 1, requests: 150, unbilled_requests: 9, input_uncached: 900000, cached: 18000000, output: 190000, credits: 2100.0 }
      by_model:
        claude-opus-5: { requests: 150, credits: 2100.0 }
    implementer:
      totals: { invocations: 3, requests: 55, unbilled_requests: 0, input_uncached: 359777, cached: 3963581, output: 44002, credits: 285.082 }
      by_model:
        claude-sonnet-5: { requests: 55, credits: 285.082 }
  facts: "<path>"           # null unless --facts-out was passed
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
- **`by_agent` says which log each request came from**, keyed by the agent name
  in the filename; `main` is the parent session, deliberately not called
  `coordinator` — the file records where a request was made, not who authored
  it. The buckets reconcile against the totals, and `invocations` counts the
  log files, so an agent that ran and billed nothing still appears. It is
  `null`, not `{}`, when coverage is `truncated`: the split inherits the same
  downward bias as the totals.
- **The nested `by_model` resolves both axes on a joint key.** "The coordinator
  is expensive" and "opus is expensive" are different findings, and only the
  crossing distinguishes them — an agent that is costly *because of its model*
  is a routing decision, an agent that is costly on a cheap model is a prompt
  problem. Tokens and credits carry independent signals here too: a bucket can
  read far more tokens than another and still cost a fraction of it.
- **`credits_by_kind` splits the bill the way it is charged.** A cached token
  costs a tenth of an uncached one and an output token ten times it, so the
  three token counts and the single credit scalar cannot be crossed after the
  fact. The split is computed from the `models.json` price dump the editor
  writes next to the log, named in `rate_card`; without it the kinds are not
  guessed — everything lands in `unexplained` and `rate_card` is `null`.
- **`unexplained` is a named field, never a rounding.** Cache-*write* tokens are
  billed and never reported, so on models that charge for them the known kinds
  do not reach the invoice — measured at roughly 19% of a real session. That
  gap is stated rather than distributed across the kinds that *are* known,
  because a plausible total is worse than an honest one. The four kinds always
  sum to `credits`.
- **`facts` names the per-request artifact** (`--facts-out`, NDJSON, one row per
  request). The debug log is capped and expires; a row that was never extracted
  while it existed answers no question ever again. The aggregates above are
  computed *from* those rows, so the block cannot disagree with them. The rows
  carry dimensions the block does not render — request purpose (agent work,
  compaction, background), the parent span, the prompt and tool payload files,
  reasoning effort — and contain numbers and identifiers only: no prompt text
  is ever extracted, which is what makes the file keepable at all. The rows are
  still written under `coverage: truncated`, where the aggregates are withheld:
  each row is individually accurate, only the *set* is incomplete, and the
  header row records the coverage so nobody re-aggregates them as a total.
- **The numbers never pass through a language model.** The hook appends the
  script's output verbatim; no agent reads the debug log (a session log reaches
  tens of megabytes and contains every prompt verbatim).

Regression tests: `scripts/test-session-cost.ps1`.

## The `agent_invocations:` block

Also appended by `documenter-stop`, from the filenames the editor writes for
each subagent call (`runSubagent-{agent}-{id}.jsonl`):

```yaml
agent_invocations:
  observed:
    implementer: 2
    test-writer: 1
  claimed_without_invocation:
    - arbiter
```

Reading it:

- **`observed` is a lower bound.** It counts one chat session. A workflow
  resumed in a later window records only the session that finalised it.
- **`claimed_without_invocation` lists agents named in `steps[]` with no
  invocation log.** For a workflow that ran in a single session, that list is
  the set of steps that did not happen. A log once carried a complete
  `agent: arbiter` step — action, verdict, review findings — for an arbiter
  nobody called (issue #173).
- **Nothing gates on it, deliberately.** A multi-session workflow would fail a
  block it did not deserve, and a hook that fails honest work gets switched off.
  The contradiction is written down instead, where a reader meets it without
  having to reconstruct anything.
- **The names never pass through a language model.** They come from a
  directory listing.

Regression tests: `scripts/test-agent-invocations.ps1`.

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
