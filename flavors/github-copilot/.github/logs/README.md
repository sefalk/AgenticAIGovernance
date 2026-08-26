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
  schema_version: 4
  collector: "collect-session-cost.py@4"
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
  by_purpose:              # what the request was for, not who made it
    agent_work: { requests: 199, unbilled: 0, credits: 2290.082 }
    compaction: { requests: 6, unbilled: 0, credits: 95.0 }
    background: { requests: 0, unbilled: 9, credits: 0.0 }
  by_agent:                 # most expensive first; null when truncated
    main:
      totals: { invocations: 1, requests: 150, unbilled_requests: 9, input_uncached: 900000, cached: 18000000, output: 190000, credits: 2100.0 }
      by_model:
        claude-opus-5: { requests: 150, credits: 2100.0 }
      by_purpose:
        agent_work: { requests: 144, unbilled: 0, credits: 2005.0 }
        compaction: { requests: 6, unbilled: 0, credits: 95.0 }
        background: { requests: 0, unbilled: 9, credits: 0.0 }
    implementer:
      totals: { invocations: 3, requests: 55, unbilled_requests: 0, input_uncached: 359777, cached: 3963581, output: 44002, credits: 285.082 }
      by_model:
        claude-sonnet-5: { requests: 55, credits: 285.082 }
      by_purpose:
        agent_work: { requests: 55, unbilled: 0, credits: 285.082 }
  by_entity:                # what the payload carried, not what it cost
    available: true
    credits_attributable: false
    payloads: { system_prompt: 57, tools: 4, unreadable: 0 }
    classes:
      tool: { entities: 197, tokens_est_per_request: 61651 }
      instruction_attached: { entities: 4, tokens_est_per_request: 5062 }
      skill: { entities: 30, tokens_est_per_request: 3631 }
    tools_by_group:
      mcp:azure: { entities: 40, tokens_est_per_request: 17614, invoked: 3 }
      mcp:pylance: { entities: 19, tokens_est_per_request: 9926, invoked: 0 }
    customizations:
      testing.instructions.md: { applying: 0, skipped: 61, listed: 0, reason: "applyTo '**/test_*.py' did not match any attached files" }
      git-workflow.instructions.md: { applying: 61, skipped: 0, listed: 0 }
    rows: "<path>"          # null unless --entities-out was passed
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
- **`by_purpose` says what a request was *for*, which is not the same question
  as who made it.** Compaction (`summarizeConversationHistory`) is the price of
  the session having grown too long, not of the agent whose turn happened to
  trigger it — measured at 292 of 6764 credits, 4.3%, on one real session, all
  of it inside the `main` bucket where it read as coordinator spend. The lever
  that reduces it is splitting the session or trimming context, not rewriting
  that agent's prompt. The split is rendered inside every agent bucket as well,
  including the buckets where it is uniform: an absent split must not mean both
  "uniform" and "not computed". `background` is always unbilled and is listed
  anyway, with its request count under `unbilled` — "it happened and cost
  nothing" is a different statement from "it did not happen". An unrecognised
  `debugName` lands in `other` and is never sorted into a known bucket; the
  block names only the bucket, and the raw `debugName` stays in the facts rows
  where it can be looked at without widening the block for every vendor string.
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
- **`by_entity` answers a different question from every block above it: not who
  spent the credits, but which *definitions* were in the payload they paid
  for.** The other blocks can only ever say "the coordinator on opus is
  expensive"; none of them can say *why* its prompt is large. This one names
  the tools, skills, agents and instruction files that were actually delivered,
  measured from the dumps the editor wrote next to the log — not from the
  source files on disk, which is the difference between what shipped and what
  exists.
- **`credits_attributable: false` is rendered in the block, not only here.** An
  entity's tokens are inside a request's `inputTokens`, and a request-level
  billing record cannot be split by which span of the prompt produced it. A
  per-entity credit figure could only be invented by dividing, so none is
  emitted at any grain — not in the block, not in the rows. What is honest is
  the footprint, how many requests carried it, and how often it was used.
- **`tokens_est_per_request` is an estimate and says so in its name.** It is
  characters over four, the usual English rule of thumb; the vendor's tokenizer
  is not ours to run. It is a *request-weighted mean*, because the payload
  changes during a session — picking one payload would be a choice, averaging
  over the requests that carried each one is a measure.
- **`invoked` appears only where it is complete.** Tool calls are logged, so
  tool groups carry a count and a group with `invoked: 0` is the finding the
  block exists for: definitions shipped on every request and called on none. A
  skill or an agent description is *read* by the model, not called — a zero
  next to its token count would read as "never used" when it means "not
  measurable", so none is emitted.
- **`tools_by_group` can merge two MCP servers, never split one.** VS Code
  prefixes MCP tools `mcp_{server}_{tool}` and server names contain underscores
  themselves, so the boundary is not recoverable from the name; grouping on the
  first token is deliberate. The direction of the error matters: the question
  is whether a whole server earns its place in the payload, and a merge keeps
  that answerable while a split would not.
- **`customizations` reports instruction and chat-mode resolutions, never-applied
  first, with the skip reason.** The reason is the actionable half — it says
  whether the fix is to narrow the `applyTo` pattern or to remove the file.
  Measured on one real session: four of seven instruction files were skipped on
  all 61 resolutions, every one of them for `applyTo` patterns that matched no
  attached file. Note the denominator: only resolutions are counted, not
  requests, so `61` is not a share of that session's 808 requests.
- **The payload *kind* comes from which attribute named the file**
  (`systemPromptFile` vs `toolsFile`), never from the filename. `payloads`
  counts how many of each were read and how many could not be; an unreadable
  dump is counted there rather than dropping the block, so a session with one
  bad payload still attributes the rest.
- **It degrades like everything else.** `available: false` with
  `payload_not_named` (no request named a dump) or `payload_dumps_unreadable`
  (named but gone or unparseable — dumps expire with the log); `by_entity: null`
  under `coverage: truncated`, where each row is still accurate but the request
  set behind the weighting is not.
- **`rows` names the entity artifact** (`--entities-out`, NDJSON) and it is a
  **different grain from the facts file: one row is one definition inside one
  delivered payload, not one request.** The two must never be joined and summed.
  `requests` on a row is a *multiplier*, not something the row did: adding it up
  counts each request once per definition it carried — on a real session, 158300
  against 808 requests actually made. The fan-out is left visible as a column
  rather than materialised as duplicate rows, the header states the grain
  and `credits_attributable: false`, and there is no credit column to sum.
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
