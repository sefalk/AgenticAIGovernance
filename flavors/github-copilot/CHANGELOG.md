# Changelog

All notable changes to the Agent Framework are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **The shipped bash hook suite is now executed (#190, #183).**
  `run-all-tests.ps1` sweeps `test-*.ps1`, so `test-hooks.sh` — the only
  executing coverage the `.sh` hooks have — was committed, maintained, and run
  by nothing. Reading was doing the work that running was believed to do,
  which is #61 in the other half of the payload.

  A CI step runs it on the Windows runner through the bash that Git for
  Windows installs at `C:\Program Files\Git\bin\bash.exe`. The suite exits 0
  when it finds no usable Python interpreter, so the step also fails on a
  `SKIP:` line and on a missing pass count — a suite that skipped itself must
  not report green.

  First measured run: **187 assertions, 0 failures.** Five are new. The cases
  the #183 fix was written against existed only in the PowerShell harness, so
  the `.sh` copy of that fix had been reviewed and never measured; it holds.

  `hooks/README.md` now says where that interpreter is and how to invoke the
  suite by hand, because "not on `PATH`" had been indistinguishable from "not
  installed" for as long as nobody ran it.

- **A switched-off cost source now announces itself (#228).** Cost collection
  depends on a VS Code setting that is off by default. When it is off the
  collector correctly writes `cost: available: false` into a workflow log —
  a file nobody opens unless they already suspect something is wrong. A
  consumer could therefore run for months with an empty cost series and no way
  to discover why short of reading framework source.

  `scripts/check-cost-source.ps1` (and its `.sh` twin) probes the effect rather
  than the configuration: it counts session logs on disk. Reading the setting
  is unreliable — it may live in user, workspace, or profile settings, and
  those files are JSONC, which no JSON parser accepts. A session log that
  exists is proof the source is live.

  The advisory is emitted by the deploy summary, which is the only channel that
  reaches **existing** installs: the `.vscode/settings.json` that would carry
  the key is PRESERVE'd on update, so shipping the key upstream would reach new
  consumers only. It names the setting, what is lost while it is off, and the
  caveat that the setting is experiment-flagged and the vendor may withdraw it.

  Nothing gates on it. The probe always exits 0, and a dark source fails no
  workflow, hook, or suite. This generalises the #224 principle — a check that
  does not run must announce itself — to the data source behind it.

### Fixed

- **One stale word no longer switches off four measurements (#252).** The
  documenter's stop hook decided whether a workflow had ended by reading
  `**Status:**` out of the plan file. Anything other than `COMPLETED` was read
  as a mid-workflow call and the hook exited at its first gate — before the log
  schema check, the timestamp check, the cost block and the invocation census.
  The plan status is a word an agent maintains by hand, so forgetting to write
  it disabled every measurement behind it silently, and the run reported green.
  Observed twice, both times on workflows that had finished and merged while
  their log said `COMPLETED` all along.

  The hook now finalises when *either* the plan says `COMPLETED` or the
  workflow log reports a terminal status, and it names the disagreement in its
  output instead of resolving it in silence. The log match is deliberately
  looser than the schema's closed set: an invalid value such as
  `COMPLETED-WITH-ISSUES` must reach the schema checker that reports it, not
  exit the gate and take the measurements with it. A log that claims no end
  still leaves a genuine mid-workflow call alone. Both hook twins changed;
  four assertions were added to each suite.

- **The bash hook suite no longer runs its fixtures in the real repository
  (#248).** Five fixture helpers guarded their working directory with
  `cd "$fixture" || exit 1`. That stops a *wrong* path and not an *empty* one:
  `cd ""` succeeds in bash and stays where it was. With the current directory
  still at the repository root, the fixture's `git init` and
  `git checkout -b agent/72-x` ran against the checkout itself — measured, not
  theorised: a suite run created `agent/72-x` in a maintainer's repository and
  two later commits landed on it.

  Fixture creation now fails loudly instead of continuing with nothing, and the
  guards use `${fixture:?}`, which refuses an empty value. Why `mktemp -d`
  returned nothing is not established; the fix does not depend on knowing,
  because a harness must not be able to write into the repository it is
  testing whatever the reason.

- **A request that consumed nothing no longer voids the session's cost (#238).**
  The collector required four attributes on every `llm_request` and read a
  missing one as a changed log schema. A failed compaction reports none of the
  three token counts and no billing attribute — it consumed nothing, so there
  is nothing to account for — and reading that absence as drift returned
  `available: false, reason: schema_drift` for the whole session.

  Measured across 25 session directories: 10,734 requests, 51 of them shaped
  that way, every one an aborted compaction. They are not spread evenly. 39 of
  the 51 sit in a single 231 MB session, 4 in another, 8 in a third, and the
  remaining 22 sessions have none — compaction only happens once a session has
  grown long, so the cost data died in exactly the sessions worth measuring. A
  consumer project's workflow logs had been emitting an empty cost block on
  that account, and the session that previously reported `schema_drift` now
  reports 306 requests and 2327 credits.

  The test is "reported no usage", not "said it failed". Of the 51 records, 50
  carried `status: error` and one carried `status: ok`; a status-based check
  would have let that one through and voided its session anyway. These requests
  are counted as `no_usage_requests`, held apart from `unbilled_requests`,
  which counts requests that did spend tokens without being charged — folding
  the two together would file a failure inside a normal category.

  Genuine drift is now subtracted instead of fatal. A *billed* request missing
  its token fields is still drift, but it costs that one record: the rest are
  still priced, and `drift: { records, of, fields }` names the field, the loss
  and the base, so a reader can judge whether the total is still worth reading.
  `schema_drift` survives and now means what it says — every request was
  unreadable.

- **The documented cost block had fallen two versions behind (#227, partly).**
  The example in `logs/README.md` announced `schema_version: 4` against a
  collector emitting 5. A hand-kept example is documentation only for as long
  as something compares it to the code, so the suite now does: the version and
  the collector tag in the README are checked against `SCHEMA_VERSION`, and the
  check was confirmed to fail against the stale text before it was refreshed.
  #227's wider ask — that the block's *content* and its documentation cannot
  diverge — is untouched.

### Changed

- **The retro template no longer offers a status the schema rejects (#252).**
  `documenter.agent.md` told the documenter that a workflow log's `status:` is
  one of `COMPLETED`, `FAILED`, `ESCALATED`, and eleven lines later offered
  `COMPLETED-WITH-ISSUES` as a retro outcome. Two vocabularies for one fact
  invite the invalid value into the log. The template now uses the same closed
  set, and says where a run's problems belong: in the sections below the
  outcome, not in the word.

- **The cost block is at `schema_version: 6`.** It gains `no_usage_requests` on
  every block, and `drift` on the blocks that lost a record.

## [1.23.0] -- 2026-08-26

### Added

- **The catalogue payload now has a ceiling (#206).** Every skill, agent and
  instruction file announces itself by name and description on every chat
  request — the discovery level of the editor's three-level loading — and until
  now that payload was gated by nothing. It is the same accretion problem the
  always-on ceiling exists to stop, with none of the friction: adding a skill
  *feels* free precisely because its body is not sent, and the description that
  is sent never appeared on any ledger. `AF_CATALOGUE_BUDGET_TOKENS` and
  `AF_PROJECT_CATALOGUE_BUDGET_TOKENS` close that gap, split by ownership like
  the three ceilings before them, and the breakdown names the kind and the five
  widest entries so a breach says what to shorten.

  The framework's share measures 3322 tokens — 29 skills at 1906, 17 agents at
  1040, 7 instruction entries at 376 — and the ceiling is set at 3400. That is
  roughly the size of the entire always-on set, paid on every request, and it
  was not on any budget. Note an always-on instruction file is charged twice:
  once for its catalogue entry, once for the full attachment.

  Two facts were checked rather than assumed. The absolute `<file>` path the
  editor emits with each entry is deliberately **not** counted, because a gate
  whose number moves when someone clones to a different directory is measuring
  the directory; the omission errs low, and the delivered payload measured in
  #214 says by how much — agent entries carry no path and the model lands
  within one entry of the real block, instruction entries do carry one and the
  229-token gap is exactly seven Windows paths. And a description written as a
  YAML block scalar is followed rather than truncated, which a first-line read
  would have scored as two characters — an undercount that grows with precisely
  the descriptions worth catching.

  Skills in a `_`-prefixed directory are dormant and cost nothing here. That is
  the intended behaviour and also the defect #222 tracks: invisible is cheap,
  and indistinguishable from absent.

  The pre-commit guard needed a fix to make any of this bind at commit time. It
  exported `copilot-instructions.md`, `instructions/` and `agents/` and never
  `skills/`, so the first commit carrying the new ceiling reported 1416 tokens
  where the checker reported 3322 — agents plus instruction entries, with the
  largest kind missing entirely. It now exports `skills/*/SKILL.md`, and only
  that: the reference material beside a skill loads on demand and costs the
  budget nothing.

- **Cost can now be traced to the definitions that cause it, not only to the
  agents that spend it (#214).** Every block so far answered *who spent*. None
  could answer *why a prompt is that large*, because none of them knew what was
  in it. `by_entity:` names the tools, skills, agents and instruction files
  actually delivered in each request, measured from the payload dumps the editor
  writes next to the log — not from the source files on disk, which is the
  difference between what shipped and what exists.

  The first measurement of one real session says the budget discussion has been
  aimed at the wrong target. The tool catalogue is 197 definitions and roughly
  61651 estimated tokens on *every request that carried it*; the entire skill
  catalogue is 3631, agents 1129, instruction entries 651. Two MCP servers —
  pylance at 9926 and playwright at 3823 — shipped on all 633 requests that
  named a tools payload and were called zero times. Disabling one unused server
  is worth several times what trimming every skill description in the
  repository would save.

  The second finding is cheaper still to act on. Four of the seven instruction
  files were skipped on all 61 customization resolutions, every one for an
  `applyTo` pattern that matched no attached file — while four *attached*
  instruction files were pasted in full on each of the 589 requests that named
  a system prompt, at 5062 estimated tokens, nearly eight times what their
  catalogue entries cost.

  What the block deliberately does not do is put a price on any of it.
  `credits_attributable: false` is rendered in the block itself, not only in
  the docs: an entity's tokens live inside a request's `inputTokens`, and a
  request-level billing record cannot be split by which span of the prompt
  produced it. A per-entity credit figure could only be invented by dividing.
  `invoked` follows the same rule and appears only for tool groups, where calls
  are logged — a zero next to a skill's token count would read as "never used"
  when it means "not measurable".

  `--entities-out` writes the rows as NDJSON at grain **payload × entity**, its
  own schema version and its own header, deliberately not the facts file's
  grain. `requests` on a row is a multiplier, not something the row did:
  summing it counts each request once per definition it carried — 158300
  against 808 requests actually made. The fan trap is left visible as a
  column instead of being materialised as duplicate rows, and a regression check
  asserts the file is not summable to a credit total rather than only saying so
  in prose. `schema_version` 5; 97 regression checks, each new one shown able to
  fail under a targeted mutation of the collector.

- **Compaction is no longer billed to the agent that did not cause it (#215).**
  The block split by model and by agent. Both answer *who spent*; neither
  answered *what the request was for*, and one category of request is not the
  agent's work at all. `by_purpose:` now distinguishes `agent_work`,
  `compaction` (`summarizeConversationHistory`), `background` and `other`,
  derived from `llm_request.debugName`, at session level and inside every agent
  bucket.

  Measured on session `1d4b973a`: 292.1 of 6764.4 credits — 4.3% — was context
  compaction, and all of it sat in the `main` bucket reading as coordinator
  spend. It is not. It is the price of the session having grown too long, and
  the lever that reduces it (split the session, trim context) has nothing to do
  with the lever that reduces an agent's prompt cost. Six compaction rounds at
  roughly 49 credits each is a retrospective finding, not a rounding error.

  The split is rendered in every bucket, including the uniform ones, so an
  absent split cannot mean both "uniform" and "not computed". `background` is
  always unbilled and is listed anyway with its count under `unbilled`: "it
  happened and cost nothing" is a different statement from "it did not happen",
  and a credit-weighted view is exactly where the difference disappears. An
  unrecognised `debugName` lands in `other` rather than being guessed into a
  known bucket; the block names only the bucket, while the raw `debugName` stays
  in the facts rows, so a new vendor string is visible without the block growing
  a category per release. `schema_version` moves to 4.

- **The collector no longer aggregates against an expiring source (#217).** The
  debug log is capped at 100 MB and the cap drops the *oldest* entries; it also
  contains every prompt verbatim, so it can never be committed. Everything not
  extracted while it exists is unanswerable afterwards, and the block extracted
  four numbers. `--facts-out` now writes one NDJSON row per request — numbers
  and identifiers only, never `inputMessages` or `userRequest`, which is what
  makes the file keepable at all. The aggregates are computed *from* those rows,
  so the block cannot disagree with the artifact it summarises, and the rows
  already carry dimensions the block does not render: request purpose (agent
  work, compaction, background), the parent span, prompt and tool payload files,
  reasoning effort, latency. `schema_version` moves to 3.

  `credits_by_kind` splits the bill the way it is charged. A cached token costs
  a tenth of an uncached one and an output token ten times it, so three token
  counts and one credit scalar could not be crossed. The prices come from the
  `models.json` dump the editor writes beside the log, named in `rate_card`;
  the identity `nano_aiu = 1e9 * (1 - auto_discount) / batch_size * (uncached *
  input + cached * cache_read + output * output)` was verified to hold exactly
  on every request of the one model whose `cache_write_price` is zero.

  On every other model it does not close, and the gap is stated rather than
  smoothed away: cache-*write* tokens are billed and never reported, leaving
  `unexplained` at 1274.9 of 6764.4 credits — 18.8% — on a real session. The
  residual is not divided among the kinds that are known, and it is not
  dropped; the four kinds always sum to `credits`. Dividing it by the published
  cache-write price yields fractional token counts spread evenly across every
  bucket, so the count is not recoverable and pretending otherwise would be
  invention. Without a usable rate card nothing is guessed: `rate_card` is
  `null` and the whole amount lands in `unexplained`, never a silent zero.

- **Cost is now attributed per subagent, not only per model (#212).** The
  `cost:` block answered what a workflow cost but not what in it was expensive,
  and a workflow is split into subagents precisely so work can be moved between
  them. The data was already being read and discarded: `collect-session-cost.py`
  has always summed `main.jsonl` together with every `runSubagent-*.jsonl`, and
  the filename carries the agent name. The new `by_agent:` block keeps that
  bucket key instead of throwing it away.

  Measured on one real session, the split says something the total cannot: the
  implementer read more input tokens than the entire parent session (34.5M vs
  22.6M) while costing under a third as many credits, because it runs on a
  cheaper model. Token pressure and credit cost point at different agents, and
  a `by_model` split attributes neither to anyone who could act on it.

  The buckets reconcile against the totals — no field is dropped in the split —
  and `invocations` counts log files, so an agent that ran and billed nothing
  still appears. Under `coverage: truncated` the block is `null` rather than
  `{}`: the split inherits the downward bias of the size cap, and an empty map
  would read as "no agent consumed anything". `main` is deliberately not named
  `coordinator`; the file records where a request was made, not who wrote it.
  `schema_version` moves to 2.

  Each bucket also carries its own `by_model:`, so agent and model resolve on a
  joint key rather than as two separate lists that cannot be crossed. The
  crossing is what makes the number actionable: on the same session `main`
  accounts for 33% of requests and 75% of credits purely because it is the only
  bucket running on opus — a routing decision. An agent that were expensive on
  a *cheap* model would be a prompt problem instead, and the two look identical
  until the axes are joined.

- **A workflow that leaves no log reads as a cheap workflow (#210).** The YAML
  log in `.github/logs/` is the only per-run record of what a workflow cost and
  which definitions it loaded. It was never written for every run: Review Only
  and Plan Only invoke no documenter at all, and in the Trivial tier the log
  gate was `Standard+`, so nothing enforced it. That is tolerable for audit —
  those runs change little — and corrosive for measurement, because the gaps
  are not random. They fall exactly on the cheapest and the most-repeated
  workflows, so every average computed over the series is biased downward by an
  unknown amount, and a skill used only in unlogged runs looks unused.

  `AF_WORKFLOW_LOG_COVERAGE` (`af-env.conf`) now decides, defaulting to `all`:

  - Review Only and Plan Only get a **log-only** documenter pass — the YAML log
    and nothing else. No plan status, no provenance scan, no retro.
  - The log becomes a HARD gate at **every** tier, not from Standard upward.
  - `standard+` restores the previous behaviour byte for byte.

  The documenter is told what a log-only run must *not* contain: it has no
  phases, no verdicts and no changed files, so those keys are omitted rather
  than filled with an empty list or a `SKIPPED` verdict. A reader cannot tell an
  invented zero from a measured one, and the series exists to be read later.

  The two workflows this covers write no plan file, so `documenter-stop` used
  to classify their call as unclassifiable and say nothing further. It now
  names the missing log in that branch — advisory, never blocking, because the
  same branch carries legitimate mid-workflow documenter calls that have no log
  yet.

  Costs 76 tokens of coordinator budget (9,128 → 9,204 of 9,450). Refs #210.

- **A measurement an agent cannot show you is not a result (#134).** The
  framework already required agents to report evidence. It never said where the
  evidence had to live. That gap is invisible while the deliverable is a file —
  git holds it, anyone can open it — and opens the moment the deliverable is a
  *value*: a benchmark, a validation, a profile, a row count. The code that
  produced it is committed; the number is not. It exists only in the return text
  of the agent that produced it, which is exactly the artifact a reviewer has no
  independent way to check.

  Four layers were added, each at the level where it belongs:

  - **MANIFEST § 7 (Traceability)** gains `### Measured Results`: a result only
    the producing agent can observe is not evidence. Cite a location a third
    party can open without re-running anything — not the number alone.
  - **`quality-gates.instructions.md`** gains an *evidence durability* clause in
    the gate taxonomy. When no durable channel exists the gate is **BLOCKED**,
    which the existing taxonomy already defines as an escalation trigger. It is
    not passed with the number in the return.
  - **`databricks-execution-patterns`** gains a channel-selection matrix. Its
    run-type framework listed `jobs/runs/submit` and defined jobs but never
    mentioned the Command Execution API (`/api/1.2/commands/*`) — and a decision
    framework that omits an available option does not forbid it, it just fails
    to see it. The ephemeral channel is now named, permitted for probing, and
    barred from anything that will be quoted. Retention is stated as a **time
    horizon**, not a yes/no, with a persistence policy by investigation size.
  - **`copilot-authoring`** gains the convention this generalises to: platform
    skills carry the runbook, projects carry a configuration overlay, never a
    forked runbook.

  **The 60-day retention figure is quoted from the issue, not independently
  measured.** The skill says so and tells the reader to verify the current
  figure for their own workspace.

  **What this does not do: it is not mechanically enforced, and cannot be.** A
  Stop hook does not receive the agent's return text, so no hook can check that
  a cited number has a run id behind it — the same structural limit recorded
  against #175. *(Corrected under #123: the conclusion holds, but "structural
  limit" is the wrong label. The tool-call record **is** reachable from a Stop
  hook; what no hook can do is bind a number in prose to a run id.)* The twelve
  regression cases assert that the *guidance exists and
  says what it says*; they are documentation invariants, not behavioural ones.
  Calling them enforcement would repeat the failure this issue is about.

  Paying for the words was part of the change. Adding the durability clause put
  the always-on budget at 3,522 / 3,500 — 22 tokens over, a hard fail. The
  budget was not raised. The provider-worker naming examples were duplicated
  between `quality-gates.instructions.md` (always-on, paid on every request) and
  MANIFEST § 7 (not counted); the always-on copy now points at the MANIFEST one.
  Result: **3,476 / 3,500, passing**. Four regression cases assert each example
  survived the move, so a deduplication that silently became a deletion fails
  the suite.

  Suite went 312 → **324 passed, 0 failed**. The first run of the new cases
  reported 323/1, and the failure was mine, not the content's: the assertion
  matched the literal `BLOCKED, not passed` while the skill writes it with
  markdown emphasis and a line break between. The assertion was corrected, not
  the prose.

  A test that passes against the text that was written alongside it proves
  nothing on its own, so each case was checked against a mutation that deletes
  the rule it guards. Nine mutations, nine reds, each with exactly one failure
  and no collateral: the principle sentence, the durability clause, the named
  ephemeral endpoint, the citation bar, the time-horizon framing, the
  no-fallback escalation rule, the forked-runbook warning, the
  enumerate-what-is-disallowed rule, and one provider-worker example removed
  from the MANIFEST. The three remaining cases are further iterations of that
  same survival loop and were not mutated separately.

- **Working state now lives on the tracker, not in an agent's context (#186).**
  Every issue in this repository read exactly as it did on the day it was filed.
  What had been delivered, what was blocked, and what had been decided lived in
  a context window; when the context ended, so did the knowledge. #167 was fully
  delivered and its issue said nothing about it. The reasoning for keeping #170
  open survived only because a human asked for it to be written down.

  The new `work-item-state` skill is provider-agnostic and binds both
  `gh-issue-manager` and `ado-work-item-manager`. It puts the *current* state in
  a block under its own `## Working state` heading at the end of the issue body,
  and the *reasoning* in dated, append-only comments — because those two
  artifacts have different properties and neither substitutes for the other.

  Which artifact holds what was decided by measurement, not taste. On this MCP
  server `issue_read` `method: get` returns the body — so current state has to
  live there, because that is what a default read shows. Comments need a second
  call, and whether to make it is decided by the `comments` count that both
  `get` and `list_issues` return.

  That count took two measurements to establish, and the first was misleading:
  the field is **omitted entirely when it is zero**, so an issue read before any
  comment existed looks like a surface with no count at all. Reading #186 again
  after a comment was posted showed `comments: 1` on both calls. The rule is
  therefore: non-zero means the fetch is mandatory; an absent field means the
  agent inferred a zero and must say so in its return, because absence is not
  self-describing and the inference should fail loudly if the serialisation ever
  changes. Both the wrong first conclusion and the correction are recorded on
  #186 rather than quietly overwritten.

  The body block is deliberately capped at six lines and carries an index of
  the decision comments. It makes the second call targeted; it never makes it
  optional. Two new HARD gates make both halves checkable, and the trigger stays
  narrow: an issue whose state actually changed, not a status banner on
  everything.

  Two further behaviours were found by applying the convention to #186 itself
  and checking what landed. `<!-- af:working-state:START -->` markers, which the
  first draft used as the splice anchor, **do not survive the round trip** — the
  block came back without them. And a stored `agent's` reads back as
  `agent&#39;s`, so a body written back verbatim stores the literal entity for
  every human to see. The anchor is therefore a visible `## Working state`
  heading, entities are decoded before writing, and the procedure ends with a
  re-read rather than an assumption.

  The Azure DevOps half of § 6 is marked unmeasured. Whether an ADO description
  field renders Markdown, and whether its default read returns comments, has not
  been probed here, and the GitHub answer is not assumed to transfer.

- **The formatting rule the framework enforces on consumers now applies to the
  framework (#167).** #124 made `ruff format --check` a hard gate for consumer
  projects. The framework itself had no repository-level ruff configuration at
  all, so everything outside `mcp-deploy` was measured against ruff's defaults
  — a width nobody had chosen — and 19 of its 36 tracked Python files did not
  meet it.

  Three separate commits, because a reformat mixed into anything else is
  unreviewable:

  1. A root `ruff.toml`. `line-length = 120` is not a preference: it is the
     only ruff decision already made in this repository (`mcp-deploy`'s
     `pyproject.toml`) and it reformats the fewest files — 19, against 30 at
     ruff's default 88. `line-ending = "lf"` is explicit because "auto" writes
     CRLF on Windows into files git stores as LF, which git normalises away
     locally and leaves for a consumer's working tree to discover.
  2. The reformat alone: 19 files, +317/−324, listed in
     `.git-blame-ignore-revs` so `git blame` and GitHub's blame view skip it.
  3. The gate, plus a `ruff==0.16.2` pin. An unpinned formatter turns a
     routine ruff release into a red build on a pull request that changed no
     Python at all.

  The gate takes its file list from `git ls-files` rather than a glob, so a new
  file is covered the moment it is tracked, and an empty list fails loudly
  instead of passing silently.

  Not included, and measured rather than assumed: under the rule selection this
  config declares, `ruff check` reports 28 findings (15 auto-fixable). Those are
  lint, not formatting, and are left visible and ungated rather than quietly
  fixed inside a formatting change.

- **The framework now arms one of its own safety guards, without deploying to
  itself (#61).** The framework ships hooks that hard-deny `git push --force`,
  `git reset --hard` and `git add -A`, and has been developed without them.
  Deploying the payload into its own repository was the obvious fix and a bad
  one: it creates a second copy of every script that can drift from the first,
  and it makes `deploy.ps1` predict `CONFLICT` and `PROTECT` against the
  framework's own working files (#105, #106).

  A root `.github/hooks/agent-hooks.json` whose `command` entries point *into*
  `flavors/` avoids both. Nothing is copied, nothing is deployed, and only
  `block-dangerous` is armed — no agents, instructions or skills, so the
  untested question of how two payloads would take precedence never arises.

  What is measured is that the scripts work that way: driven from the
  repository root with a synthetic `PreToolUse` payload, `block-dangerous.ps1`
  allowed `git status` and denied force push, hard reset and `git add -A`. It
  resolves its helpers relative to its own location, not the current
  directory.

  And it loads. In a reloaded window, 13 runs of the `flavors/` command were
  recorded with `cwd` set to this repository — so VS Code reads a root hooks
  file from a folder that is not a deployed payload, and resolves the relative
  `command` path against the folder that declares it. Every `PreToolUse` ran
  exactly two hooks, one from each workspace folder, with no duplication and
  neither suppressing the other; `PostToolUse` ran one, because this file
  declares none. Cost is about 1.9 s per tool call, which is PowerShell
  startup rather than analysis.

  Still untested: that the guard *denies* in this arrangement. Every observed
  run returned allow, because no dangerous command was issued. #61 stays open.

- **A pull request that changes this repository's own environment must now say
  so (#164).** `.vscode/`, `.githooks/` and the root `.github/` decide which
  guards run and what CI enforces, and they are the paths where an unintended
  change is least likely to be read, because reviewers read the payload diff.
  Nothing signalled a change to them.

  The prompt was a near-miss during the work on #124: a delegated subagent
  returned an empty result and had nevertheless modified seven files, one of
  them `.vscode/settings.json` — a tracked file that was never in scope, and a
  side effect of an environment tool rather than of the task. It was caught
  because the coordinator chose to read `git status` and every diff hunk.
  Nothing required that, which is the whole problem: a rule telling agents to
  declare environment changes is enforced by the same diligence that was
  missing. Refs #123.

  The regression job now fails a pull request touching those paths unless the
  body carries `env-change: <reason>`. It is a step in the job that is already
  required rather than a new job, because a new job means a new status-check
  context and a hand-edited branch ruleset. The reason must be at least ten
  characters: a bare marker is a checkbox, and a checkbox gets ticked. The body
  is read from the API so that adding the line and re-running clears the check,
  HTML comments are stripped so the commented-out template line cannot satisfy
  it, and an unreadable file list or body fails closed. Like the attestation it
  sits beside, this is a *declaration* gate — it proves somebody wrote down why
  the environment changed, and it must never be cited as review. Refs #164.

- **The declaration gate has its own decision table (#164).** The gate is a
  PowerShell block inside a workflow, so `run-all-tests.ps1` does not reach it
  — that sweep covers the payload. `.github/scripts/test-env-change-gate.py`
  extracts the step's script from the workflow and executes it against a
  stubbed `gh`, nine cases, one child process each. Extracting rather than
  retyping is the point: a copy of the logic would prove only that the copy
  works. It runs in CI on every pull request, so the gate is not a shipped
  script that nothing ever executed — the defect class #61 records.

  It earned its keep immediately. The first implementation matched the marker
  with `\s*`, which swallows the newline after an empty `env-change:`; the
  marker then read as absent and the author got the generic "add a line"
  message instead of "your line states no reason". The exit code was right and
  the diagnosis was wrong, which is exactly the kind of defect that survives
  review and dies in a decision table.

  Then the table missed one, and that is the more useful half of the story. It
  reported nine of nine green while CI failed the very pull request that
  introduced the gate: the check could not see its own declaration. PowerShell
  hands back a native command's multi-line output as an *array of lines*, and
  casting that array to a string joins it with spaces — collapsing the body to
  a single line and defeating every line anchor. The stub returned one string,
  so the suite exercised a shape that never occurs. A test double that is
  tidier than reality tests the double. The stub now splits, the failure
  reproduces without the fix, and the body is joined with `Out-String`.

- **Formatting is now a gate, not a suggestion (#124).** `run-lint.ps1` is the
  mandated lint runner — *"all agents MUST use this script instead of calling
  ruff directly"* — and it ran `ruff check` only. `ruff format --check` was
  never run by anything. A consumer project measured the consequence: two
  agent-authored test files were committed unformatted across two commits, and
  the gate printed `LINTING_GATE_PASS` with exit 0 every time. The same files
  were clean on the base branch, so the drift was agent-attributable, and the
  project standard names both tools while only one was enforced.

  `check-python-linting.py` now runs `ruff format --check` over exactly the
  file set it already lints. The check sits in the checker rather than in the
  runner because the checker is what the `implementer-stop` and
  `refactorer-stop` hard gates execute; fixing only the runner would have left
  the gate itself unchanged. Formatting is binary, so it applies at every
  `LINTING_STRICTNESS` level and is unaffected by `project_ignore` — it is not
  a rule selection. The gate line now carries `format=clean` or
  `format_drift=N` either way, so the signal is present in the output and not
  only in the exit code, and a failure names each drifted file plus the one
  command that clears it. `-Fix` / `--fix` now applies `ruff format` as well,
  so the remedy the gate names actually works.

  Fails closed: if `ruff format --check` cannot be executed, or ruff itself
  errors, the gate reports blocked (exit 1) and never clean.

  **Existing projects may see a red gate on the first run after upgrading.**
  That is the drift this change exists to surface. `run-lint.ps1 -Fix` clears
  it in one commit.

### Changed

- **`--seed-project-budget` now fills in only the ceilings that were never
  set.** Adding a ceiling used to force a project that had already seeded to
  choose between re-baselining the ones it had tuned (`--force`) and leaving
  the new one ungated forever. Neither is a decision anyone should have to make
  to receive an upgrade. `--force` still replaces everything.

### Fixed

- **`test-context-budget.ps1` dropped two checks in a consumer without saying
  so (#224).** `SS_deploy_ps1_seeds_project_budget` and
  `SS_deploy_sh_seeds_project_budget` are guarded by the presence of the deploy
  scripts, which exist only in the framework source tree. In a consumer the
  guard was false, the block was skipped, and nothing was printed — the summary
  reported `Checks passed: 96 / Checks failed: 0`, which was true and also
  complete-looking. A consumer comparing its run against the framework's had no
  way to tell *"these do not apply here"* from *"these disappeared in the last
  upgrade"*.

  Skips are now a third outcome: named, printed with their reason, and counted.
  That makes the inventory identical everywhere — 99 checks, whether as 99
  passed or as 96 passed and 3 skipped — so the run now asserts that total. A
  check that quietly stops running, or a guard condition that silently stops
  matching, fails the gate instead of shrinking a green number nobody compares.

  The argument for enforcing rather than merely printing it was made during
  #209, one issue earlier: a framework-detection marker written one directory
  level too shallow would have disabled an assertion in *every* environment,
  and was caught only because that particular skip happened to be audible. The
  convention existed; relying on each author to remember it is what produced
  this issue.

- **The shipped hook suite failed in any consumer that customised `RETRO_DIR`
  — 14 red cases, not one of them a defect (#209).** `RETRO_DIR` is marked
  `[customizable]`, and the first consumer to use it as intended got a suite
  that read its own configuration back as broken hooks. The fixtures inherited
  the host's `af-env.conf`, while the behavioural cases seeded their retro at
  the hardcoded `.github/retros/auto/`. Cases expecting a pass got a block,
  cases expecting a block got a pass, and eight timestamp cases read their log
  back unmodified because the gate had stopped the run before enrichment. A
  ninth failure was structural: one case asserted the framework's default into
  the *consumer's* real config, a claim that cannot be true anywhere but here.

  The proof that the hooks were right sat in the failing output itself — the
  gate reported `artifact gate PASS for '72-x' + timestamps measured`, having
  correctly found the retro at the configured path. The suite was wrong about
  the hook, not the hook about the retro.

  The fix is not new machinery. The suite already declares its own policy and
  points the hooks at it through `AF_CONF_PATH`, built after the identical
  failure under a different key: a consumer that had set
  `AUTONOMY_CAT_FS_WRITE=auto` once produced nine phantom failures (#108).
  `RETRO_DIR` simply was not in the declared set. It is now, in both harnesses,
  stripped from the carried-over config and supplied by the policy — so the
  32 hardcoded path literals across the two files needed no change, and the
  cases that deliberately override the key still do, because a fixture's own
  `af-env.conf` outranks the policy.

  The consumer-only assertion is now framework-only, with an audible skip
  rather than a silent one. It was worth keeping — if the shipped config ever
  loses the key, every override case below it would still pass, against the
  default, proving nothing — but it can only be made where the shipped file
  lives.

  Two checks now watch the property that was violated: one asserts a fixture
  carries the pinned default, the other that a case supplying its own config
  still overrides it. Without them the suite is green here and red in every
  consumer that uses a supported setting, which is how this reached a consumer
  at all. That is the failure mode worth naming: a suite that goes red for a
  documented configuration does not merely mislead, it teaches the people
  running it to discount red output — or to revert the setting until the tests
  agree. Either way the next real defect arrives to an audience that has
  learned not to look.

- **Producer stop-hook gates scoped themselves from shared git state, so
  parallel subagents on one branch authored — and falsely claimed provenance
  for — each other's files (#101).** `git diff` is global to the checkout.
  When the coordinator ran two producers at once on the same branch, each
  one's Stop hook read the other's in-flight edits as its own: the quality
  gate demanded docstrings and type hints for a file the agent had been told
  not to touch, and the provenance gate then required it to stamp a
  `copilot:modified` marker naming itself as the author of work it had never
  done. The gate did not merely misfire; it manufactured a false attribution
  and blocked until the agent produced one.

  Who edited which file is not something an agent has to be asked. The editor
  writes one debug log per subagent call, named
  `runSubagent-{agent}-{toolcallid}.jsonl`, and each write tool leaves a
  `tool_call` span carrying its own arguments. A new reader,
  `hooks/scripts/concurrent-agent-edits.py`, walks that directory, takes the
  spans of every *other* subagent whose run overlapped this one in time, and
  reports the files it edited. The four producer Stop hooks subtract that list
  before judging. This is the channel #173 already used to measure which
  agents ran at all — the same principle: a value a model can get wrong should
  be measured, not requested.

  Three design decisions are worth stating, because two of them depart from
  the issue:

  - **The issue's own option 2 — snapshot the diff at agent start and judge
    only what changed after — does not work, and the issue's claim that it
    fixes the concurrent case is wrong.** A baseline taken at start excludes
    only what a peer changed *before* that moment. Under genuine concurrency
    both agents start together and do their editing afterwards, so every peer
    edit lands *after* the snapshot and stays in scope. The option repairs the
    sequential-within-branch case only.
  - **Option B — an interlock that refuses to launch a second producer — was
    rejected on the framework's own recorded grounds, not out of caution.**
    `collect-agent-invocations.py` states the doctrine directly: *"nothing
    here blocks: a watchdog that fails a legitimate multi-session workflow
    gets switched off, and a hook nobody runs protects nothing (issue #108)."*
  - **Subtraction, not intersection.** Scoping each agent to "the files my own
    log says I edited" would be tighter, and fails dangerously: one unrecognised
    edit-tool name would collapse the scope to empty and every gate would pass
    in silence. Subtracting only what a peer *positively claims* means every
    failure mode subtracts less and lands back on today's behaviour. The gate
    can lose the fix; it cannot lose its teeth. Every error path in the reader
    and in both `_common` helpers returns an empty list for the same reason.

  **The filter is confined to the authorship and quality scopes. The lint
  scope is deliberately left whole.** This was a correction made during
  implementation: the first version subtracted peer files from the lint scope
  too, which contradicts the boundary #86 drew and the existing suite already
  asserts — *a ruff violation is real whoever produced it*. The peer's own
  Stop hook lints the peer's files, so nothing goes unlinted; scoping there
  would have converted a correction into a bypass. Both harnesses now assert
  that the lint scope stays unfiltered, so the mistake cannot be made twice.

  `coordinator.agent.md` still forbids running producers in parallel, and the
  wording was tightened rather than relaxed: subtask independence is not
  sufficient grounds, `WORKTREE_ENABLED=true` does not help (one worktree per
  workflow, not per subagent), and the hook change repairs the misattribution
  without licensing the practice. Read-only agents — the critics, `researcher`,
  `compliance-checker`, `Explore` — may still be parallelised.

  Two defects in this change were found and fixed by its own controls, and are
  recorded here because both produced confident, plausible, wrong output:

  - The timestamp regex required no whitespace after the colon
    (`"ts":(\d+)`). Any log written by `json.dumps` — which emits `"ts": 1000`
    — yielded *zero* timestamps, and the reader then fell through to its
    unknown-bounds branch and subtracted a peer that had never overlapped.
  - That fallback was itself wrong. It treated unknown bounds as overlapping,
    which subtracts *more* — in direct contradiction of the safety property
    stated three paragraphs above it in the same file. Unknown bounds now mean
    no overlap. The stated invariant had to be checked against every branch,
    not just the ones the author had in mind.

  **Measured.** `test-hooks.ps1` 335 → **349 passed, 0 failed** (14 new cases);
  `test-hooks.sh` 169 → **178 passed, 0 failed** (9 new cases);
  `test-hooks-integration.ps1` 8 passed, 0 failed. The reader's own control
  suite covers 12 cases including shared authorship, a read-only peer, a
  non-overlapping peer, a path outside the repository, an unrecognised write
  tool, and both "nothing measurable" exits.

  The new cases were then checked for teeth by mutation, with the expected
  failures declared before each run:

  | mutation | cases that must go red | result |
  |---|---|---|
  | timestamp regex loses `\s*` | overlapping peer subtracted; nested replacements harvested; unknown write tool caught | exactly those, and only those |
  | unknown time bounds treated as overlapping | non-overlapping peer is ignored | exactly that |
  | every tool counts as an edit | `read_file` is not an edit; `create_and_run_task` is not a write | exactly those |

  The first run of that control was itself wrong twice, and both corrections
  are the useful part: the predicted red set for the regex mutation was
  mis-specified (the *compact* fixture, `"ts":1000`, is the one format the
  brittle pattern still parses — which is exactly why the defect stayed hidden),
  and the changed-line counter reported 158 changes for a one-line insertion
  because it compared line by line instead of diffing. The tests had teeth; the
  predictions did not. Mutation coverage is confined to the reader's logic —
  the harness assertions about hook wiring and the lint-scope boundary are
  static checks and were not mutation-tested.

  **Honest limits.** This reads one editor session: producers launched from
  two separate chat sessions against one branch are not covered. Peers are
  matched by time overlap, so a peer that finished before this agent started
  is correctly ignored but a long-idle overlapping peer is still counted. The
  caller's own log is identified by most-recent modification time, which is a
  heuristic. The bash twin extracts `transcript_path` with the same
  `grep`/`sed` idiom the documenter hook already uses and inherits its existing
  limitation with escaped Windows paths.

- **The worktree gate mis-read any path containing a space, and shipped with no
  test cases at all (#200).** Both twins extracted the path and branch with
  `\S+`, which stops at the first blank. For

  ```
  git worktree add "c:\...\OneDrive - Siemens Healthineers\MP Usage XP.worktrees\3097" agent/3097-micro-movements
  ```

  the PowerShell twin read the `-` out of `OneDrive - Siemens` as an argument
  and denied a perfectly valid branch name, while the collision guard tested
  `"c:\...\OneDrive` — a path that does not exist — and waved everything
  through. The reporter's summary was blunt and correct: this made worktrees
  unusable in any repository whose path contains a space.

  Measured against both twins with byte-identical payloads, before and after:

  | case | `ps1` before | `sh` before | both after |
  |---|---|---|---|
  | quoted path with spaces, valid branch | **deny `'-'`** | silent | silent |
  | unquoted path, valid `-b` branch | silent | silent | silent |
  | unquoted path, **invalid positional** branch | deny | **silent** | deny |
  | unquoted path, invalid `-b` branch | deny | deny | deny |
  | collision, existing path **with** spaces | **silent** | **silent**, invalid JSON | deny |
  | collision, existing path without spaces | deny | deny | deny |

  Two of those columns are defects the issue did not report, and both were
  found only because the twins were measured side by side rather than one
  after the other:

  - **The bash twin never parsed a positional branch.** It handled `-b` only,
    so `git worktree add ../wt/bad main` was denied on Windows and allowed on
    macOS and Linux. The issue states bash "has the identical issue"; it does
    not. It could not mis-read the branch because it never read it. Same
    symptom class as #123: one gate, two platforms, opposite verdicts.
  - **The bash twin emitted unparsable JSON for Windows paths.** It
    interpolated values straight into a hand-built string, so `\U` in
    `c:\Users\...` is not a JSON escape and the client discarded the object.
    The gate reached the *correct* deny and the deny reached nobody — a
    silent fail-open. A new `af_json_escape` helper in `_common.sh` covers the
    two call sites here; the remaining 42 interpolation sites across 12 files
    are filed as #202 rather than folded into this change.

  **Deviation from the fix the issue proposed.** It suggested keeping
  `grep -oP` with a longer regex. `-oP` is a GNU extension, absent on macOS
  and BSD, so a hook depending on it is broken on the platforms this gate is
  meant to protect. Both twins now use a quote-aware tokeniser instead — a
  POSIX `case` loop in bash, `[regex]::Matches` in PowerShell.

  **The gate had zero test cases in either harness before this change.** A
  grep for `worktree` across both suites returned two prose comments and
  nothing executable. That is how a defect of this size reached users. Six
  cases were added per harness: `test-hooks.sh` **163 → 169 passed, 0 failed**;
  `test-hooks.ps1` **329 → 335 passed, 0 failed**.

  Each new case was then falsified by mutation. The mapping is one-to-one
  except where noted:

  | mutation | case that goes red |
  |---|---|
  | `ps1` tokeniser reverted to `\S+` | quoted path fakes a bad branch |
  | `ps1` path extraction reverted to the truncating regex | collision, path with spaces |
  | `sh` tokeniser replaced by word splitting | quoted path fakes a bad branch |
  | `sh` positional branch assignment deleted | invalid positional branch |
  | `af_json_escape` stops escaping | **both** collision cases, as `UNPARSEABLE` |

  Three things about that table are worth stating rather than leaving to be
  inferred. The negative control drives the hooks directly with the six
  payloads the harness cases assert on, instead of re-running both suites five
  times; it therefore proves the *hook behaviour* changes under mutation, while
  the harness reporting that change is what the 169/0 and 335/0 runs show. The
  two `-b` branch cases are not falsified by any mutation here — they guard
  behaviour this change did not touch and are regression anchors, not evidence
  for the fix. And `UNPARSEABLE` is scored as its own outcome, never folded
  into `silent`: a hook that decides correctly and emits broken JSON has been
  discarded by the client, and calling that "silent" would conceal precisely
  the defect above.

  A first attempt at the PowerShell mutation was **discarded as invalid**: it
  rewrote every line ending and wrote `'\\S+'` instead of `'\S+'`, so the hook
  matched nothing and fell silent on all six cases. Four reds that looked like
  a result were a dead hook. The changed-line counter is what caught it — 484
  lines where 2 were expected.

  One harness defect surfaced on the way and is fixed here too:
  `Invoke-HookInFixture` built its fixture with `git checkout -q -b $Branch`,
  which fails with ``switch `b' requires a value`` when a case seeds files but
  declares no branch. Every prior `-Files` case happened to pass a branch, so
  the empty value was never reached. The fixture died before the hook ran and
  the case reported a git error where a verdict belonged.

- **Three producer gates ran the suite and then threw the result away (#123).**
  The issue reported an implementer that "echoed its verification commands back
  and declared broken code complete", and a test-writer whose measured red was
  wrong on two tests. Both turned out to have a mechanical cause underneath the
  behavioural one, and it is the same line in three hooks:

  ```bash
  output=$(pytest ...) || true
  exit_code=$?          # the status of `true`, which is 0 on every path
  ```

  Measured, by running the idiom against a command with a chosen exit code:

  | intended exit | 0 | 1 | 2 | 5 |
  |---|---|---|---|---|
  | captured with the `\|\| true` | 0 | 0 | 0 | 0 |
  | captured without it | 0 | 1 | 2 | 5 |

  The gate therefore could not see a failing suite at all. The three hooks fail
  in **opposite directions**, which is why neither direction was reported as the
  same bug:

  | hook | gate | pre-fix behaviour |
  |---|---|---|
  | `implementer-stop.sh` | Green | fails **open** -- a failing suite never blocks |
  | `refactorer-stop.sh` | Refactor | fails **open** -- a refactor may break the suite unchallenged |
  | `test-writer-stop.sh` | Red | fails **closed** -- every legitimate Red phase is blocked as "all tests PASS" |

  Verified by executing each hook against a stubbed runner whose exit code is
  the input under test: before the fix, `implementer-stop.sh` and
  `refactorer-stop.sh` answered *pass* to a suite exiting 1, and
  `test-writer-stop.sh` answered *block* to all three of exit 0, 1 and 2.

  `scan-secrets.sh` had already been fixed for this exact bug, with a comment
  naming it -- *"a detection was reported as a pass every single time"*. It was
  never swept across its siblings. Knowing a bug once is not the same as
  removing it.

- **Not every red is a red (#123).** The Red gate read two exit codes -- 0 meant
  "all tests pass", 5 meant "nothing collected" -- and let everything else fall
  through to *Red phase satisfied*. A test file that cannot be imported, or a
  test that dies in setup, was therefore counted as a genuine red. It never
  reaches the behaviour it claims to guard and it stays red after a correct
  implementation, so the Green phase is sent hunting for a defect that does not
  exist. That is the mechanism behind the issue's second finding.

  Reading the exit code alone is not enough. Measured against pytest, 2026-08-24:

  | case | exit | summary line |
  |---|---|---|
  | failing assertion | 1 | `1 failed` |
  | collection `ImportError` | 2 | `1 error` |
  | syntax error | 2 | `1 error` |
  | missing fixture | **1** | `1 error` |
  | `ValueError` raised in the test body | 1 | `1 failed` |

  A missing fixture exits 1, exactly like a genuine failure, so both twins now
  read the summary line as well: exit 2 **or** a summary matching `N error`
  blocks, with an explanation of what to fix.

  **Deliberately not done: blocking on non-`AssertionError` failures.** A
  genuine red against production code that does not exist yet legitimately
  raises `AttributeError` or `ImportError` from inside the test body, and the
  last row of that table shows such a case is indistinguishable from an
  assertion failure by the summary line. A gate that fails honest work gets
  switched off (#108), so this stays guidance rather than a HARD gate.

  Also **not** addressed from the issue: the scope-breach diff (direction 3 --
  the Stop hook has no declared in-scope file list to diff against) and treating
  an empty producer return as a failed handoff (direction 5 -- coordinator-side,
  not a hook's job). **#123 stays open.**

  A correction to the framing used on #175 and #134: a Stop hook's payload
  carries no return text and no agent identity -- measured, it is
  `hook_event_name`, `session_id`, `transcript_path`, `stop_hook_active`, `cwd`.
  But `transcript_path` resolves to a debug-log directory holding one
  `runSubagent-{agent}-{id}.jsonl` per invocation, and those files contain
  machine-written `tool_call` records naming every tool the subagent ran --
  `documenter-stop.ps1` already navigates exactly that path. "Did the agent
  actually run the tests" is therefore *reachable*, from a better source than
  the agent's own prose. It is not built here, but it is not impossible, and the
  earlier wording implied that it was.

  **Regression coverage, and what it is worth.** Fourteen cases were added that
  execute the hooks against a stubbed runner whose exit code and summary line
  are the input under test -- nine in `test-hooks.sh` (163 passed / 0 failed,
  from a baseline of 154) and five in `test-hooks.ps1` (329 / 0, from 324).
  Text-only coverage would have proved nothing here: every one of these gates
  read the right variable and then acted on a value that was already wrong.

  Each case was then checked against a mutation of the hook it guards, because
  a case no mutation can turn red is not a test (#173). Every case fell to
  exactly one mutation, and to a different one:

  | mutation | case turned red |
  |---|---|
  | `\|\| true` restored in `test-writer-stop.sh` | a failing assertion is a satisfied red; no tests collected is not a verdict |
  | red-validity branch deleted (both twins) | a collection error is not a satisfied red; a setup error exiting 1 is not a satisfied red |
  | exit-0 violation branch deleted (both twins) | a green suite is not a red phase |
  | exit-5 skip turned into a violation (PowerShell) | no tests collected is not a verdict |
  | error regex widened from `\d+ error` to `\d+ ` | a failing assertion is a satisfied red |
  | `\|\| true` restored in `implementer-stop.sh` / `refactorer-stop.sh` | a failing suite blocks the implementer / the refactorer |
  | green suite no longer accepted (both) | a passing suite does not block the implementer / the refactorer |

  The last row matters as much as the first: without it, half the suite would
  only prove the gates can block, not that they can still let honest work
  through. The widened-regex row is the one that shows the error check is
  guarded for its *precision* and not merely for its existence.

  `test-hooks-integration.ps1` was run as required for a hooks change (8 checks
  passed / 0 failed) and says nothing about this fix: all three modified hooks
  appear in its own orphan-candidate list, never having fired in the logs it
  reads.

- **Two provenance gates were not gates: one never ran, one had no checker
  (#175).** `test-writer-stop` called `Test-AfProvenanceMarker` /
  `af_has_provenance_marker` without ever sourcing the file that defines them.
  It was the only hook script in the payload doing so. The two twins then
  failed in **opposite directions**, which is why neither was noticed:

  | | marked file | unmarked file |
  |---|---|---|
  | PowerShell, helper unsourced | not flagged | **not flagged** |
  | bash, helper unsourced | **flagged** | flagged |
  | either twin, after sourcing | not flagged | flagged |

  PowerShell abandons the enclosing `if` on a command-not-found error, and the
  hook sets `$ErrorActionPreference = 'SilentlyContinue'` — so the gate was a
  silent fail-open. Bash returns 127, which `if ! …` reads as "no marker" — so
  it blocked every new test file, marked or not. Both twins now source
  `_common`; the PowerShell one uses the standard preamble instead of a
  hand-rolled worktree block.

  The pre-existing suite case asserted only that each hook *mentions* the
  shared detector. A call site is not a resolved call, so a text match could
  never have caught this. The replacement enumerates every hook script,
  detects which of the eight shared helpers it calls, and requires the file to
  source the one defining them — it is green across all of them, i.e.
  `test-writer-stop` was the sole offender.

  Separately, `refactorer-stop` had **no provenance gate at all** — not a weak
  one. The refactorer's reported "marked as `copilot:modified` in both files"
  was therefore checked by nothing, and the diff carried no marker. It now
  runs the same gate as `implementer-stop`, filtered through
  `--list-authored`. That filter matters most here: the refactorer is the
  agent that runs `ruff format`, and a marker may only be demanded of a file
  it actually wrote in (#86). `refactorer.agent.md` gains the matching HARD
  gate row, stating that the Stop hook checks it and the agent does not
  self-certify.

  A correction to the issue's report: the gate row it quotes
  ("Scan changed files for markers") is the **documenter's**, not the
  refactorer's. That one is not a maker-checker violation — the documenter
  scans files other agents wrote — and is left alone.

  Measured locally: `test-hooks.ps1` 305 → 306 for the sourcing check, →
  **312** with the refactorer cases; `test-hooks.sh` re-run after the `.sh`
  edits; `test-hooks-integration.ps1` re-run because the diff touches
  `.github/hooks/`. Negative control, one mutation at a time, each turning
  exactly its own case red and nothing else: removing either twin's `_common`
  sourcing, removing the refactorer's provenance call, and removing its
  `--list-authored` filter.

  **Not addressed by this change**, and #175 stays open for it: re-verifying
  advisories an agent claims to have resolved, and treating an empty subagent
  return as a hard failure. The latter cannot live in a Stop hook at all — a
  hook does not receive the subagent's return text — so it belongs to the
  coordinator. *(Corrected under #123: the payload carries no return text, but
  the debug-log tool-call records are reachable from it, so this is unbuilt
  rather than impossible.)*

- **A workflow log named a subagent that was never called (#173).** The
  documenter wrote a `steps[]` entry for `arbiter` in a workflow where no
  arbiter ran. Nothing in the artifact contradicted it, so the only way to
  catch it was to remember the workflow — which is exactly what the log exists
  to replace.

  The editor already keeps a machine-written record of which subagents ran: the
  session's debug-log directory contains one `runSubagent-{agent}-{callid}.jsonl`
  per invocation. Those filenames never pass through a language model. Measured
  here by listing `%APPDATA%\Code\User\workspaceStorage\**\debug-logs\**` —
  `runSubagent-implementer-…`, `runSubagent-test-writer-…`,
  `runSubagent-ado-pr-manager-…`. `documenter-stop` already resolved that
  directory for the cost block, so the input was in reach.

  The new `collect-agent-invocations.py` (stdlib only) counts those files per
  agent and appends an `agent_invocations:` block to the log: `observed:` with
  the counts, and `claimed_without_invocation:` listing any agent named in
  `steps[]` with no invocation log. The fabricated `arbiter` step is now
  refutable by reading the same file it appears in.

  **Nothing gates on it, deliberately.** The count covers one chat session, so
  a workflow resumed in a later window would fail a check it did not deserve —
  and a hook that fails honest work gets switched off, which is the #108 lesson.
  `observed:` is therefore documented as a lower bound, and the block carries
  that caveat inline. When no subagent logs exist at all the recorder exits 1
  and writes nothing, rather than stamping an empty block that would read as
  "no agents ran" (#59: an unrun check is not a pass).

  Measured: the recorder's own suite `test-agent-invocations.ps1` 22 passed /
  0 failed; `test-hooks.ps1` 298 / 0 before the seven new end-to-end cases and
  **305 / 0** after; `test-hooks.sh` 154 / 0 (measured before those PowerShell-
  only cases were added — `documenter-stop.sh` itself is unchanged since, and
  its wiring is covered by `bash -n` plus the existing twin cross-checks, not by
  an end-to-end case); `test-hooks-integration.ps1` 8 / 0.

  A mutation control decided which of those cases are evidence. Breaking the
  agent-name split turned the hyphenated-name case red; removing the block-scalar
  skip turned the block-scalar case red; removing the `steps:` boundary turned
  the other-section case red. A fourth mutation — removing the top-level-key
  guard — left its case **green**, because a top-level `agent:` clears the
  `steps` flag by itself before that guard is reached. That case was measuring
  nothing, so it was deleted rather than shipped, taking the suite from 23 back
  to 22.

  **What this does not fix.** `summary.tests_added`, `summary.provenance.*` and
  `escalation.step_at_escalation` are still written by hand and still fabricable;
  the same reported workflow claimed `tests_added: 122` for 11 tests and "6 files
  checked, 6 markers present" having read no file. No mechanical source exists
  for `tests_added` (`test-log.json` records passed/total, not added), and a
  naive provenance derivation would produce a new wrong number, since AF
  framework files and `docs/**` are deliberately unmarked. #173 stays open.

- **The watchdog quoted a file it had not read (#174).** A post-flight
  compliance report presented a sentence as a direct quotation from the
  workflow's retro; the retro contained neither that sentence nor the work item
  it cited. The same report asserted `ADO_CAPABILITY_MODE=off` while the config
  said `optional` — the mode had been inferred from the absence of a PR, which
  is the very thing the check exists to assess. The report's conclusion was
  correct anyway, and that is what makes this the dangerous shape: a fabricated
  premise reaching a right answer cannot be caught by reading the answer.

  The compliance-checker now carries a content rule beside its existing
  existence rule: quote only what you read in this pass, cite `{path}:{line}`
  for every quotation, locate a property by line number instead of retelling
  it, and read configuration from `af-env.conf` rather than deducing it from
  observed behaviour. The post-flight return format demands those citations, so
  a missing one is visible in the artifact rather than buried in a transcript.

  An agent file is a prompt, and no test can prove an LLM will obey one. What
  the four new suite cases prove is narrower and still worth having: the
  requirement is present, and removing it turns the suite red. Measured — 298
  passed / 0 failed with the rule, and 294 passed / **4 failed** against the
  previous version of the agent file, failing exactly the four new cases and
  nothing else. The requirement is chosen so that a violation is refutable by
  opening one path, which is the property the fabricated quotation lacked.

- **The hook suite failed a project for configuring the hooks (#108).** Every
  "asks by default" case in `test-hooks.ps1` was a claim about an autonomy
  policy, and the policy came from whichever `af-env.conf` the running checkout
  shipped. Measured here on the same commit: 287 passed / 0 failed in this
  repository, and 278 passed / **9 failed** from a copy whose config set
  `AUTONOMY_CAT_FS_WRITE`, `AUTONOMY_CAT_DATABRICKS` and
  `AUTONOMY_CAT_CLOUD_READ` to `auto` — a supported, documented choice. Those
  nine failures were that project's configuration read back as broken safety
  hooks. The suite is what tells a project whether its hooks work, so a false
  red teaches either to ignore it or to revert a legitimate setting to make it
  pass; both are worse than not having the test.

  The shared preamble now honours `AF_CONF_PATH`, and both suites write a config
  holding a **declared** policy and point the hooks at it. The verdict is a
  function of the stated policy instead of the consumer's settings: the same
  consumer copy now measures 294 passed / 0 failed, identical to this
  repository. Seven new cases in `test-hooks.ps1` and six in `test-hooks.sh`
  (150 passed / 0 failed) assert the other half of the matrix — the same
  delete `allow`ed under a declared `FS_WRITE=auto`, `ask`ing again once the
  opt-in is withdrawn, and a declared `DATABRICKS=deny` denying what the shipped
  config never denies, which is what proves the declared file is the one in
  force. Both summaries now print the policy they judged under.

  Two boundaries are pinned by cases rather than by prose. A config path that
  does not exist counts as **no config**, not as a fallback to the deployed one:
  falling back would put the consumer's settings back in play behind a typo. And
  the seam moves the ask/auto boundary only — the deny tier is hardcoded and
  resolved before any category is read, so `Remove-Item -Recurse -Force` is
  still denied under `FS_WRITE=auto`. Anyone able to set the variable on the
  hook process already controls that process; hooks are launched by the
  extension host, so an assignment in an agent's terminal does not reach them.

- **An interrupted test run read as the previous run's result (#179).** The test
  runner built its `test-log.json` entry only after pytest returned. A run that
  was interrupted — terminal closed, agent cancelled, machine slept — left the
  previous entry untouched, still saying `"status": "ok"` with yesterday's
  counters. Nothing in the file distinguished it from a run that had just
  finished green. Under the once-per-workflow test budget the next reader skips
  the suite on exactly that evidence, so an abandoned run was silently promoted
  to a passing one.

  Both runners now claim their entry *before* pytest starts: `status: running`,
  a `started` timestamp, and counters `null` — never `0`, for the same reason
  the runner-failure path uses `null`. When pytest returns, the result replaces
  the marker. An interrupted run therefore leaves behind a state that says so.
  The `test-execution` skill gained the matching rule: `running` is not
  evidence, in either of its two meanings (a live run or an abandoned one).

  The interim write is a merge like the final one, so the marker cannot evict
  the other scopes' entries — that would have traded #179 for #93. Measured on
  the shipped scripts through `test-run-tests.ps1`: **28/28 passed**, up from 23,
  with the four new PowerShell cases and the four bash cases failing first for
  the right reason (during the run, the log still read `passed=42 total=42` for
  the scope being re-run).

- **Every completed run of `run-tests.sh` was logged as `0 passed` (#179,
  found while fixing it).** The summary parser matched with `grep -E '\d+
  passed'`. `\d` is PCRE; in an ERE `grep` reads it as a literal `d`, so the
  pattern never matched a pytest summary line. `SUMMARY_LINE` was always empty,
  which meant a green run was recorded as `0 passed / 0 total` with
  `status: ok`, and a run with real test failures was recorded as
  `status: error` — "pytest did not run" — when pytest had run and reported
  them. The extraction that followed used `grep -P`, which is absent from BSD
  and macOS grep entirely.

  Both are now POSIX classes (`[0-9]`, `[[:space:]]`) with `grep -Eo`. Verified
  against the three dialects on Git bash 5.2.37: the old ERE pattern exits 1 on
  `3 passed in 0.42s`; `-P` and the POSIX form both return `3 passed`. Pinned by
  a case that asserts the parsed counters *and* the runtime, so a parse that
  regresses to matching the first number it finds still fails.


  splits a command into quote-aware units, so that a string literal mentioning a
  dangerous construct is read as data. Three deny rules opted out of that and
  matched the raw command line instead: pipe-to-shell, `DROP TABLE|DATABASE`,
  and `TRUNCATE TABLE`. A PowerShell line building a label that happened to
  contain `| bash` was hard-denied, and so was every commit message or `echo`
  that named `DROP TABLE` — including the ones written while fixing this class
  of bug. The reported case was the narrow one; a probe showed all three rules
  were affected.

  The rules scan the raw line for a reason — a pipe into `bash` spans units by
  construction — so the fix is not a global "strip quotes everywhere" switch.
  That would have laundered the real attack: SQL clients accept a statement
  positionally, so `sqlite3 app.db "DROP TABLE users"` is a genuine destructive
  command whose payload is quoted. The two threat models are separated instead:

  **exec** (pipe-to-shell) treats every quoted literal as data, because a `|`
  inside quotes is not a pipe — only an interpreter makes it one, and
  interpreter payloads (`bash -c "…"`, `powershell -Command "…"`) are already
  extracted and scanned as their own targets. **prose** (SQL) exempts only
  recognised prose carriers — `echo`/`printf`/`Write-*` and
  `git commit|tag|notes|stash` — plus bare literals; anything else keeps the
  deny. Where the command contains `$(` or a backtick, the raw line stays a
  target in both modes: quotes do not make a substitution inert.

  Acceptance criterion 1 is therefore met **fully for pipe-to-shell and only for
  prose carriers for SQL**. That gap is deliberate and is the safer half of the
  trade the issue asks about.

  Measured, not reviewed: ten new assertions bring the hook suite to
  **287 passed, 0 failed**, a nine-case probe runs the bash hook and passes 9/9,
  and a control run of the same probe against the pre-fix build reproduces the
  defect (`deny`) on both false-positive cases, so the comparison is against the
  real prior behaviour rather than an accidental copy. `sqlite3 app.db "DROP
  TABLE users"` and `git commit -m "$(curl … | bash)"` are still denied.

  A first draft of the fix started the Python splitter three times per hook
  invocation, in a hook that runs before every terminal call. Wallclock could
  not settle it — the same unmodified build measured 17970 ms and 14042 ms per
  call on this host — so the cost was counted instead of timed, via an
  `AF_PYTHON_OVERRIDE` wrapper that tallies interpreter starts. The splitter now
  returns every view the tiers need in one RS-separated response: **1 start
  before, 1 start after**, where the draft would have cost three.

- **The delegation check accused on presence, not on causality (#172).**
  `coordinator-posttooluse` ran `git status --porcelain` after every terminal
  call and reported a DELEGATION VIOLATION whenever the working tree was dirty.
  It never established *who* made the change. In a normal TDD workflow subagents
  hold uncommitted work in exactly those directories for the whole span between
  phase commits, so the warning fired on essentially every coordinator terminal
  call — each time asserting a Cardinal Rule 1 breach that had not happened, and
  each time advising `git checkout -- <file>`, which would have discarded the
  subagents' work.

  A guard that fires on the normal case teaches the operator to ignore it, so it
  is also ignored on the one occasion it is right. The fix supplies the missing
  evidence instead of tuning a threshold: `coordinator-pretooluse` writes a
  baseline of the already-dirty entries to `af-delegation.snapshot` inside the
  git directory before it allows a terminal call, and the PostToolUse hook
  reports only entries absent from that baseline. Whole porcelain lines are
  compared rather than paths alone, so a staged/unstaged transition still counts.

  Two properties follow deliberately. Without a baseline the hook stays
  **silent** — absence of evidence of causality is not evidence of a violation,
  and accusing anyway is the defect being removed. And the destructive
  `git checkout --` advice is gone: the remedy is to delegate the change, never
  to discard uncommitted work.

  The hook had no unit coverage at all. `test-hooks.ps1` never invoked it and the
  integration suite only checked *that* it fires. Seven assertions now cover the
  silent-without-baseline case, the false positive from the issue, the true
  positive, the absence of the destructive advice, tool scoping, and the
  PreToolUse write. Suite: **279 passed, 0 failed**.

  The bash twin carries the same logic **and one further fix**. It used
  `[ -z "$X" ] && echo '{}' && exit 0`, which evaluates to 1 whenever `$X` is
  non-empty and so aborted the hook under `set -euo pipefail` — the exact
  failure mode its own header comment warns about twenty lines above. Both
  occurrences are now `if` blocks. **This was not executed:** the authoring host
  has no bash, so every bash change here is reviewed, not measured (#168).

- **The test guard denied reading, not running (#183).** `coordinator-pretooluse`
  decided "this is a test run" with `$command -match '\bpytest\b'`. A `.` counts
  as a word boundary there, so grepping the configuration header `[tool.pytest`
  was a hard deny — on a command that read a JSON file, listed processes and
  searched a TOML file, and ran no test at all. The denial's advice made it
  worse: `runTests` and the test tasks cannot read a file or list a process, so
  the only available recourse was to rephrase the command to avoid a word. That
  is precisely the evasion behaviour the guard exists to prevent.

  The gate now matches an *invocation* rather than the word: `pytest`,
  `py.test`, `python -m pytest`, or a runner form such as `uv run pytest`,
  anchored to the start of a statement, allowing a path prefix and quotes so
  `& ".venv\Scripts\pytest.exe"` still counts.

  Anchoring closes a hole in the other direction as well. `git status ; pytest
  tests/` was caught before only by accident of the substring, and a narrowing
  that looked at the first token alone would have turned that accident into a
  bypass. `test-hooks.ps1` now holds both directions — three denials, two
  permissions, including the command from the issue verbatim.

- **The hooks README said JSON hooks do not run. They do (#166).** Three
  places in `.github/hooks/README.md` called the `.json` files "currently
  orphaned", "legacy fallbacks" and "not currently auto-loaded by VS Code",
  while a fourth section in the same file called them "Active Hooks (ready to
  use)". A reader had no way to tell which half to believe, and the wrong half
  invites the conclusion that the shipped guards are inert.

  Two independent measurements settle it. A workspace folder containing
  nothing but a `.github/hooks/agent-hooks.json` — no agents, no instructions
  — ran its `PreToolUse` hook 13 times in one session with the working
  directory set to that folder; nothing else could have registered it. And in
  a log of 4,146 hook runs, a single `PreToolUse` event shows
  `block-dangerous` followed by `test-writer-pretooluse` 167 times, where
  `test-writer.agent.md` declares only the second — so both sources fire into
  one event and neither replaces the other.

  The README now says that, and carries the evidence rather than an assurance.
  What it explicitly does **not** do is act on it: the duplicate declarations
  stay. The same log shows `scan-secrets` running twice inside one event 476
  times with no frontmatter hook to account for the repeat, and until that is
  explained, removing a declaration risks removing the only copy that runs. A
  hook that fires twice costs a second; a guard that quietly stops firing is a
  hole nobody sees.

- **The hook test drew the same false conclusion, and its evidence was
  contaminated (#166).** `test-hooks-integration.ps1` printed "agent-hooks.json
  may not be loaded by VS Code" and advised wiring the hooks into agent
  frontmatter instead — the claim the README just retired, in a script people
  run to check their setup.

  It reached it by putting `SessionStart` hooks in one list with tool-scoped
  ones. A tool-scoped hook fires on every matching call, so its absence from a
  log holding hundreds of invocations means something. `SessionStart` fires
  once per session, while the log file is created per window: a window reload
  opens a fresh log mid-session, and that log cannot contain the event that
  preceded it. Across 8 logs and 7,127 recorded hook events there is exactly
  one `SessionStart` — and it ran `session-context.ps1` to completion, Success
  in 3330ms, returning `additionalContext`. The event works; it is rarely
  captured. The check now separates the two and reports the second as INFO.

  The parser had the opposite fault. Its patterns were unanchored, and the log
  records every tool's response — so anything printed into a terminal comes
  back as quoted text inside a later `PostToolUse` line and was counted as hook
  activity. Printing one raw `Running: ... session-context.ps1` line while
  investigating made the next run report that hook as firing, with no hook
  having run in between. The costly case is `Completed (Failure)`, where a
  phantom match fails the suite and turns the CI gate red. All six patterns are
  now anchored to the start of the message.

  Orphan detection kept the same shape of error, recommending deletion of
  scripts "never invoked by VS Code" when all the log shows is that they did
  not run during the sessions it covers. It now says so, and points at the
  declarations to check before anything is removed.

- **Auto-merge could never be armed for the pull requests that most needed it
  (#170).** `arm-auto-merge.yml` triggered on `opened`, `reopened` and
  `ready_for_review` only. Nothing fires again after a pull request exists, so
  one that was not mergeable at the moment it opened stayed unarmed forever.

  That is not a corner case here. Every payload change touches `CHANGELOG.md`
  and `VERSION`, and the pre-commit hook's automatic `VERSION` bump *guarantees*
  a collision between any two concurrent branches. The workflow therefore
  failed for precisely the pull request that had to queue — the situation #150
  built it for. Observed on #169: opened two minutes after its base moved, born
  conflicted, the arm job failed by design, and resolving the conflict raised a
  `synchronize` event that nothing was listening to. It waited for a human.

  `synchronize` is now a trigger, so the push that resolves a conflict is also
  the push that arms. A still-conflicted pull request exits with a notice
  instead of a failure — failing on every push during a rebase would train the
  author to ignore this job, which is how a guard stops being read.
  Mergeability is computed asynchronously and reads `UNKNOWN` for a moment
  after a push, so the state is polled before it is trusted.

  The control is #171: same workflow, same author, same base, opened onto a
  base that did not move, armed and merged by `github-actions[bot]` six minutes
  later, unattended. Positive and negative case differ in exactly the variable
  named above. What that pair does *not* establish is the fix itself — only a
  pull request that is conflicted at open and then resolved can show that, and
  until one has merged unattended this entry describes an intent, not a result.

- **The framework's own lint-gate suite was writing mixed-line-ending files.**
  Adding the format check turned six previously-green scenarios red, and the
  cause was the harness, not the gate: `Set-Content` terminates a file with
  CRLF, the suite is stored with LF endings, so every here-string fixture was
  written with an LF body and a CRLF last line. `ruff format --check`
  correctly reports such a file as drift. The fixtures are normalised to CRLF
  once, at a single place, leaving all ~24 write sites untouched.

  Worth recording as evidence for #124 rather than as an embarrassment: the
  defect was present in the framework's own test fixtures for as long as they
  have existed, and no gate noticed until formatting became something that
  gets checked.

### Changed

- **The coordinator had two tokens of headroom left (#205).** All three context
  ceilings were measured within 0.7 % of their limits at once — AF always-on
  3,476/3,500, AF conditional 3,824/3,850, and the coordinator at 9,448/9,450.
  A gate that passes by two tokens is not a gate that passed; it is a gate
  about to fail on the next sentence anybody adds, and the agent it would block
  is the one every workflow starts with.

  Fixed by **compression alone** — no rule was removed, nothing was extracted
  into a skill, and no ceiling was raised:

  | budget | before | after | headroom |
  |---|---|---|---|
  | coordinator | 9,448 | **9,128** | 322 / 9,450 |
  | AF always-on | 3,476 | **3,414** | 86 / 3,500 |
  | AF conditional | 3,824 | **3,811** | 39 / 3,850 |

  `coordinator.agent.md`, `quality-gates.instructions.md`,
  `git-workflow.instructions.md` and `tooling.instructions.md` were rewritten
  denser: bullet lists that carried no branching collapsed to prose, split
  paragraphs stating one thing were merged, and pointers to skills were reduced
  to the pointer. Exactly one thing was deleted, and it was not a rule — the
  standalone line restating that Steps 0b and 7b are mandatory bookends, which
  the Steps 1–7b preamble and the Full TDD note both already say. Stating a
  rule three times does not make it three rules.

  Two limits are recorded rather than papered over. The conditional budget
  gained only 13 tokens and still sits 39 from its ceiling — the compressible
  slack in those files is spent, and the next request there will need
  extraction. And the gate counts less than it appears to: `check-context-budget.py`
  measures `copilot-instructions.md` plus the always-matching `instructions/*.md`,
  so the skill catalogue (29 active skills ≈ 1,949 tok), the agent catalogue
  (17 agents ≈ 918 tok) and every MCP tool description are always-on payload
  that no ceiling sees. That is roughly the size of the entire measured
  always-on budget, sitting outside it — which also means extraction into a
  skill relocates tokens out of the measurement rather than out of the request.
  Filed as #206; it is why nothing was extracted here. Refs #205.

- The header comments of `run-lint.ps1` / `run-lint.sh`, `tooling.instructions.md`
  and the `test-execution` skill now state *why* a direct `ruff` call does not
  reproduce the gate: `check-python-linting.py` applies the project's own ruff
  `ignore` / `per-file-ignores` on top of the selected rules, so a bare
  `ruff check --select=…` can report violations the gate does not have. The
  issue reports a real wasted edit caused by exactly this, and the standing
  risk that an agent adds a `# noqa` the project deliberately does not want.
  Agents route around rules whose cost they cannot see.

- **The suite CI cannot run is no longer covered by nothing.**
  `test-hooks-integration.ps1` reads VS Code's own hook log to confirm hooks
  fired during a real agent session, so a hosted runner cannot run it and
  `regression.yml` excludes it by name. Before CI existed, a maintainer's
  hand-run sweep covered it. After CI, the hand-run sweep is the thing CI
  replaced — so the suite stopped being run at all, while the code it covers
  is the most safety-critical part of the payload.

  A step in `regression.yml` now fails the job when a pull request changes
  files under `flavors/github-copilot/.github/hooks/` and its body does not
  contain `local-check: test-hooks-integration.ps1`. The error message names
  the exact line to add. Pull requests touching nothing under that directory
  are unaffected.

  **This is attestation, not verification.** It records that someone states
  they ran the suite; it cannot prove they did, and it may never be cited as
  evidence that the hooks were tested. It is worth having because the failure
  it prevents is forgetting, not lying — and forgetting is the failure that
  actually occurred.

  Two details are load-bearing. The body is read from the API rather than the
  event payload, because a re-run replays the original payload and would still
  see the body as it was when the run started — adding the marker would never
  clear the check. And HTML comments are stripped before the search, because
  `.github/pull_request_template.md` carries the marker commented out: a
  template nobody edited must not satisfy a check about work somebody did.
  Both `gh api` calls fail the step on a non-zero exit rather than falling
  through to a pass, so the step cannot report green about a question it never
  got an answer to. Refs #145.

### Changed

- **Sharding the regression suites across parallel jobs: rejected.** Recorded
  as a decision rather than left open. The full sweep measures 5 min 59 s on
  the runner, of which `test-deploy-flags.ps1` (331 s locally) and
  `test-hooks.ps1` (299 s locally) dominate, and most pull requests touch
  neither. A path-based case distinction would save roughly three minutes.

  It cannot be built as "skip the job for these paths", because a required
  check that does not run does not fail — it stays pending and stops
  asserting. The only sound shape is one job that always runs and decides
  internally which suites to execute, with the full sweep retained on
  `push: dev` as the backstop. Three minutes does not justify machinery whose
  failure mode is a gate that quietly covers less than it claims. Refs #145.

## [1.22.0] -- 2026-08-19

### Added

- **The merge nobody was there to arm.** `gh-pr-manager` can open a pull
  request and cannot finish, because GitHub's auto-merge is opt-in per pull
  request and the MCP server exposes no tool for arming it. PR #149 was the
  demonstration: `conclusion: success`, `mergeable_state: "clean"`, and it
  waited for a human click. Every condition the gate exists to check was met
  and nothing happened.

  `.github/workflows/arm-auto-merge.yml` arms it. This does not weaken the
  gate — auto-merge waits for the required status check, so a red or pending
  check still never merges; the workflow only presses the button. It uses
  `pull_request` rather than `pull_request_target`, because the latter runs
  with the base branch's token and would hand write permissions to code from a
  fork, and this repository is public. Three further conditions gate the job:
  same repository, author is the repository owner, base is `dev`. The base is
  filtered twice, in the trigger and in the job, so that widening one does not
  silently widen the other — the same allowlist reasoning as `gh-pr-manager`,
  and `main` is never armed because merging into the default branch is where
  `Closes #N` fires.

  A failure to arm fails the job deliberately. Arming quietly would leave a
  pull request waiting forever for something nobody is doing, which is the
  failure shape of #125 and #98 rather than a lesser version of it.

  One documented cost: work performed with `GITHUB_TOKEN` does not trigger
  further workflow runs, so a merge armed by this token may not produce the
  post-merge sweep on `dev`. The pull-request run is unaffected and is the one
  the ruleset requires. Stated here rather than found later.

  The merge does not clean up after itself, and cannot: `--delete-branch` is
  inert with `--auto`, because `gh` returns once auto-merge is armed and the
  merge happens minutes later inside GitHub. `prune-merged-branches.yml` does
  it on a schedule instead. Closes #150.

- **An agent may now open a GitHub pull request, and cannot merge the one
  branch where merging would close issues.** The merge gate from #143 made
  `dev` and `main` enforceable, but no agent could open a pull request against
  them: `ado-pr-manager` speaks only Azure DevOps, and the coordinator's
  integration path had no GitHub equivalent. `gh-pr-manager` fills that gap,
  gated by `GH_PR_CAPABILITY_MODE` and defaulting to `off`.

  It is not a port of `ado-pr-manager`, because the assumption underneath that
  agent does not hold here. Azure DevOps has autocomplete — set a flag, and the
  platform merges later once policies pass. **The GitHub MCP server exposes no
  such tool.** The only merge tool attempts the merge immediately, and the
  ruleset refuses it while a required check is unfinished. So a refusal is a
  normal outcome rather than an error, and the agent reports
  `NEEDS_CHECK_COMPLETION` and returns instead of polling — one attempt per
  invocation, no waiting, no burning context on information a later invocation
  gets for free. That status is deliberately distinct from `NEEDS_HUMAN_MERGE`:
  the first means the work is fine and the platform is still deciding, the
  second means no agent may decide at all, and a coordinator that confuses them
  either waits forever or re-invokes against a branch it may not touch.

  Which branch it may merge is an **allowlist** (`GH_PR_AUTOMERGE_BRANCHES`,
  default `dev`), not a denylist. A denylist fails open, and the branch most
  likely to be missing from it is a release branch created next month. The
  default branch is refused even when explicitly listed, because GitHub honours
  `Closes #123` only on a merge into the default branch — measured on issue
  #143, where a pull request into `dev` carrying that keyword left
  `closed_by_pull_requests` at `total_count: 0`. That coupling is what makes
  "this worker never closes an issue" a property rather than an intention, and
  it is the GitHub analogue of `ado-pr-manager`'s mandatory
  `transitionWorkItems: false`. Closing an issue requires someone to have read
  its acceptance criteria, which is not a judgment this agent makes.

  The agent file states what configuration cannot enforce: `Allow auto-merge`
  is repository-wide with no per-branch form, and a single maintainer cannot
  require an approving review on the default branch without deadlocking it,
  since GitHub forbids approving your own pull request. The human-only boundary
  therefore rests on this policy, not on the platform — and the agent says so
  in its return rather than implying a guarantee it does not have. Closes #146.

### Changed

- **Branch cleanup stopped depending on the merge event, because three
  mechanisms that depend on it all fail here.** Automated merges left their
  head branch on the remote every time: #151, #152 and #155, the last still
  present 27 minutes afterwards. *Settings → Automatically delete head
  branches* was enabled throughout, and toggled off and on again in between.

  `gh pr merge --delete-branch` cannot help — `gh` returns as soon as
  auto-merge is armed, so the client-side deletion never runs, and the flag
  reported success while doing nothing. A `pull_request: closed` cleanup
  workflow cannot help either: work performed with `GITHUB_TOKEN` triggers no
  further workflow runs, the same rule that produced the problem.

  What the three share is the merge event. `prune-merged-branches.yml` uses
  `schedule:` instead, so who merged and how stops mattering. It deletes an
  `agent/` branch only when `dev` already contains every one of its commits,
  which is true once its pull request has merged and false while work is
  outstanding — so an abandoned branch with unmerged commits is left alone, and
  a branch abandoned *after* merging is finally cleaned up, which the
  repository setting never covered.

  The cause of GitHub's own deletion not firing is not established, and this
  does not depend on establishing it. That is the point: `--delete-branch` was
  a fix written against an unverified diagnosis and cost a pull request to
  learn nothing.

  **It is inert until the release.** `schedule` and `workflow_dispatch` trigger
  only from the default branch. This file lives on `dev`, and `main` has no
  `.github/workflows` directory at all while sitting 233 commits behind — so
  there is no nightly run, no Run workflow button, and the workflow is not even
  listed in the Actions tab, which is how this was caught. Recorded in the file
  itself rather than left as a surprise. #153 stays open until a run is observed
  deleting something. Refs #153.

- **A green check on `dev` now describes the branch you are actually merging
  into.** Arming auto-merge (#150) removed a guarantee nobody had written down.
  `dev` had two independent signals: the pull-request run, testing the merge
  result before it lands, and `Regression Suites` on `push: [dev]`, testing
  `dev` as it ends up. The second is gone for automated merges, because work
  performed with `GITHUB_TOKEN` does not trigger further workflow runs —
  measured, not assumed: the human merge of #149 produced
  `Regression Suites #6: Commit b6459c4 pushed by sefalk`, and the bot merge
  that produced `42b78d0` produced no run at all.

  On its own that is survivable, since the pull-request run already tests the
  merge commit. It stopped being survivable in combination with
  `strict_required_status_checks_policy: false`, which let a pull request merge
  on a check measured against a base that had since moved. Two pull requests
  opened against the same commit, both green, one merges — and the second lands
  on a `dev` that no run has ever seen. Only hand-serialised merges kept that
  from firing.

  `dev-branch-ruleset.json` now sets the policy to `true`, which makes the
  failure unreachable rather than detected afterwards: a pull request whose
  base has moved must take the new base and re-run before it can merge, and the
  `synchronize` event that follows is already known to produce a run. The cost
  is that auto-merge stalls if nothing updates the branch — visible, and
  preferable to a gate reporting green about a state that was never built.

  `main` keeps `false`. It moves only on release pull requests that a human
  merges, so there is no concurrency for a check to be stale against.
  Closes #154.

- **The context budget has two owners now, so it stops failing on arrival.**
  One ceiling covered the framework's instruction files and the consuming
  project's together. The framework's own always-on files spend 3,461 tokens of
  it, which left the project 1,489 to describe itself in — and AF's own
  `copilot-instructions.md` template invites about 2,000. Issue #107 measured a
  fresh consumer failing all three budgets on the day it was deployed, before
  anyone had drifted anywhere.

  A gate that fails on arrival has two available responses, and both destroy
  it. Raise the numbers until it passes, and a drift detector becomes a rubber
  stamp whose passing verdict carries no information — the same failure shape
  as #98 and #27. Or shrink the project's own self-description to fit the
  framework's leftovers, which is what the consumer in question actually did:
  its `copilot-instructions.md` went from 2,051 tokens to 1,405, a 31% cut to
  the file that tells every agent what the project *is*. It passes today with
  84 tokens of headroom.

  So the ceilings are split by author. `AF_CONTEXT_BUDGET_TOKENS`,
  `AF_CONDITIONAL_BUDGET_TOKENS` and `AF_AGENT_CONTEXT_BUDGET_TOKENS` now cover
  only what the framework ships and controls, and were **tightened** to match:
  4,950 → 3,500, 5,500 → 3,850, 10,900 → 9,450, each the measured framework
  share plus the headroom it already carried. The project's files are charged
  to two new keys, `AF_PROJECT_CONTEXT_BUDGET_TOKENS` and
  `AF_PROJECT_CONDITIONAL_BUDGET_TOKENS`, seeded from what the project actually
  has — so the gate detects drift from the project's own baseline instead of
  from a number the framework invented for someone else's repository.

  Ownership is not guessed. `[customizable]` in `.af-manifest` marks the files
  AF ships as templates and invites the project to rewrite; `.af-hashes` shows
  what AF deployed at all, which is how a project's own instruction file is
  told apart from AF's in the same directory. Checked against a real consumer,
  the annotation is exactly accurate: only the customizable files had diverged,
  the rest were byte-identical. Without `.af-manifest` the check is **BLOCKED**,
  not passed — charging the wrong share to the wrong owner is how this defect
  started.

  Per-agent totals no longer include the project's always-on set. An agent that
  fits must not stop fitting because the consuming project wrote itself a
  longer overview. The real total is still printed as the worst case.

  `deploy.ps1` and `deploy.sh` seed the project ceilings on a **fresh** install
  only — on an update `af-env.conf` is a baseline somebody chose, and
  overwriting it would erase the drift the ceiling exists to detect. Where no
  Python is available deploy says so and names the command. Existing consumers
  never receive the keys at all (`af-env.conf` is protected on update); until
  they are seeded the project share is measured, printed as `UNBUDGETED` and
  left ungated, because a project that never stated a baseline has not drifted
  from one.

- **The token divisor is a measurement now, not a rule of thumb.**
  `check-context-budget.py` estimates tokens as `characters / 4`, and the code
  said outright that the 4 "has not been calibrated against a tokenizer for
  this payload". Issue #59 expected that to be wrong in the unsafe direction:
  dense markdown was thought to run 3–3.5 characters per token, which would
  mean every budget understated real consumption by 15–30%.

  It was measured, against all 24 files the gate covers, with tiktoken
  `o200k_base` cross-checked against `cl100k_base`:

  ```
  183,317 chars → 44,602 real tokens = 4.110 chars/token
  per file 3.83 – 4.29 (median 4.111)
  ```

  **The suspicion was wrong.** `characters/4` lands within −4.2%/+7.2% per file
  (+2.8% median) and it errs *high* — it reports slightly more tokens than
  exist, which is the safe direction for a ceiling. By group: always-on +3.6%,
  conditional +1.7%, agents +2.8%.

  So the constant does not move and the **budgets are not restated**. Changing
  4 to 4.11 would shift every figure by under 3% — inside the noise this gate
  exists to ignore — and would relax all three ceilings for no gain. What
  changes is the justification: the calibration date, the tokenizers, the
  ratio, the per-file band and the direction of the error are now recorded
  beside the constant and beside the budgets in `af-env.conf`, where somebody
  deciding whether to raise a ceiling will actually be looking.

### Added

- **The fifteen regression suites ran only on a maintainer's laptop, so GitHub
  had no way to tell a sound pull request from a broken one.** There was no
  `.github/workflows` directory and no `.github` directory at the repository
  root at all; `dev` and `main` both reported `"protected": false` with an
  empty `required_status_checks.contexts`. Every suite result reached the
  project as a claim in a chat transcript and nothing else, which is why the
  question "may this pull request merge automatically once all conditions are
  met" had no answer: there were no conditions, so a pull request was mergeable
  the instant it was opened.

  Two things had to be settled before a workflow could mean anything. Ten of
  the fifteen suites end their preflight with `Write-Host 'SKIP: ...'` followed
  by `exit 0` when Python, ruff or PyYAML is missing — correct on a developer
  machine, and on a bare runner a green gate that asserted nothing, the same
  shape as #125. And `test-hooks-integration.ps1` does not test the payload at
  all: it reads VS Code's own hook log under `%APPDATA%\Code\logs` to confirm
  hooks fired during a real session, so on a hosted runner it exits 2.

  So `scripts/run-all-tests.ps1` gives the suites the single entry point and
  single exit code a CI job needs, and classifies each one as PASS, SKIP,
  BLOCKED or TIMEOUT by reading its output rather than trusting its exit code.
  Under `-FailOnSkip`, which the workflow passes, a suite that asserted nothing
  fails the run. `.github/workflows/regression.yml` runs it on `windows-latest`
  — not a preference, since the suites are Windows PowerShell 5.1 scripts and
  hosted Linux runners have no `powershell` — installs the prerequisites, and
  configures a git identity, because several suites commit inside throwaway
  repositories and a fresh runner has none. `test-hooks-integration.ps1` is
  excluded explicitly, with the reason stated at the exclusion.

  Baseline on the maintainer machine: 15 passed, 0 skipped, 0 failed, 956
  seconds. This is a prerequisite, not the feature — branch protection,
  auto-merge, automatic head-branch deletion and automatic issue closing remain
  separate decisions, and each of them is only safe once this check exists and
  is trusted. Closes #143.

- **The plan was written three times before it reached disk, because the agent
  that produced it was forbidden to save it.** The planner returned the plan,
  the coordinator repeated it verbatim inside a delegation prompt, and the
  documenter emitted it a third time as the argument to `createFile`. All three
  are output emissions — `createFile` takes the file body as an argument, so
  persisting is not free either. Measured over the 66 plans in this framework
  and one consuming project, the plan is a median 1,747 tokens when it first
  lands (mean 2,951, max 8,410, 194,793 in total), so the two redundant passes
  cost a median 3,494 and a mean 5,902 output tokens per workflow — roughly
  390,000 across the corpus, for text that already existed.

  The cause was a least-privilege rule applied by agent rather than by path:
  the planner was read-only, so the only way to disk ran through an agent that
  had no reason to read the document. The planner now holds `edit/createFile`
  and writes its own plan, confined by a new `planner-pretooluse` hook to `.md`
  files under a `plans/` directory. The hook is an allowlist, not a denylist
  like `test-writer-pretooluse`: the planner's legitimate write surface is one
  directory, so everything outside it is refused by default rather than
  enumerated. Path traversal, absolute paths, non-`.md` payloads smuggled into
  the plan directory, one bad path hidden in a batch of good ones, and pathless
  writes are all denied — asserted by 20 cases in
  `scripts/test-planner-write-scope.ps1`, of which 14 are attempts to escape.

  The coordinator reads the plan file for its § 4 review gate instead of
  reviewing a copy in its context, and the same change removes the same relay
  from the Quick Fix investigation document. Critics and the arbiter remain
  read-only; the planner still edits no code. Closes #130.

- **The workflow log had a schema and no reader, so 16 of 55 logs speak a
  language the framework does not.** `documenter.agent.md` has always given the
  log a vocabulary — `status` is COMPLETED, FAILED or ESCALATED; a step verdict
  is one of the five in MANIFEST § 13 — and nothing has ever read a log back
  against it. Measured across the 55 logs in a consuming project: two are not
  valid YAML at all, six carry verdicts from outside the set (`PASS`, `SKIPPED`,
  `SUBMITTED_FOR_REVIEW`, `PROCEEDED`, `PASSED`), and six carry statuses from
  outside it (`DRAFT`, `IN_PROGRESS`, `IN-PROGRESS`, one a whole sentence). A
  schema nobody enforces records an intention; the corpus records the habit.

  `check-workflow-log.py` runs from the documenter's Stop hook and **blocks** on
  vocabulary, because vocabulary is a choice the documenter can correct. It is
  stdlib-only for the scan and reaches for PyYAML only to answer "does this
  parse", declaring the rule unrun rather than passing it when the library is
  absent. A block scalar's body is skipped, so a `description: |` that quotes
  `verdict: "PROCEEDED"` cannot invent a violation out of prose.

  `summary.retries` and `summary.escalations` are handled the other way: they
  are **derived from the steps and stamped by the hook**, and the documenter is
  told to write `0`. In the same corpus, 25 of 53 readable summaries contradict
  their own steps — 23 retries self-reported against 63 counted. That is not
  dishonesty and not a rule violation, it is a model doing arithmetic over a
  list at the end of a long context, and the fix for a number a model can get
  wrong is not to validate the number, it is to stop asking for it. Issue #91
  established the precedent with `completed:`, where a documenter wrote a
  timestamp six hours in the future in the same output that declared zero
  fabricated data. The derivation uses the same definition of a retry as
  `analyze-retry-economy.py`, verified against the corpus, so the two tools
  cannot disagree about what they are counting.

  The mechanism was corrected before it was built. The issue proposed a
  pre-commit guard over staged logs; `.github/logs/.gitignore` ignores `*`, so
  such a guard could never have fired once. It would have been the #125 failure
  mode — a check that passes because it never runs — proposed by an agent that
  had read #125. `ALLOW_WORKFLOW_LOG_SCHEMA=1` stands the gate down for a human
  who disagrees with it, and still prints what it found. 26 regression tests in
  `test-workflow-log-schema.ps1`. Closes #137.

- **The retry budget was set per agent without ever counting a retry.**
  MANIFEST § 4 gives every agent the same two attempts before escalation, and
  that number has never been checked against a workflow. `analyze-retry-economy.py`
  reads the `.github/logs/*.yaml` the documenter already writes and answers the
  question the budget assumes: who actually retries, how often, and why.

  Issue #43 named `transcripts/*.jsonl` as the source. They were measured first
  and rejected: 143 MB across four workspace-storage directories, uncommitted,
  machine-local, and a retry only inferrable from the shape of a `runSubagent`
  call. The workflow logs are the framework's own record, they are versioned
  with the project, and a retry is visible in them structurally — the same
  agent appearing twice in one `steps` list.

  Against a 55-log corpus the tool reports what the flat budget hides. The
  implementer runs 75 times and retries 33 of them, 0.44 per step, in 43% of
  the workflows it appears in; the refactorer and the compliance-checker never
  retry at all. Two agents carry the retry cost and the rest pay the same
  allowance. The distribution matters more than the mean: 27 of 53 workflows
  have no retry whatsoever, and one has six — an average of 1.2 retries per
  workflow describes neither.

  Causes are attributed from the steps in between, and the tool states its
  heuristic in the output before it prints a number. A `REJECTED` or `ESCALATE`
  verdict in between is `critic-rejected`; a step below its hard-gate count is
  `gate-failed`; nothing in between at all is `consecutive-pass`. Tool errors,
  the third cause the issue asks for, are not derivable from these logs — no
  step records them — so the tool says the column is missing rather than
  printing zero. The largest single finding is that 19 of the implementer's 33
  retries are `consecutive-pass`: the most expensive agent's most common repeat
  is a second run with no reviewer between the two.

  The tool refuses to be quiet about its own blind spots, per the #12 lesson.
  An empty or missing log directory exits 2 — a framework with no evidence is
  not a framework with no retries. A corpus where nothing parses exits 2. Any
  log that fails to parse is named and excluded, and the count of what was
  excluded is printed next to the count of what was read.

  Reading the record exposed the record. In the corpus, 25 of 53 workflows have
  a `summary` that contradicts their own `steps` — self-reported retries total
  23 against 63 counted structurally, and `summary.escalations` is 0 in all 55
  logs while a step verdict says `ESCALATE` once. Six verdicts fall outside the
  MANIFEST closed set (`PASS`, `PASSED`, `SKIPPED`, `PROCEEDED`,
  `SUBMITTED_FOR_REVIEW`, `APPROVED-WITH-ISSUES`). Two logs are not valid YAML
  at all. Nothing had ever read them, so nothing had ever noticed. The tool
  reports all three as drift and exits 1; fixing the record is a separate
  problem from being able to read it.

  `test-retry-economy.ps1` adds 20 checks over synthetic corpora, each proving
  one claim by constructing the log that would break it — the empty directory,
  the unparsable log, the lying summary, the verdict outside the set.
  Closes #43.


  Two layers now stand where the count stood, and neither is a new agent.

  `check-plan-structure.py` runs in the existing pre-commit shim, over the same
  scope as the budget guard, and blocks a staged plan that has fields left as
  template placeholders, headings the templates do not define, a subtask
  without acceptance criteria, files, or an exit criterion, an unstated
  complexity tier, or no subtasks at all. Both document kinds in the plans
  directory are recognised: `PLAN.md` and `INVESTIGATION.md` are checked
  against their own section sets, chosen by the title, so an investigation is
  not rejected for lacking subtasks it was never supposed to have. `DRAFT`
  stands the guard down — and is named in the output, so DRAFT cannot quietly
  become the way out. Override: `ALLOW_PLAN_STRUCTURE=1`.

  What it deliberately does not do is reject a Standard plan for containing a
  section the template reserves for Deep. Length is already paid for by the
  budget guard, and a rule that punished thoroughness would be teaching authors
  to write less than they know.

  It also cannot judge whether an acceptance criterion is *useful*, which is why
  the second layer is a question and not a regex. The coordinator's gate in
  `tdd-orchestration` § 4 now asks five things about the plan already in its
  context — are the criteria decidable, does every subtask name files and an
  exit criterion, is the tier justified against the layer-override rule rather
  than asserted, can the subtasks be executed in the order given, is anything
  in the plan untraceable to the request. A "no" returns the plan to the
  planner once; the second failure escalates. The escalation triggers are
  unchanged; this adds the reasons, it does not replace them.

  The coordinator commissioned the plan, so those answers are a self-check, and
  a self-check nobody reads stops happening. They are persisted as
  `plan_review` in the workflow log and the compliance-checker's post-flight
  bookend — already independent, already reading workflow artifacts — reports
  their absence. An absent block means the gate was skipped, not passed.

  Measured against the framework's own 34 plan documents, exactly one passes.
  The other 33 predate the template that #26 tightened, and they are not
  rewritten: the guard reads the staged blob, so it judges what is written from
  here on. But the ratio is the finding. A template that nothing enforced was
  followed by one document in thirty-four, and every one of those was written
  by an agent instructed to follow it.

  Guard: `.github/hooks/scripts/check-plan-structure.py`
  Regression suite: `.github/scripts/test-plan-structure.ps1` (25 checks).
  Whether a dedicated plan-critic is needed on top of this is deliberately not
  decided here — issue #133 holds it until the retry cost it would prevent has
  been measured. Closes #132.

- **Plan documents are budgeted by complexity tier, and the budget is checked
  on commit.** The plan is the largest artifact a workflow writes and the one
  nobody re-reads. Measured across 29 plans in a consuming project (768 KB):
  Standard tier averaged 20,555 characters — about 5,100 tokens — and Deep
  averaged 9,710 tokens, with the largest single plan at 87,696 characters.

  The obvious remedy was to cut narrative sections out of the template. The
  measurement says that would not have worked: the template is 4 KB, so it is
  not the scaffolding that is expensive, and **45% of Standard-plan text sat in
  sections the template never defines** — invented per plan, one at a time.
  Deleting every droppable template section would have left the average at
  ~3,900 tokens, still above the 3,000 the issue asked for. A template cannot
  hold a limit, because nothing in a template says *and no more than this*.

  So the limit is a number, in `af-env.conf`, enforced by a new pre-commit
  guard against the staged blob:

  ```conf
  PLAN_BUDGET_TRIVIAL_TOKENS=0
  PLAN_BUDGET_STANDARD_TOKENS=3000
  PLAN_BUDGET_DEEP_TOKENS=12000
  ```

  - **Trivial is zero** because a Trivial fix is chartered to have no plan file.
    That rule already existed; nothing enforced it, so nothing could tell
    whether it held.
  - **Deep is generous on purpose.** It leaves the average Deep plan untouched
    and exists for the tail — the 87 KB plan no reviewer read.
  - **An unstated tier is charged Standard.** Silence is not a licence for an
    unbounded document. The template's own `<!-- Trivial / Standard / Deep -->`
    placeholder is a comment and states nothing, which the guard asserts
    directly rather than assuming.

  The template and the planner now say the same thing in words: sections marked
  `[Deep]` are omitted at Standard, subtask fields are one line each (subtasks
  are the largest named section at ~6,600 characters), and no section outside
  the template. The planner's return format stopped restating the whole template
  and now references it — two copies of one structure had already drifted.

  Also documented, because it was never written down: the plan text is emitted
  **three times** before it reaches disk — the planner returns it, the
  coordinator repeats it verbatim in the documenter's delegation prompt, and the
  documenter writes the file. That is the price of the planner being read-only,
  charged per workflow at the full size of the plan, and it means a plan kept
  inside its budget is worth roughly three times its own size.

  Guard: `.github/hooks/scripts/check-plan-budget.py`
  (override `ALLOW_PLAN_BUDGET=1`). Regression suite:
  `.github/scripts/test-plan-budget.ps1`, 18 checks.

  Closes #26.

- **`check-context-budget.py --verify-tokenizer`.** A measured constant that
  nobody can re-derive decays back into folklore the moment the payload's
  character mix drifts. The flag re-runs the calibration and prints per-file
  and aggregate drift against the divisor in use.

  It imports tiktoken lazily, inside the handler, so the gate itself acquires
  no third-party dependency — asserted on the source, because an import test
  passes for the wrong reason on a host that has the package. It exits 1 when
  the aggregate error exceeds 10%, since these figures are quoted to humans as
  "tokens" in plans and pull requests. Without tiktoken it exits **2
  (BLOCKED)**, not 0: a verification that could not run is an unknown result,
  and "calibration fine" reported on the strength of a missing import is the
  failure this framework keeps closing.

  The regression case runs it against the **real** payload rather than a
  fixture, which makes the calibration itself a live gate: if the character
  mix ever drifts past 10%, the suite goes red. A synthetic fixture cannot do
  this job — fixture text is a run of filler characters, which BPE collapses to
  a handful of tokens, so it measures the fixture generator and fails a correct
  divisor.

  Known limitation, stated rather than buried: tiktoken is an OpenAI tokenizer,
  and this payload is consumed by Claude, whose BPE is not available here. The
  agreement between the two OpenAI vocabularies suggests the ratio is robust
  for English markdown, but that is an inference, not a measurement of the
  tokenizer that bills.

- **The retro destination is now a project decision (`RETRO_DIR`).** Agent
  retros were classed with the workflow logs and gitignored on that basis.
  The classification was checked and does not hold.

  `retros/README.md` justified the exclusion by saying the two are "the same
  class of artifact", and `documenter.agent.md` gave the operative reason:
  *the log embeds the user request verbatim*. That is a property of the **log**.
  Measured on a real 55-file consumer corpus, the agent retros contained zero
  credential values, zero personal or absolute paths and zero URLs — the three
  `secret` hits all named the Databricks Secrets API and secret *names*. The
  56 workflow logs, by contrast, carry a verbatim `trigger:` in 55 of them
  (40–420 characters, averaging 104). One of the two is unsafe to publish, and
  it is not the retro.

  So the destination becomes configurable while the **default does not move**:

  ```conf
  RETRO_DIR=.github/retros/auto
  ```

  A consumer that upgrades without touching `af-env.conf` observes byte-for-byte
  the behaviour it had before the key existed — asserted directly, in both
  dialects, rather than assumed. Point it at a tracked directory such as
  `docs/retros` and retros become reviewable project history that survives a
  fresh clone.

  What does **not** become configurable:

  - **There is still exactly one destination.** The gates resolve the same key
    the documenter writes to, so a retro in the wrong place is still detected
    rather than tolerated — the property #98 established, now derived from
    config instead of a literal. The override cases assert the inverse too: with
    `RETRO_DIR` pointed elsewhere, the old path stops satisfying the gate. A key
    that only ever *added* an acceptable location would have re-created the
    ambiguity it was meant to preserve against.
  - **The logs stay local, unconditionally.** The verbatim-request argument is
    true of them.

  Resolution lives in one function per dialect (`Get-AfRetroDir`,
  `af_retro_dir`), because a key honoured by `.ps1` and ignored by `.sh` is a
  gate whose verdict depends on who ran it — the shape #93 lived in for weeks.
  Both normalise trailing slashes and backslashes, and both fall back to the
  default on an empty value rather than treating `''` as the repository root,
  which would have made every retro satisfy the gate.

  Revises the reasoning shipped with #98/#27, and is the constructive half of
  #109: a migration that moves records into a gitignored directory is only safe
  once the directory does not have to be gitignored.

  Closes #117.

### Fixed

- **The context budget guard was inert wherever `.github/` was gitignored, and
  inert looked exactly like passing.** The guard measures the *staged* payload,
  which is the right scope: it is why an ordinary commit pays nothing. But a
  project that blanket-ignores `.github/` can never stage a budget input, so
  the guard was installed, wired, dispatched on every commit — and structurally
  unable to fire. It emitted nothing. Nothing is also what a passing guard
  emits, so for months the absence of complaints read as consent. When the
  payload was finally tracked, the guard's first run reported three
  simultaneous breaches (always-on 562 over, conditional 161 over, coordinator
  636 over) that no single commit had introduced.

  The guard now distinguishes *"this commit stages no budget input"* — the
  ordinary case, still silent, because whatever it would measure was already
  measured when it was committed — from *"git holds no budget input at all"*,
  which is not that case: there was no such commit and there cannot be one.
  In the second case it prints `NOT GATED`, names how many files it can see on
  disk but not in git, says whether a gitignore rule is the cause, and gives
  the command that measures them by hand.

  Partial tracking gets the same treatment, because it is the same defect
  wearing a passing verdict: half an unignored `.github/` is not half a gate,
  it is a gate that measures a subset and reports it as the total. Untracked
  budget inputs are listed as `PARTIALLY GATED` when nothing is staged, and on
  a payload commit the measurement is labelled a floor rather than a total.

  Where the index is blind, the reading is taken from disk. Copilot loads
  instruction files from the working tree; whether git holds them changes
  nothing about what they cost, so the index is the right basis for a *verdict*
  — it is what the commit is made of — and the wrong basis for a *number*. The
  blind-spot report therefore carries an actual measurement, marked advisory.
  Measuring the working tree on *every* commit was considered and declined: it
  would report breaches the committer did not stage and cannot act on, and a
  repository whose payload is fully tracked would pay for a second reading that
  can only repeat the first. The measurement runs exactly where the index
  cannot answer.

  Blindness is reported, never blocked. An exit code is a statement about the
  commit in front of the guard; untracked files are a statement about the
  repository. Charging one to the other would make an unrelated commit pay for
  a configuration defect, and would leave a project that deliberately keeps its
  payload local no way forward except disabling the guard entirely.

  Closes #125.

- **Two gate scripts decoded git and ruff output with the platform default
  encoding.** On a German Windows host that default is `cp1252`, so a valid
  UTF-8 byte sequence containing `0x81` — Cyrillic `Ё` in a commit subject, for
  instance — raised `UnicodeDecodeError`. The exception is raised inside
  `subprocess`'s reader thread, so it never reaches the caller: `subprocess.run`
  returns `returncode=0` with `stdout=None`. Git *succeeded*; the script simply
  never learned what it said.

  The two consumers in `check-python-quality.py` fail differently, and the
  second is the reason this is filed as a defect rather than a nuisance:

  - `_changed_line_ranges` guards with `if code != 0`, which is false, then
    calls `out.splitlines()` on `None` → `AttributeError`, loud and visible.
  - `_read_base_source` guards with `if code != 0`, which is false, then
    returns `None` — and `None` is that function's documented value for *"the
    base has no such blob"*. A failed read is indistinguishable from a file
    that did not exist before, so the gate silently loses its comparison
    baseline and reports on a premise that is not true.

  `check-python-linting.py` had the same call shape around `ruff`, where a
  decode failure surfaces as `LINTING_GATE_ERROR: failed to run ruff` — an
  encoding bug wearing a tooling bug's label. Both now pass
  `encoding="utf-8", errors="replace"`; a gate must not crash on, or quietly
  misread, the content it exists to inspect. Most sibling scripts already
  decoded explicitly, so this closes an incomplete rollout rather than
  introducing a convention.

### Changed

- **The provider registry is no longer always-on (issue #115).** Five provider
  workers exist against eleven core agents, which looked like agent
  proliferation. Measurement said otherwise: agent files load on demand, so a
  sixth worker costs nothing for any workflow that does not invoke it. What did
  cost was the *registry* — 511 tokens of `coordinator.agent.md` documenting
  capabilities whose shipped defaults are all `off`, paid on every turn of every
  workflow, including pure-git projects where none of them will ever fire.

  Twenty-three of those lines duplicated `ado-shared` §§ 180–267 — the same
  section the coordinator was being told to go and read. Five delegation rows
  became one; the duplicated sequences became a pointer. The integration-path
  rule stayed inline, because it is mandatory for *every* workflow including
  pure git, and a mandatory rule moved into an on-demand skill is a rule that
  can silently fail to load. Coordinator own prompt 6,011 → 5,765 tok; headroom
  against the agent budget 24 → 270.

  Two alternatives were measured and rejected. A provider *manager* with
  subagents saves ~135 always-on tokens and costs ~6,400 per provider operation
  for the extra invocation — and adds a delegation hop, where acceptance
  criteria that must be copied verbatim can quietly stop being. One agent per
  provider with capabilities selected by skill fails harder: tool grants are
  static and per-agent, so the union of the four ADO workers (36 grants) would
  put `pipelines_write` and `repo_pull_request_write` in scope for a wiki edit —
  the exact over-grant #113 had just removed — and the four workers' mandatory
  guards would have to move into on-demand skills to fit the budget.

### Added

- **A consumer can report a framework defect without being granted the tools to
  do it (issue #113).** Filing #104–#112 from a consumer project required
  hand-editing 22 `github/*` MCP grants into that project's
  `coordinator.agent.md` — a local divergence in an AF-owned file, reported as a
  conflict by every subsequent deploy, with a grant list that drifts unreviewed.
  The name for the fix already existed: `quality-gates.instructions.md` lists
  `gh-issue-manager` in its provider-worker table. Only the worker was missing.

  `gh-issue-manager` follows the `ado-*` pattern — MCP only, no git, no
  terminal — and carries an issue-lifecycle tool set rather than the general
  repository surface the ad-hoc grant had accumulated. Two routes share it:
  `project` for the project's own tracker (`GH_CAPABILITY_MODE`, `GH_OWNER`,
  `GH_REPOSITORY`) and `upstream` for defects in the framework itself
  (`AF_UPSTREAM_REPORTING`, `AF_UPSTREAM_REPO`). The gates are independent on
  purpose: a project tracking work items in Azure DevOps previously had no path
  to report a framework defect at all, short of a human copying text between two
  systems.

  Two properties matter more than the plumbing. When the gate is `off` — the
  default — the worker still returns the drafted issue body, because suppressing
  the write must not suppress the finding; a defect noticed and never recorded is
  indistinguishable from a defect never noticed. And an upstream report is
  verified against the framework *source* before it is filed, not against the
  consumer's deployed copy, since a deployed copy may carry local modifications
  and a defect observed there may be a divergence the consumer introduced. The
  coordinator holds no `github/*` tools; it delegates.

### Fixed

- **The retro has one destination, and is owed only when the run had something
  to teach (issues #98, #27).** The destination contradiction #98 reported was
  already gone from the source — every agent file names
  `.github/retros/auto/`. What survived was the gate underneath: both hooks
  accepted the retro at the canonical path *or* at the legacy root path. That
  does not resolve an ambiguity, it preserves it — a documenter writing to the
  wrong place was indistinguishable from one writing to the right place, and
  the file it left behind sat outside the `.gitignore` that exists to keep
  generated retros out of the repository. The legacy path is no longer
  accepted, and a file found there is named in the block message rather than
  ignored: silent rejection is as unhelpful as silent acceptance when the only
  person who can move the file has to be told where it is.

  The second half is #27. Every workflow was made to write a retro, including
  runs with nothing to report, so the corpus filled with files recording that
  nothing happened — and `/af-retro-summary` reads them back as input. A retro
  is now owed only when the workflow log records retries, escalations, an
  adverse step verdict, or a status other than COMPLETED.

  The condition is derived by the hook from the log, never declared by the
  documenter: "it was clean, so I skipped it" is the self-report channel #91
  closed for timestamps, and it would be reopened here for a strictly larger
  prize. The default is REQUIRED, so a log that is missing, empty, or still
  carrying the unfilled `retries: <number>` template licenses nothing —
  absence of evidence is not evidence of a clean run. Every condition matches a
  *field*, because the log quotes the user request verbatim in `trigger:`,
  where "blocked" and "rejected" appear as ordinary prose.

  When the exemption applies, the hook says so (`no retro required (retries 0,
  escalations 0, status COMPLETED, no adverse verdict)`). An exemption applied
  in silence cannot be reviewed, and looks exactly like a gate that was never
  reached.

  `deploy.ps1` now warns when a target has `.github/retros/auto/` without the
  `.gitignore` that belongs next to it — the documenter creates that directory
  at run time, `retros/` is optional in the manifest, and the directory
  existing is not evidence that the ignore came with it. Measured in a consumer
  repo: generated retros staged as if they were authored source.

- **The test log now actually merges on Windows, and a log the runner cannot
  read is announced instead of overwritten (issue #93).** `run-tests.ps1` read
  `.github/test-log.json` with `ConvertFrom-Json -AsHashtable`, a parameter
  that exists only in PowerShell 6+. Windows PowerShell 5.1 is the default host
  for the shipped VS Code tasks, so on Windows the read always threw, a silent
  `catch` reset the accumulator, and the file was rewritten with only the scope
  that had just run. Measured here: a `domain` run followed by a `contracts`
  run left `scopes=[contracts]`. Exit code 0 throughout.

  The lost merge is the symptom. The defect is the `catch`, which converted a
  hard interpreter incompatibility into a plausible-looking artifact — the same
  failure as #73 in the same file, and the same shape as everything else in
  this release: a mechanism that fails silently produces output that cannot be
  distinguished from success. It matters because `testing.instructions.md`
  tells every agent to consult this log before running anything, and acceptance
  criteria are routinely phrased as "green at the same pass count as before".
  An agent establishing that baseline found the other scope missing, with no
  way to tell a regression from a parser it could not run.

  `run-tests.sh` already merged correctly. So this was never a missing feature;
  it was two runners documented as interchangeable disagreeing about what their
  shared artifact means, with nothing asserting that they agree. There is now a
  case that runs both and compares.

  The read no longer uses the parameter at all rather than branching on the
  host version — one path, not two, and not one that would go untested on a
  maintainer's PowerShell 7 machine. An absent log stays silent, because a
  first run is legitimate and a warning on every one of them would be noise. A
  log that exists and will not parse is data loss: it is reported with the
  parser's own message and copied to `test-log.json.unreadable` before being
  replaced, so the evidence outlives the run that tripped over it. A new guard
  scans every shipped `.ps1` for PowerShell 6-only constructs — `-AsHashtable`
  was the only one in the payload, and nothing was stopping the next one.

- **The hook harness no longer certifies what it never observed (issues #95,
  #96).** Two defects in the instrument every quality claim in this framework
  is read through.

  A hook is supposed to make exactly one statement per invocation. Because the
  harness searched its output for the expected answer, a hook that decided
  correctly and then contradicted itself was certified as correct — while a
  last-wins consumer would act on the second statement. Measured, not inferred:
  `run_case` reported `pass` for a deny-then-allow emitter and `stop_case`
  reported `pass` for a block-then-pass one. The issue predicted the same for
  PowerShell; it does not reproduce there, because `ConvertFrom-Json` on 5.1
  happens to throw on two concatenated objects. That is protection by parser
  version, not by design, and it reported the failure as `unparsable` — naming
  the wrong cause. Both harnesses now count top-level JSON values
  (`Get-JsonStatementCount`, `af_json_statements`) and treat more than one as
  its own outcome. A top-level array is still one value; prose printed beside
  the JSON is not a clean statement either. `Get-StopDecision` had its own
  parse path and now routes through a shared `Resolve-StopDecision`, so the
  rule cannot hold in one half of the harness and not the other.

  The second defect: `$null -notmatch '2099'` is `$true`. Every negative
  content assertion passed when the thing it examined was empty, so the
  read-back channel added for #91 could have returned nothing for every case
  while the suite stayed green. The neighbouring assertions were saved by
  accident — `-match` on `$null` is false, and a match count of 0 is not 1 —
  which made "does this assertion survive an empty subject" a coincidence of
  operator choice. `Assert-Contains`/`Assert-NotContains` and
  `assert_contains`/`assert_not_contains` now take the subject itself and fail
  when it is empty; `Assert-True` gained an optional `-Subject` for compound
  conditions. Passing the subject in is the whole point: once the caller has
  collapsed it to a boolean there is nothing left for a guard to inspect.

  Both harnesses now self-check the read-back channel as well as the verdict
  channel, and they do it by asserting that certain assertions *fail* —
  PowerShell by snapshotting the tally around a probe, bash by running the
  probe in a subshell. Suites: `test-hooks.ps1` 213 → 233 checks,
  `test-hooks.sh` 106 → 120, both green. Mutation evidence: breaking the
  read-back turns nine cases red including the `-notmatch` one; disabling the
  statement count turns the contradiction cases red in both harnesses;
  removing the empty-subject guard turns the vacuous cases red.

  The test-critic gained the question this defect answers to: would this
  assertion still pass if the thing under test produced nothing?

- **The context budget is enforced at commit time instead of being asked for
  politely (issue #85).** `check-context-budget.py` could always measure the
  payload; nothing ever asked it to. Its only reference anywhere in the
  repository was a checklist line — one that told the reader to run a Python
  script with `pwsh`, so it had never been executed as written. The result was
  visible on `dev`: the conditional instruction set sat 273 tokens past its own
  ceiling, and `test-context-budget.ps1` case `J_real_payload_within_budget`
  was red for the whole period. A red test in a suite nobody runs is
  indistinguishable from a green one.

  A new pre-commit checker, `check-context-budget-staged.py`, exports the
  staged payload out of the index into a temporary tree and hands it to the
  existing measurement — globs, budgets and `applyTo` semantics keep exactly
  one definition, and what is measured is what would be committed rather than
  whatever happens to be on disk. It runs only when the commit stages
  `copilot-instructions.md`, `instructions/*.md`, `agents/*.agent.md`, or the
  `af-env.conf` that sets the ceiling, so every other commit pays nothing. It
  blocks rather than warns: the budgets carry deliberate headroom, so the
  ceiling is meant to be reached by the change that crosses it, while its
  author still has the context to decide what should have been narrowed or
  moved. One-off escape hatch: `ALLOW_CONTEXT_BUDGET=1 git commit ...`.

  Two things had to be fixed for that guard to reach the repository that needs
  it. The AF source repo's hook path is `.githooks/`, whose `pre-commit` only
  bumped `VERSION`, while the shipped guards resolve themselves under
  `$repo_root/.github` — a directory this repo does not have. The framework's
  own commit guards therefore ran in every consumer project and in none of the
  commits that wrote them. `.githooks/pre-commit` now dispatches the payload
  shim first, so a blocked commit does not leave a bumped `VERSION` staged
  behind it, and the shim resolves its checkers relative to itself instead of
  assuming the deployed layout. The shim's interpreter probe also trusted
  `command -v python`, which on Windows answers with the Microsoft Store alias
  that then refuses to run; a candidate must now report a `--version`. A broken
  interpreter probe is indistinguishable from a payload that is genuinely over
  budget, and it blocked every commit rather than none.

  The checklist line is gone. `copilot-authoring.instructions.md` now points at
  the gate that runs instead of asking a human to remember one.
  `test-context-budget.ps1` grows from 39 to 54 checks covering scoping,
  staged-versus-working-tree, the override, BLOCKED propagation, consumer
  budgets, the nested source-repo layout, and both wiring call sites.

- **Workflow-log timestamps are measured by the Stop hook, not authored by the
  documenter (issue #91).** The log is the only durable record of when a
  workflow ran, and its `started:`/`completed:` fields were filled in by the
  model. Measured: a documenter wrote `completed: "2026-08-07T16:30:00Z"` for a
  workflow that finished at 09:59Z — six and a half hours in the future — and
  `started:` an hour before any commit on the branch, in the same output that
  declared "zero fabricated data". Nothing rejected it. Every gate that looks
  at the log checks the field is *present*, and an invented value is present.

  The fix is the one the `cost:` block already uses: take the numbers out of
  the model's hands rather than validate them afterwards. A range check would
  have caught this particular timestamp and accepted any lie inside the range.
  `documenter-stop` now stamps both fields after its artifact gate passes —
  `completed:` is the moment the hook fires, which is the moment the documenter
  finished, and `started:` is the branch's oldest commit, the same
  approximation the cost collector already uses for `--workflow-start`. Values
  the documenter left behind are replaced rather than joined: two `completed:`
  keys is a YAML file whose meaning depends on which one the parser reaches
  last. A call made while the workflow is still running is not stamped at all,
  because it never reaches the artifact gate.

  Both fields are gone from the log schema in `documenter.agent.md`. Leaving
  them there and arguing against them in prose is what produced the fabrication
  in the first place — the schema is the instruction.

- **Artifact existence is now a filesystem question, not a search result
  (issue #87).** The compliance-checker post-flight verified that the workflow
  log and retro snippet exist by searching for them. Search tools honour
  `.gitignore`, so in any project that gitignores `.github/` — the normal setup
  for a project consuming a deployed payload rather than versioning it — every
  post-flight reported both artifacts MISSING and returned BLOCKED, whatever
  was on disk. Measured in a consumer repo: a 2922-byte workflow log, two hours
  old and independently validated afterwards, reported as missing.

  The fix is a capability removal, not a warning. The invoking prompt had
  already warned the agent that `.github/` was gitignored there and that it had
  to verify on the filesystem; it reached for the ignore-aware tool anyway. The
  compliance-checker therefore no longer holds `search/codebase`,
  `search/textSearch` or `search/fileSearch` at all — it never needed them,
  because every artifact it checks sits at a path derived from the workflow id
  and the changed files are handed to it in the prompt. Opening the file is now
  the existence proof, and a failed read is the absence.

  Every MISSING it reports must name the path it probed. A bare MISSING cannot
  be told apart from a false negative by anyone downstream — and downstream is
  where files get recreated.

  The remediation path is guarded independently of the cause. Step 7b now
  requires the coordinator, which has a terminal the checker deliberately does
  not, to confirm each reported path is genuinely absent before recreating
  anything, and never to overwrite an existing non-empty artifact. This matters
  because the documenter cannot distinguish "write fresh" from "replace
  verified content": applied to a false negative, the documented remediation
  destroyed correct evidence instead of restoring missing evidence. Any future
  false negative is now a no-op.

### Changed

- **The ask tier was scoped to what the framework knows and VS Code does not
  (issue #78a).** Returning `permissionDecision: "ask"` renders our reason
  verbatim and suppresses Copilot's own assessment — the one that categorises
  the command and describes in plain language what it will do. For a generic
  durable change our fixed sentence is simply the worse of the two prompts, and
  emitting it cost the user the better one. Four rules now return `{}` instead:
  `pip install/uninstall`, `conda install/remove`, `ruff format`, and the
  filesystem create/move/copy rule (`New-Item`, `mkdir`, `Copy-Item`,
  `Move-Item`, `mv`, `cp`). All of them are ordinary environment changes or
  repo-local rewrites git can undo, and none carry repository context the
  native assessment lacks.

  Deferring is not approving. `{}` hands the decision to
  `chat.tools.terminal.autoApprove`; where that setting does not cover the
  command — the normal case — the result is a *better* prompt, not a missing
  one, and where it does cover it the user had already said what he wants.

  Seven rules stay ours, each for a reason the native assessment cannot reach:
  `git merge` and `git checkout`/`switch` (branch and worktree state — and the
  path form of checkout discards uncommitted work while `git checkout` is a
  plausible auto-approve prefix), `git tag` (a release marker others rely on),
  `databricks` and `az` (effects outside this repository), `Remove-Item` and
  `rm` (the one durable change git cannot undo). The task-launch asks are
  untouched: they fire precisely when the command cannot be resolved at all,
  which is the case that must never go quiet.

  A cross-harness assertion now fails if the PowerShell and bash classifiers
  retain a different number of rules — a rule kept in one and handed back in
  the other is a confirmation that appears on one platform only.

### Fixed

- **Gates were scoped to the diff, so a formatter run looked like authorship
  (issue #86).** The provenance, docstring and ignore-hygiene gates all asked
  their question of whatever the branch diff listed. A diff answers "which
  lines moved", and a formatter moves all of them. MPUsageXPTP work item
  WIT #3121 — `ruff format` across the repository, acceptance criteria "a
  single dedicated commit" and "no logic change" — came back with 148 hand
  edits across 68 files: 72 provenance markers, 35 docstring sections and 9
  suppression justifications, each one mapping onto a gate the agent had to
  clear to exit. The markers claimed authorship of files nobody authored, and
  an AST comparison found 11 files carrying authored docstring *content*
  inside a commit labelled formatting-only. Formatter adoption, import
  rewrites and codemods had no correct path at all: the implementer and
  refactorer are gated and the coordinator cannot write code.

  `check-python-quality.py` now answers a different question. `is_authored`
  compares the file's AST against the base commit's, with docstring
  whitespace collapsed — `ast.dump` omits line and column attributes, so
  reflowing, re-quoting and re-bracketing leave the signature untouched,
  while the words in a docstring do not. Undecidable means authored: no base
  blob, an unparseable file on either side, or git unable to answer all keep
  the gate on. Type hints and docstrings are skipped for a file with no
  authored change, and `--list-authored` reports the authored subset so
  `implementer-stop.ps1`/`.sh` can scope the provenance gate the same way.
  If that query cannot run, the gate keeps the whole diff.

  Ignore hygiene is deliberately *not* filtered this way: comments leave no
  trace in an AST, so a `# noqa` smuggled into a "formatting only" commit
  would read as mechanical. Instead, ownership there now follows the
  suppression rather than the line it sits on — inherited suppressions are
  counted in the base blob, and what is left over is what the branch
  introduced. This also fixes the converse misfire, where a reformat rewrote
  the line an inherited suppression sat on and made it blocking. Linting is
  not scoped by authorship at all, and both hook suites assert statically
  that no lint invocation references the filter.

- **The provenance gate could not see the marker the instruction prescribes
  (issue #81).** `provenance.instructions.md` puts a Python marker *after* the
  module docstring, and the marker for a modified function *inside that
  function's docstring*. Every gate that enforced it read the first five lines
  of the file. For a module docstring of four lines or more the two rules
  cannot both be satisfied; for the function-level placement they never can.
  The block message named the instruction it was contradicting, so the only
  move that cleared the gate was to violate the convention it pointed at.
  MPUsageXPTP work item WIT #3119 carried an acceptance criterion that was
  unsatisfiable for exactly this reason.

  Detection now lives in one place — `Test-AfProvenanceMarker` in `_common.ps1`
  and `af_has_provenance_marker` in `_common.sh` — and scans the whole file.
  All six call sites (`implementer-stop`, `test-writer-stop`, `scan-secrets`,
  in both shells) and the two rows in `compliance-checker.agent.md` now ask it,
  and their messages no longer promise a five-line window.

  `-Kind generated` still narrows *what counts* — test-writer's gate is about
  authorship of a new file, so `copilot:modified` must not satisfy it — but
  nothing was tightened about the marker's format. Widening where we look must
  not quietly start blocking work the old window would have passed.

- **The context budget measured the disk, not the content (issue #59).**
  `check-context-budget.py` estimated tokens as `st_size // 4` — bytes on disk.
  Bytes move for reasons that leave the content the model reads completely
  unchanged: CRLF adds one byte per line, so flipping `core.autocrlf` shifted a
  350-line instruction file by ~87 tokens; `—`, `→` and `≥` cost three bytes and
  one character, and AF instruction files are full of them; a stray BOM added
  three more. `architecture.instructions.md` measured **1,966** by bytes and
  **1,617** by characters — a 20% spread on one file, and enough to put the
  whole conditional set 273 tokens "over budget" without a single character
  having been added. A gate whose entire job is detecting real change must not
  react to changes that are not real.

  The estimator now counts characters read in text mode, with universal
  newlines and `utf-8-sig`, so line endings, typographic punctuation and BOMs
  are invisible to it. Counting characters means decoding, and decoding can
  fail, so a file that is not valid UTF-8 now BLOCKS (exit 2) instead of letting
  a `UnicodeDecodeError` escape as exit 1 — which would have been
  indistinguishable from "over budget".

  All three budgets are re-derived against the new scale in the same change —
  a mixed-estimator state would be worse than either alone. Measured on the
  character scale: always-on 4,865, conditional 5,387, largest agent 10,753;
  each budget is that figure plus the headroom it previously had, rounded down
  to the nearest 50: `AF_CONTEXT_BUDGET_TOKENS` 5000 → **4950**,
  `AF_AGENT_CONTEXT_BUDGET_TOKENS` 11000 → **10900**,
  `AF_CONDITIONAL_BUDGET_TOKENS` unchanged at **5500**.

  What the divisor is *not* is now stated where the budgets live: `4` is the
  rule of thumb for English prose, not a measurement of this payload. These
  figures are a drift scale, and the budgets are calibrated against that same
  scale — they are not a tokenizer-derived or billed token count. Calibrating
  the divisor against a real tokenizer remains open under issue #59.

  Also fixed: the authoring checklist told the reader to run a Python script
  with `pwsh`.

- **The documenter's Stop gate knew only one question, so it compelled a false
  answer (issue #72).** The documenter has two chartered jobs: persist plan
  files mid-workflow (Responsibility 1, Step 1 of Full TDD) and finalise at the
  end (Responsibilities 2-6). `documenter-stop` fired on both, and blocked
  unless `.github/logs/{id}.yaml` and `retros/auto/{id}.md` already existed. Its
  only escape was "not on an `agent/` branch", which never applies during a
  workflow. So a mid-workflow documenter call had exactly one way to terminate:
  write a workflow log marked COMPLETED, and a retro, for a workflow still
  running. The gate mechanically produced the fabrication it existed to
  prevent — observed three times in a consumer project, most recently with two
  subtasks still open.

  The damage did not stop at the file. The compliance-checker's post-flight
  HARD gate checked that those artifacts *exist*, so the premature ones
  satisfied it vacuously; the artifacts are invisible in review because
  `.github/` is gitignored in target projects and the documenter is forbidden
  to stage them; and the premature retro enters the coordinator's retro
  feedback loop as if it were a lesson.

  A Stop hook receives `session_id` and `transcript_path` and nothing else, so
  the invocation's intent is not knowable from stdin — it has to be read off
  the repository. The honest signal is the plan file, because setting its
  status to COMPLETED *is* the documenter's declaration that it finalised. New
  shared reader `Get-AfPlanLifecycle` / `af_plan_lifecycle` finds the plan that
  names `agent/{workflow-id}` and reports its status; the gate now applies only
  when that status is COMPLETED.

  Two things the reader deliberately refuses to do. It does not match raw
  text: `templates/PLAN.md` ships `**Status:** <!-- DRAFT | APPROVED |
  IN_PROGRESS | COMPLETED -->`, so a grep calls an untouched template a
  finished workflow — HTML comments are stripped first. And it does not accept
  any plan in the directory: a plan speaks for the one workflow whose branch it
  names. `stop-tests` had both defects in a worse form, passing if *any* file
  in `docs/plans/` mentioned COMPLETED anywhere.

  When no plan names the branch, the hook cannot classify the call. It says so
  and names the enforcement point rather than passing in silence — silence
  reading as consent is the defect this whole family is about.

  Aligned with it: `stop-tests` now shares the same reader and judges the same
  condition, differing in force rather than in what it considers wrong
  (PENDING while the workflow is open, WARNING when a COMPLETED plan is missing
  its closing artifacts). The compliance-checker's post-flight gates moved from
  existence to content — the log's `status:` must be COMPLETED with its
  mandatory fields and a non-empty `steps:` list, the retro must carry an
  actual lesson. And `documenter.agent.md` now states which responsibilities
  are mid-workflow and that a plan-persistence call must stop there.

- **Every confirmation prompt asked the same unanswerable question (issue
  #78, part b).** All eleven ask-tier rules shared one sentence — *"This
  command makes a durable change. Please confirm it is intentional."* — which
  named neither the rule that fired nor the command it fired on. `git merge`,
  `pip install`, `Remove-Item`, `databricks … deploy` and `mkdir` all produced
  the identical prompt, while the deny tier next door has always said exactly
  what it objected to and why. A question that does not say what it is about
  cannot be answered; it can only be waved through, which turns a confirmation
  into a keystroke and the gate into noise.

  Each rule now states its actual effect — `'Remove-Item' deletes files or
  directories`, `pip install/uninstall changes the environment for everything
  that uses it, not just this task`, `this Databricks CLI call acts on a remote
  workspace, where the effect is outside this repository and outside git` — and
  the command line itself is echoed (whitespace-collapsed, capped at 300
  characters), so the human answers about the command rather than the category.

  Carrying the command into the reason meant carrying its quotes and
  backslashes, so `block-dangerous.sh` now escapes the reason before
  interpolating it into its hand-built JSON. It did not before; it had simply
  never been handed a string that needed it. An unparsable verdict is
  indistinguishable from no verdict, so this would have disarmed the gate at
  exactly the moment it had something to say. PowerShell goes through
  `ConvertTo-Json` and was never exposed.

  The same question applied to the file's other emitter turned up a second,
  older instance: `emit_task` also hand-built its JSON, and its deny reasons
  quote the offending task command back at the reader — a path, on Windows a
  backslash path, where `\e` is not a valid JSON escape. The task tier could
  therefore silence its own deny without any wording change at all. Both
  emitters now escape, and both are pinned by mutation-tested cases.

  Part (a) of the issue — deciding, rule by rule, which confirmations to hand
  back to Copilot's own assessment by returning `{}` — is deliberately not in
  this change: that is a policy decision about auto-approval, not a wording fix.
- **The deny gate read quoted data as commands (issue #62).** Deny rules were
  matched against the raw command line, so text an agent was merely *passing*
  became text the gate believed it was *running*. Three false denies in one
  session: a read-only probe whose JSON test data contained
  `Remove-Item -Recurse -Force`, the same harness carrying a force-push string
  as a fixture, and — the one that cost real work — `git add <file> ;
  git commit -m "…the negated guard sm --force…"`. That last one is the worst
  shape of the bug: `(\S+\s+)*` in the `git add --force` rule happily matched
  across the `;`, joining a genuine `git add` in one statement to prose in the
  next. The commit message had to be reworded to get past a gate that was
  objecting to a description of itself.

  A false deny is not a harmless over-reaction. It teaches the agent that the
  gate is noise, and it pushes work back to the human for no security gain —
  the same currency a false allow spends, paid in the other direction.

  The fix is a change of unit, not of thresholds: the command line is split
  into statements, and each statement is scanned on its own, so no rule can
  span a separator. Quoted text is dropped only where it is unambiguously
  prose — the arguments of `echo`/`printf`/`Write-*` and of
  `git commit|tag|notes|stash`, and a segment that is nothing but a quoted
  literal (the JSON-on-stdin case). Stripping quotes globally would have been
  the wrong fix, because the payload of `bash -c "…"` lives inside quotes and
  *is* executed: those payloads are instead promoted to scan units of their
  own, which also closes an evasion the raw scan had all along —
  `powershell -Command "git add -A"` never matched `-A(\s|$)` while the closing
  quote was still glued to the argument. Quotes lose their protection entirely
  once they contain `$(` or a backtick, since the shell executes inside them.
  Three rules stay scoped to the whole line because they are about structure
  rather than a statement: pipe-to-shell, `DROP TABLE`, `TRUNCATE TABLE`.

  Both hooks were changed in lockstep, and twelve cases in each harness pin the
  three reported false denies alongside the payload promotions. Mutation runs
  confirm they bind to the gate: reverting to a raw scan reddens the four
  false-deny cases, disabling payload promotion reddens the two promotion cases.

- **The default test scope ran no tests, and reported it as green (issue #73).**
  `$scopeMap['all']` was the only entry carrying a trailing separator.
  `Join-Path` normalises `tests/` to `…\tests\`; because the workspace path
  contains spaces PowerShell quotes the argument, and the CRT argv parser reads
  the resulting `\"` as an escaped quote — it loses the closing quote and
  swallows every following argument into `argv[1]`. pytest received one
  nonsense path and collected nothing. Since `all` is the *default* scope, a
  bare `run-tests.ps1` was broken, together with four shipped VS Code tasks.
  It only reproduces from a path containing spaces, which is every default
  OneDrive path — hence its long life.

  The second half is the one that mattered. `2>$null` discarded pytest's usage
  error; with empty stdout no summary line parsed, and the runner wrote
  `"passed": 0, "failed": 0, "total": 0` to `test-log.json`. A consumer reading
  `failed: 0` concludes green — and the test-execution skill tells agents that
  log is the source of truth and that they may *skip* a run when it looks
  current, so the entry did not merely misinform, it suppressed the run that
  would have exposed it. This half was never Windows-specific: `run-tests.sh`
  produced the identical entry, and any runner failure triggers it.

  A run with no parseable summary and a non-zero exit is now recorded with
  `passed`/`failed`/`errors` as `null` — never `0` — plus `status: "error"` and
  the interpreter's own error text, which is no longer discarded but shown to
  the caller. `null` is the point: a consumer testing `failed == 0` now gets a
  false answer instead of a reassuring one. Both runners were fixed in
  lockstep, and `test-run-tests.ps1` pins the no-trailing-separator invariant
  for every scope, the argv survival, and the log's refusal to lie.

- **Task launches were never classified (issue #74).** `block-dangerous`
  matched `createAndRunTask`; the tools VS Code actually sends are
  `create_and_run_task` and `run_task`. The creation allowlist built in #56 —
  bare binaries denied, interpreters checked by payload, OS-scope decoys
  caught — had therefore never once run in production. It now matches the real
  name, and its 25 existing cases are joined by three asserting the same
  verdicts under it.

  `run_task` was worse than misnamed: it was not classified at all. Its
  payload is `{id, workspaceFolder}` — a name, and a name is not a command.
  The command lives in the project's `.vscode/tasks.json`, so a task doing
  `git push --force` launched with the classifier none the wiser. The gate now
  reads the task back out of `tasks.json`, reconstructs a command line for
  every scope (including `windows`/`linux`/`osx` overrides, which otherwise
  let `command` stand as a decoy) and puts it through the same three tiers as
  a terminal command.

  The two checks are deliberately different in kind. **Creation** keeps the
  allowlist: the agent is authoring the task, so it must point at a reviewed
  script. **Execution** uses the blocklist: `tasks.json` is human-authored and
  legitimately calls `git`, `pytest` and `databricks` directly, so an
  allowlist there would deny nearly every real task. Both are checked because
  the danger can enter at either point — a task can be smuggled into
  `tasks.json` by a file edit that never touches the creation gate, and a task
  that was acceptable when written may not be acceptable now, since policy,
  protected branches and autonomy categories all move underneath it.

  Anything unresolvable — no `tasks.json`, JSONC rather than strict JSON, an
  unknown label, an `${input:}` variable, an `options.shell` override —
  answers `ask` rather than staying silent. Per #68, silence is what a gate
  that cannot judge and a gate with no objection have in common.

  Residual gap, deliberately not closed here: a task carrying
  `runOptions.runOn: folderOpen` that is written straight into `tasks.json` by
  a file edit runs on the next folder open without passing either gate.
  Guarding that means classifying partial edits to `tasks.json`, which is a
  separate problem.

- **The parse gate walked past a stray CR (issue #70).** `bash -n` accepts one:
  the script parses, and the `\r` becomes part of the last token on every line.
  On Linux `#!/usr/bin/env bash\r` is `bad interpreter` — the hook exits
  non-zero having printed nothing, which per #68 is indistinguishable from
  approval. Both harnesses now assert that no shipped shell script carries a
  CR, across `hooks/scripts/*.sh`, `scripts/*.sh` and the extensionless
  `hooks/git/pre-commit` shim; four of the five drifted files sat outside
  `hooks/scripts/`, which is all the parse gate had been looking at.

  The issue's other two asks turned out to be already satisfied, which was
  worth testing rather than accepting: the git blobs were always LF,
  `.gitattributes` already pinned `*.sh text eol=lf`, and `deploy.ps1` stopped
  copying bytes for text files when EOL/BOM parity landed — `Copy-Item`
  survives only where UTF-8 decoding fails, i.e. binary assets. A real deploy
  from a checkout containing five CRLF sources emitted 22 `.sh` files with zero
  CRs. The deployed copy was already protected twice over; what was missing was
  anything that made the drift visible.

- **Every write gate matched tool names VS Code never sends (issue #69).** #64
  was one hook reading `url` where the tool sends `urls`. This asked whether
  that was a mistake or a habit, against 1935 hook invocations recorded in the
  chat debug log. It was a habit: `editFiles`, `createFile`, `createDirectory`,
  `editNotebook` and `writeFile` do not occur once in the corpus, and four
  hooks were matching on them.

  - **Four gates were inert on every file edit ever made.** The coordinator's
    delegation gate, the test-writer's TDD isolation gate, the refactorer's
    no-new-files gate and the secret scan returned `{}` for
    `replace_string_in_file` (37x), `multi_replace_string_in_file` (25x),
    `create_file` (10x) and `run_task` (14x). The refactorer's creation deny
    worked only by accident — `create_file` happens to contain `create` and
    `file`, which is what its substring heuristic looked for.
  - **The two platforms failed in opposite directions.** PowerShell matched
    camelCase and never fired; bash matched `*edit*|*create*|*write*|*file*`
    and would have **denied `read_file`** on a non-agent branch. Neither
    surfaced, because the fixtures encoded the same guesses as the code.
  - **`multi_replace_string_in_file` carries no top-level `filePath`.** The
    paths are one level down in `replacements[]` — the same nesting that hid
    #64's `urls`. A batched edit of twenty production files passed every gate
    without an opinion. One `Test-AfWriteTool` / `af_is_write_tool` and one
    `Get-AfWritePaths` / `af_write_paths` in `_common` now serve all four
    gates, on both platforms.
  - **Two further bugs in the bash secret scan**, found while restructuring it
    for multiple paths: `result=$(gitleaks ...) || true; if [ $? -ne 0 ]` tests
    `true`'s exit code, so a detection was always reported as a pass; and the
    fallback regex `[^\s"']{8,}` excluded the letter *s* rather than
    whitespace — inside a bracket expression `\` is literal — so the generic
    secret rule never matched. With gitleaks absent, the fallback is the live
    path.
  - Verified by the Red phase (14 gates returning `{}` where a deny was due)
    and by mutation: disabling the shared classifier turns 9 bash cases red, so
    the newly written cases test the gate rather than the fixture.
  - Task launches are a separate problem and were split out as #74:
    `run_task` sends only `{id, workspaceFolder}`, so classifying it means
    judging a project's existing `.vscode/tasks.json` — a policy decision, not
    a name repair.

- **The hook harness read silence as consent (issue #68).** `Assert-Allow` in
  `test-hooks.ps1` treated `{}` and empty output as an approval, so a hook that
  examined a request and approved it was indistinguishable from one that never
  ran, crashed, or read a field the tool does not send. That is not a testing
  nicety — it is the mechanism by which #65 (unparsable, exited non-zero,
  printed nothing) and #64 (wrong payload field, returned `{}` on every real
  fetch) both stayed green while shipping.

  - **One classifier, five outcomes.** `Resolve-Decision` replaces the parse-
    and-compare copied into each assertion and returns `allow`, `deny`, `ask`,
    `silent` or `error`. A non-zero exit or unparsable output is `error`: a
    hook that crashed is credited with no opinion, whatever it printed on the
    way out.
  - **`Assert-Silent` states the other claim.** 15 of the 30 `Assert-Allow`
    sites never meant "approved" — the delegation gate, the branch gates and
    every "not my tool" case return `{}` by design. They now say so, and the
    other 15 must produce an explicit `allow`.
  - **The bash harness judges the exit status too.** `run_case` captured only
    stdout, so a perfectly formed deny followed by a crash counted as a deny.
  - Verified by mutation rather than by a green run: making
    `block-dangerous.ps1`'s auto-approval tier inert turns 9 previously passing
    cases red, and a bash hook that prints a deny then exits 3 no longer
    passes. No hook changed behaviour — the blindness was entirely in the
    instrument.

- **The researcher's fetch hook was reading a payload the fetch tool does not
  send (issue #64).** It looked for `tool_input.url`; VS Code passes `urls` —
  an array — beside `query`. So both of its gates were inert: the credential
  scan never ran and the domain allowlist never ran, and the hook returned `{}`
  on every real fetch. The suite was green throughout, because the fixtures
  encoded the implementation's belief about the payload rather than a captured
  one. The tests now use the real shape, and `Assert-Allow` was deliberately
  not used for them — it counts `{}` as an allow, which is precisely how an
  inert hook passes for a year.

  - **Every URL in the array is judged, and one unlisted entry decides the
    batch.** The tool fetches all of them, so approving on the first match
    would wave the rest through unseen.
  - **The sanitiser aborted the hook on exactly the URLs it exists for.** Its
    `sed` used `|` as both the `s` delimiter and the regex alternation in the
    same expression, so a credentialed URL exited 1 instead of producing a
    warning. Delimiter changed; the interpreter resolution now comes from
    #54's shared preamble on both sides rather than being re-rolled.
  - **An allowlist bypass, found by probing rather than reading.** The host was
    taken from before the first `:` in the authority, which is the *userinfo*
    when one is present: `https://docs.python.org:x@evil.example.com/` was
    approved as "allowlisted documentation domain". The host is now what
    follows the last `@`, with the port stripped. This was not in the issue —
    it surfaced the moment the credential path could run at all.
  - **`Invoke-HookInFixture` now copies `_common.ps1`**, as the bash harness
    already does, so a fixture-run hook does not die before its first gate.

- **Two shipped hooks died before their first statement, and nothing noticed
  (issue #65).** `coordinator-pretooluse.sh` carried `\'git status\'` inside a
  single-quoted string and `session-mcp-readiness.sh` an unterminated
  `${msg//"/\"}`; both failed `bash -n`. A hook that cannot be parsed exits
  non-zero without printing a decision, and **the absence of a decision is how
  a hook says "no objection"** — so the coordinator's delegation gate, its
  worktree-branch check and its commit-message rule had been permitting
  everything, silently, for as long as the defect existed. No harness asserted
  that the shipped hooks parse.

  - **A parse gate in both harnesses.** `test-hooks.ps1` tokenizes every `.ps1`
    via `PSParser::Tokenize` and shells out to `bash -n` for the `.sh` side when
    bash is present; `test-hooks.sh` runs `bash -n` over every shipped hook.
    Cheap, and it fails on the file that would otherwise fail in production.
  - **Behavioural coverage found two further silent defects the parse gate
    could not.** Once the coordinator hook parsed, tests written against what
    it is supposed to *block* showed it still blocking nothing. Its outer
    `case` matched `*terminal*` only, but VS Code sends `runInTerminal` — bash
    `case` is case-sensitive, so the entire terminal branch was unreachable
    (the inner `case`, one screen below, already spelled both). And the
    commit-message parser read `sys.stdin` while being fed a quoted heredoc,
    which *is* python's stdin: the pipe was discarded, the message always came
    back empty, and the gate never fired. `coordinator-postmerge.sh` had the
    same heredoc/stdin collision and always reported "No active agent/*
    worktrees". Both now pass their payload through the environment.
  - **A bracket list that could not match.** `^\[agent:[^\]]+\]` looks correct
    and is not: a backslash is literal inside an ERE bracket expression, so the
    pattern demanded two closing brackets. It rejected every well-formed commit
    message — invisible while the hook was unparsable, immediate once it ran.
  - **The harness tripped over the same `$ErrorActionPreference` trap as #54.**
    `bash -n` writes its diagnostics to stderr, which under `Stop` becomes a
    terminating PowerShell error; `*> $null` does not prevent it. The parse
    gate saves and restores the preference around the loop.

  The unifying lesson across #54 and #65: unparsable, unmatched and unfed all
  fail identically — as silence. Only a test that asserts a hook *speaks* tells
  them apart.

- **Hooks resolved their roots, config and interpreter from wherever the agent
  process happened to be standing (issue #54).** A hook is not guaranteed to
  run from the repo root — under worktrees it routinely does not — yet six
  `.sh` and two `.ps1` hooks read `.github/af-env.conf` through the cwd, and
  three more discovered the root via `git rev-parse --show-toplevel`, which
  misses whenever `.github/` is not at the top level. The read returns nothing
  and nothing complains, because **an unread config is indistinguishable from
  an empty one**: every setting silently falls back to its default and the
  gate stops gating. Measured, not inferred — the same fixture returned
  `BASE_BRANCH=trunk` from the root and `[]` from one directory down.

  The interpreter lookup had the identical shape. `command -v python3` counts
  as "found" when it returns a path, and on Windows that path is the 121-byte
  WindowsApps App Execution Alias: on `PATH`, prints a Microsoft Store advert,
  runs nothing, exits non-zero. Hooks then took their `[ -z "$PYTHON" ]`
  fail-open branch and returned no opinion at all. #56 repaired two hooks by
  hand; five more still carried it. That is the pattern this fix targets — the
  preamble was copied per file, so each repair landed in one copy and the other
  nine kept the defect, twice in a row.

  - **One sourced preamble.** `hooks/scripts/_common.sh` and `_common.ps1`
    derive `AF_MAIN_ROOT` / `AF_CODE_ROOT` from the script's own location,
    honour the `.active-worktree` sentinel, expose `af_conf_get` /
    `Get-AfConfig` that distinguish *file missing* from *key absent*, and
    publish an interpreter that was **proven to run** rather than merely
    resolved. The accessors always return 0, because a missing key is not an
    error and callers run under `set -e`. Every hook now sources it.
  - **A drift guard, because the helper alone would not stop the next hook
    from being written the old way.** `scripts/check-hook-resolution.py` fails
    the build on cwd-relative config reads, `--show-toplevel` root discovery,
    bare `python` lookups and command-position `python3`; `test-hooks.ps1` runs
    it over the whole tree. Deliberate exceptions carry `af-resolution-ok` and
    a reason.
  - **`set -e` abort hazard removed.** Several hooks gated on `A && B && exit 0`,
    which kills the hook when `A` is simply false. Now explicit `if` blocks.
  - **The test harness was concealing the defect it existed to catch.**
    `test-hooks.sh` installed a `python3` shim into the fixture `PATH`, so the
    bash hooks met a working interpreter under test and the broken alias in
    production. The shim is gone.
  - **A missing assertion, not a missing fix, let the interpreter bug survive
    the helper commit.** Nothing asserted that the resolved interpreter *runs*.
    The new assertion failed on first execution and exposed that PowerShell 5.1
    silently drops empty-string arguments to native commands — the probe
    `& python -c ''` degenerates to `python -c`, so `Find-AfPython` rejected
    every working interpreter and took the lint gate from 21/21 to 2/21.
    Probed with `-c 'pass'` now, and asserted both ways: a real interpreter
    must run, a stub that resolves but exits non-zero must be rejected.
  - **Findings print to stdout.** Under `$ErrorActionPreference = 'Stop'`,
    native-command stderr becomes a terminating PowerShell error, so a checker
    that reported on stderr killed the suite with its own output. The exit code
    carries the verdict.

  Two adjacent defects were deliberately left alone rather than folded in:
  `coordinator-pretooluse.sh` and `session-mcp-readiness.sh` fail `bash -n` on
  `HEAD` already, and `#64` (`researcher-pretooluse` dead on every path) gets
  its own branch — it will consume this preamble instead of re-rolling the
  interpreter logic a third time.

- **The task execution path was unclassified, and the instructions pointed at
  it (issue #56).** `block-dangerous.*` filtered on the tool name before
  anything else, so the entire hard-deny tier was unenforced through
  `createAndRunTask`: `git push --force origin main` was denied as a terminal
  command and allowed as a task. Meanwhile `coordinator.agent.md` rule 3 read
  *"Prefer tasks over terminal"* and ordered the ladder
  `run_task → createAndRunTask → terminal`. The framework was instructing
  agents to prefer the one path no hook inspected.

  Both halves are fixed, because either alone is worthless — closing the hook
  leaves an instruction pushing agents at a locked door, and rewording the
  instruction leaves the door unlocked.

  - **Allowlist, not blocklist.** A task may invoke only a script under
    `AF_TASK_SCRIPT_DIRS` (new in `af-env.conf`, default `.github/scripts`).
    Bare binaries, inline interpreter payloads and unrecognised shapes deny.
  - **The effective command is classified, not the declared one.** Reading the
    VS Code tasks specification exposed three bypasses in the first
    implementation, all of which its own green test suite had missed: an
    OS-specific `windows`/`linux`/`osx` scope overrides `command`;
    `options.shell` moves the payload into the shell's arguments; and a
    `type: shell` `command` may be an entire command line, so
    `…/run-tests.ps1; <anything>` matched the allowlisted prefix. It also
    exposed one false deny — `${workspaceFolder}` substitution is legitimate.
  - **`lint: changed files` / `-Scope changed`** fills the one capability gap
    that made ad-hoc tasks genuinely necessary: agents can now lint the branch
    delta the stop-hook gate actually evaluates.
  - **The framing is corrected everywhere the tool is granted** — coordinator,
    implementer, refactorer, code-critic, `TOOLS.md`,
    `testing.instructions.md`, `tooling.instructions.md` and the
    test-execution skill. Tasks and terminal are described as one reviewed
    surface, not as rungs of a freedom ladder.
  - **Scratch hygiene.** `createAndRunTask` writes every one-off invocation
    into `.vscode/tasks.json`; `check-scratch-tasks.py` reports the leftovers
    at workflow end (advisory), and the repo-root scratch file is now ignored.

  Two pre-existing fail-opens in `block-dangerous.sh` surfaced only when the
  hook was *executed* rather than inspected. On Windows hosts `command -v
  python3` resolves the 0-byte App Execution Alias: non-empty, so it passed the
  emptiness check, but it executes nothing — every classification failed
  silently and the hook returned no opinion for **every** command, terminal
  included. The whole hook was inert on that host class. Separately, the three
  matcher helpers passed caller-supplied patterns to `grep` positionally, so a
  pattern starting with a dash was parsed as an option and the
  commit-hook-bypass deny rule never fired.

  This is a stopgap for #60, not a resolution: it classifies a payload shape,
  where the durable fix is to stop having two execution surfaces to keep in
  sync.

- **The context budget watched the always-on half and ignored the other one
  (issue #44).** `check-context-budget.py` gated `copilot-instructions.md`
  plus every `applyTo: '**'` instruction and reported `PASS`. The
  instruction files with a *narrower* glob were never counted — 9,699 tokens,
  twice the watched set. A narrow `applyTo` makes a file load less often; it
  does not make it cheap, and for the agent whose job is to touch matching
  files it is effectively always-on.

  The checker now prints the conditional set per file with its glob, enforces
  its total via `AF_CONDITIONAL_BUDGET_TOKENS`, and reports a per-agent
  **worst case** (own + always-on + all conditional).

  Two deliberate choices:

  - **The worst case is reported, not gated.** Co-occurrence is not
    computable offline, so the bound adds the same conditional total to every
    agent. Failing all fifteen for one shared cause is a broken signal, not a
    strict one; the budget on the *set* attacks that cause once.
  - **The budget was set after the reduction, not before.** Calibrating to
    the pre-existing 9,699 would have locked in the problem it was meant to
    surface.

  Measuring it also corrected the priority: the **coordinator** sits at 97% of
  its budget before any conditional file loads, and `copilot-authoring`
  matches `**/*.agent.md` — so it crosses the budget the moment it edits an
  agent file, while the gate reported `PASS`.

  Reduction followed the #25 pattern (contract inline, reference depth into
  skills): `testing.instructions.md` 3,671 → 1,304 (execution runbook →
  `skills/test-execution`; the AAA/test-doubles material was a duplicate of
  `skills/unit-testing`) and `copilot-authoring.instructions.md` 3,176 → 1,110
  (subagent pattern, tool-name catalogue, hooks, prompt features, tool sets →
  `skills/copilot-authoring`). Conditional set 9,699 → 5,262;
  `AF_CONDITIONAL_BUDGET_TOKENS=5500`. No enforceable rule left the
  instruction files — a glob audit found all four correctly scoped, so the
  cost was file size, not glob width.

- **The Python quality gate judged whole files, so an untouched neighbour
  could block a commit (issue #45).** `check-python-quality.py` received a
  file list and reported every function in it. In WIT #3105 a one-line
  registry change therefore demanded ~90 lines of NumPy docstrings on six
  unrelated methods, blocked three commit attempts, and ended in a recorded
  deviation — the only alternatives were out-of-scope edits or bypassing a
  HARD gate.

  The checker now takes `--diff-base REF` and reports only functions whose
  line span intersects the branch's diff against that ref. Decorator lines
  count as part of the function, so a decorator-only change is in scope.

  Three deliberate choices:

  - **The default did not change.** The issue proposed diff scoping by
    default with whole-file behind a flag; that is inverted here. A caller
    that forgets the flag would otherwise get a silently *weaker* HARD gate.
    Scoping activates only when a base is passed.
  - **No second base-branch resolver.** The stop hooks already resolve
    `merge-base HEAD $BASE_BRANCH` (falling back to `origin/`); they hand
    that result to the checker. `resolve_base` only verifies the ref.
  - **Unresolvable history fails wide, not narrow.** A shallow clone, a
    missing branch, or no repository at all falls back to whole-file scanning
    with a `NOTICE:` line — never to a silent pass. Untracked files are
    likewise scanned whole, since no diff can speak for them.

  `# noqa` / `# type: ignore` hygiene follows the same scope, but a
  suppression that predates the branch is reported as `ADVISORY:` rather than
  discarded — visible without blocking on inherited debt. A suppression added
  in an *earlier phase of the same branch* still blocks: it is after the
  merge-base, so the branch owns it.

  Verified by a new `test-quality-gate.ps1` (15 cases, each in a throwaway
  repository with a real base branch — the #37 lesson about tests that
  inherit the developer's working tree) and by mutation: 7/7 mutants killed.

- **Four hook gates were green for the wrong reason, and two hooks never ran
  at all (issue #37).** The issue reported that the test-writer and refactorer
  branch guards "never fire". They fire; the *test* never established a branch,
  so it read whatever branch the developer happened to be on. Filed from an
  `agent/*` checkout, the assertion inverts — and from `dev` the branch gate
  answered first for four tests named after a different gate
  (`test-writer cannot edit production code`, `… create production file`,
  `refactorer cannot createFile`, `… createDirectory`). Deleting the TDD phase
  isolation gate outright would have left the suite green.

  `test-hooks.ps1` now runs branch-dependent hooks inside a throwaway git
  repository checked out on a stated branch, and asserts **both** directions —
  denied off an agent branch, allowed on one. A test-only environment override
  was considered and rejected: a guard that a variable can switch off is not a
  guard. Each gate was then mutation-checked by disabling it one at a time; all
  five mutants are killed by a named test.

  Three real defects surfaced underneath:

  - **The researcher allowlist was never read.** The hook resolved
    `af-env.conf` via `git rev-parse --show-toplevel`, which misses whenever
    `.github/` is not at the repository top level. `WEB_FETCH_ALLOWLIST` came
    back empty, so *every* domain fell through to a prompt — and "allowlist not
    found" was indistinguishable from "domain not listed". Resolution is now
    script-relative and the two cases give different reasons.
  - **`refactorer-pretooluse.sh` was dead code.** It tested `$PYTHON` without
    ever defining it; under `set -u` the hook aborted before reaching a single
    gate. It had no coverage, so nothing noticed.
  - **A detached HEAD passed as an agent branch.** `git branch --show-current`
    returns empty when detached, and the guard only denied a *non-empty*
    non-agent branch — while the framework's own merge-rehearsal advice is
    `git worktree add --detach`. Detached-inside-a-repo now denies; outside a
    repository the guard still stays silent, deliberately.

  The bash pendants are no longer mirrors that are only ever reviewed by
  reading: `scripts/test-hooks.sh` runs them in the same kind of fixture
  (10 cases, all passing). That harness is how the dead refactorer hook
  surfaced.

- **`analyze-copilot-usage.py` asserted a foreground coverage figure that has
  since been disproved.** Both the module docstring and the report footer
  claimed per-turn foreground usage "is not persisted by VS Code beyond a
  stable ~2 % sample". Re-measurement on 139 session files gives 49 foreground
  records — 22.7% of recorded requests and 30.8% of credits, with records
  present as far back as March. The original reading was wrong: foreground
  turns are **sampled**, at roughly 0.35 records per session file regardless
  of session length, not absent.

  The corrected conclusion is unchanged in its practical effect — 0.35 records
  per session is still far below the one-per-turn density that per-workflow
  attribution needs — but the reason matters, and a frozen percentage in a
  docstring is how a stale finding outlives its evidence. The figure is now
  computed and printed (`0.35 per session file`) instead of asserted, so the
  tool corrects itself as the data changes.

  Also recorded: the sampled records skew expensive, so their **credit share
  overstates their share of turns**. Read the record count, not the credit
  share, before trusting any attribution built on them.

### Added

- **Workflow logs now record what the workflow cost (issue #50).** The framework
  could describe every step of a workflow but not what any of it cost, so the
  cost of a gate, a retry or an extra critic pass was a matter of opinion.

  `scripts/collect-session-cost.py` reads the chat debug log of the running
  session and emits an ADVISORY `cost:` block — billed requests, uncached/cached
  input tokens, output tokens, credits and a per-model breakdown. The documenter
  Stop hook appends it to `.github/logs/{workflow-id}.yaml` after the artifact
  gate passes, appending the script's output **verbatim**: the numbers never pass
  through a language model, and no agent reads the debug log (30 MB in one
  session here, every prompt included).

  Four decisions carry the design:

  - **Subagent cost is counted.** Subagent turns are absent from `main.jsonl`
    and run on different models; the collector sums every `runSubagent-*.jsonl`
    beside it. Reading only the parent understates every workflow that delegates
    — which is all of them.
  - **The session is derived, never guessed.** The hook builds the log path from
    the `session_id` and `transcript_path` that VS Code passes on stdin, which
    name the *parent* session even inside a subagent (measured). Picking a
    session directory by modification time would misattribute silently whenever
    parallel worktrees run concurrent sessions.
  - **An incomplete measurement reports as incomplete.** `coverage` is `full`,
    `partial` (the session began after the workflow did) or `truncated` — and
    when truncated, **no total is emitted at all**. The log's size cap drops the
    *oldest* entries, i.e. exactly the plan and Red phases, so a total would look
    complete while being biased downward.
  - **It stays ADVISORY, permanently.** The source is an experiment-flagged
    vendor setting that Microsoft can switch off remotely. A missing block is
    normal, `available: false` always carries a `reason`, the exit code is `0`
    on every degraded path, and nothing may gate on the number. Schema drift in
    the vendor's undocumented fields degrades to `available: false,
    reason: schema_drift` rather than emitting wrong numbers; a test pins the
    watched attribute set so that detection cannot be narrowed silently.

  Two measurement traps are handled explicitly: `inputTokens` already includes
  `cachedTokens` (the block reports `input_uncached`, and the two are never
  added), and a request without the billing attribute is *not billed* rather
  than free — those are counted separately as `unbilled_requests` instead of
  being summed as zero. Only numbers and short identifiers are ever emitted,
  against an explicit key allowlist, because request payloads carry whatever was
  pasted into chat. Regression tests: `scripts/test-session-cost.ps1`.

- **The local-only rule for logs and retros is now shipped, not merely
  documented (issue #49).** The README described `logs/` as gitignored and
  MANIFEST set a 30-day retention, but nothing enforced either. The rule
  existed only where a human had happened to add it — and in at least one
  project a workflow log had been committed anyway, `trigger:` (the verbatim
  user request) included.

  Two `.gitignore` files now travel with the payload: `.github/logs/.gitignore`
  and `.github/retros/auto/.gitignore`, each ignoring its directory's contents
  and re-admitting only itself and the README.

  Design decisions worth recording:

  - **Directory-scoped, not root-scoped.** Appending to the project's own
    `.gitignore` would mean merging into a file the project owns, with all the
    clobber and drift questions that `af-env.conf` needed `[customizable]`
    handling to answer. A `.gitignore` inside the directory it protects is an
    ordinary payload file: the existing deploy copies it, the existing hash
    tracking updates it, and the project's `.gitignore` is never touched.
  - **Split by author, not by topic.** `retros/auto/` is agent-generated and
    ignored; hand-written retrospectives one level up stay the project's
    choice. A retrospective a team wrote and agreed on is documentation, not
    instrumentation, and the framework has no business deciding its fate.
  - **Untracking is not automated.** A `.gitignore` has no effect on files
    committed before it existed, so shipping this changes nothing in a project
    that already tracks logs. `logs/README.md` names the check
    (`git ls-files .github/logs`) and states plainly that the removal is a
    human decision — the alternative would be an agent deleting history-tracked
    files on the strength of a pattern match.
  - **The retro location had to be settled first.** The agents wrote
    `retros/auto/`, the documenter's own output section said
    `.github/retros/auto/`, and the stop hooks accepted either. Predictably,
    one project ended up with 27 snippets at the repository root and 2 under
    `.github/` — and only the latter can ever be covered by a rule the
    framework ships, because the payload cannot place a file outside
    `.github/`. `.github/retros/auto/` is now stated consistently across the
    documenter, compliance-checker, coordinator and the retro-summary prompt.
    The stop hooks still accept the bare path so existing projects keep passing
    their gates, but they name the canonical one when reporting a miss. Without
    this, the shipped rule would have protected a directory the agents were not
    writing to.

  Prerequisite for the cost-logging work under issue #22: writing usage figures
  into a tracked file would commit usage data.

- **Context budget as a regression gate — `check-context-budget.py`
  (issue #29).** Issue #23 cut the always-on instruction set from ~13,000 to
  ~4,800 tokens. Nothing kept it there. Instruction files grow by accretion,
  and `applyTo: '**'` is the path of least resistance for any rule an author
  is unsure where to put — so the trim would have silently eroded, one
  reasonable-looking commit at a time.

  The always-on payload is fully computable offline: parse the `applyTo`
  glob out of each instruction file's frontmatter, keep the ones that match
  everything, add the unconditional `copilot-instructions.md`. The checker
  does exactly that and fails when the sum exceeds `AF_CONTEXT_BUDGET_TOKENS`,
  printing a per-file breakdown so the offending file is named rather than
  merely implied. It also checks the largest **per-agent** total (own prompt
  + always-on set) against `AF_AGENT_CONTEXT_BUDGET_TOKENS`, which is the
  number that actually bounds a request.

  Design decisions worth recording:

  - **Derived, never hardcoded.** The always-on set comes from the `applyTo`
    patterns themselves. A file that widens its glob to `**` is caught the
    moment it does so; a hardcoded file list would have gone stale on exactly
    the change it exists to detect.
  - **A missing or empty `applyTo` counts as always-on**, with a warning.
    That is the conservative direction: the ambiguous case is charged rather
    than excused.
  - **BLOCKED (exit 2) is distinct from over-budget (exit 1).** A missing
    instructions directory, a missing `copilot-instructions.md`, a missing
    agents directory, or a malformed budget value stops the check with
    "unknown" — it never falls through to a pass. Silence must not read as
    success (cf. issue #12).
  - **Frontmatter only.** `applyTo:` is read from the leading `---` block, so
    an instruction file that *discusses* `applyTo` in its body cannot
    false-match itself into or out of the always-on set.
  - **No dependencies.** Tokens are estimated as bytes ÷ 4, which is accurate
    enough for a budget ceiling and keeps the gate runnable anywhere.
  - **Works in both trees.** The `.github` root is derived from the script's
    own location, so it behaves identically in the framework source tree and
    in a deployed project.

  Defaults are calibrated against the measured payload with deliberately
  small headroom — always-on 4,868/5,000 tok, largest agent (coordinator)
  10,666/11,000 tok, roughly 3% in both cases. That is the point: adding an
  always-on rule should require removing something, narrowing a glob, or
  consciously raising the budget, not drifting past it unnoticed.

  Ships with `test-context-budget.ps1` (15 checks over synthetic `.github`
  fixtures, plus one that holds the real payload to its own budget) and a
  pre-save checklist entry in `copilot-authoring.instructions.md` — which is
  itself narrowly scoped, so the guidance loads exactly when someone is
  editing an instruction file and costs nothing on every other turn.

  **Existing projects:** `af-env.conf` is `[customizable]` and is not
  overwritten on redeploy. Add `AF_CONTEXT_BUDGET_TOKENS` and
  `AF_AGENT_CONTEXT_BUDGET_TOKENS` manually to tune them; absent keys fall
  back to the documented defaults, so the gate works either way.

### Changed

- **Always-on instruction set trimmed from ~13,000 to ~4,800 tokens per
  request (issue #23).** Three instruction files carry `applyTo: '**'`, so
  every agent on every request paid for all of their content. Most of it was
  addressed to exactly one agent.

  The measurement that motivated this: background compaction accounts for
  97.7% of recorded spend, at ~40.8 credits per compaction with a mean
  pre-compaction context of ~178k tokens. Always-on overhead is paid on every
  turn *and* re-paid through the compaction it accelerates, so it compounds.

  Three moves, no rule removed:

  - **`git-workflow.instructions.md` (5,322 → 1,190 tokens).** Only the
    coordinator runs git, yet every worker loaded the 22-row autonomy boundary
    table, both integration paths, the planning document lifecycle, the
    pre-commit guards, and Git LFS guidance. That depth moved to a new
    **`git-workflow` skill**; the instruction keeps what a worker actually
    needs — who may run git, the hard-denied operations, branch naming, and
    the atomic commit contract. Safe because the `block-dangerous` and
    `coordinator-pretooluse` hooks enforce the boundary mechanically, not via
    prompt text.
  - **`quality-gates.instructions.md` (4,979 → 1,375 tokens).** The Per-Agent
    Exit Gates block held all 15 agents' gate tables; each agent needs one.
    All 100 gate rows moved verbatim into the `## Exit Gates` section of the
    corresponding `agents/*.agent.md`, where they load exactly when that agent
    runs. This follows a pattern `ado-pipeline-manager` already used. The
    taxonomy, complexity tiers, exit protocol, and Gate Summary format stay
    always-on because they are genuinely universal.
  - **`provenance.instructions.md` (1,298 → 818 tokens).** Condensed prose;
    the marker formats moved into a single table. No rule changed.

  Two duplications surfaced and were resolved rather than carried along: the
  instruction's Worktree Lifecycle sections were a subset of the existing
  `git-worktrees` skill and were deleted, and `ado-pipeline-manager`'s local
  gate table had drifted from the canonical one (it was missing the
  "never creates/relaxes branch policies" HARD gate) — it is now reconciled.

- **`coordinator.agent.md` modularised from ~11,400 to ~6,000 tokens
  (issue #25).** The coordinator is the entry point for every task, so its
  system prompt is a fixed prefix on every coordinator turn — and it had grown
  into a single file holding routing rules, git procedure, worktree bootstrap,
  optional ADO sequences, and the verbatim delegation prompt for all nine
  workflow steps.

  The issue proposed splitting per workflow variant. That axis does not work:
  Steps 0–8 are largely *shared* across Full TDD, Quick Fix, and Trivial Fix —
  only which steps run varies — so a per-variant split would duplicate rather
  than reduce. The split used instead is by **conditionality and frequency of
  need**: content for features that are off by default, and content needed only
  once a workflow is actually executing.

  Three extractions:

  - **Worktree bootstrap and cleanup → `git-worktrees` skill § 2.** Steps 0d
    and 8 are skipped entirely when `WORKTREE_ENABLED=false` (the default) or
    on a Trivial Fix, yet ~914 + ~356 tokens of procedure were paid on every
    turn. The coordinator now carries a conditional pointer with the
    preconditions and the "if dirty, halt — never force-remove" rule inline.
  - **ADO Sync and ADO Pipeline workflow sequences → `ado-shared` skill.**
    ~788 tokens describing what happens when `ADO_CAPABILITY_MODE != off`
    (default: `off`). The pure-git default stays inline because it is what
    happens in almost every run.
  - **Execution runbook → new `tdd-orchestration` skill.** The workflow state
    machine, phase checkpoints, subagent context block, the Step 1–7b
    delegation prompts, and interruption/cancellation recovery — needed only
    once a workflow executes, not to decide *whether* to execute one.

  Degradation safety was the design constraint: the agent file keeps the
  workflow-selection diagrams (which agents, in which order) and a compact
  control-point table (retry ceilings and escalation branches per step), so a
  coordinator that never reads the runbook still retains the skeleton. The
  runbook adds precision, not the basic sequence.

  A documentation drift was fixed on the way: `git-worktrees/SKILL.md` stated
  a `WORKTREE_DIR` default of `../wt` in two places, while `af-env.conf`
  documents empty → compute `../{repo}_worktrees`. Two duplicate list-numbering
  bugs in the moved Step 0d / Step 8 procedures were corrected as well.

- **Subagent return verbosity is now conditional on outcome (issue #24).**
  Everything a subagent returns enters the coordinator's context and is
  **re-sent as input with every following coordinator turn**. A verbose success
  therefore costs far more than the tokens it took to write once — cost scales
  with the number of remaining turns, not with the size of the return.

  New `OUTPUT_VERBOSITY=full|standard|lean` in `af-env.conf`, **defaulting to
  `full`** so existing projects are unaffected until they opt in. `af-env.conf`
  is `[customizable]`, so a redeploy will not inject the key silently — and an
  absent key resolves to `full`, i.e. today's behaviour.

  **The invariant, in every mode: failure output is never reduced.** REJECTED,
  ESCALATE, FAILED, BLOCKED, and any failed HARD gate always return full
  detail, because that is exactly what the retry consumes. Verdict headers
  (`## Code Review Verdict: {V}` etc.) are HARD gates and are never dropped.
  Only the path where nothing went wrong gets shorter.

  Applied to the Gate Summary (collapses to one line when all HARD gates pass
  and nothing is BLOCKED), both critic verdicts, the three producer summaries,
  the documenter, and both compliance-checker checkpoints. Estimated ~900–1,000
  tokens of returned output per green Standard workflow, which is re-sent
  roughly four more times on average.

  Two things were deliberately **not** changed. The **arbiter** is only ever
  invoked on a dispute, so its entire output is already the failure path.
  The **planner** could not adopt the issue's "reference the plan file, don't
  restate it" proposal: the planner is read-only by design and the coordinator
  persists the plan, so the plan has to travel through chat. Reducing plan size
  is issue #26's subject, not this one.

  An early draft also shortened the REJECTED path by dropping passing checklist
  lines. That was reverted — a rule stated as absolute ("failure output is
  never reduced") survives contact with a weak executor; the same rule with an
  exception does not.

### Fixed

- **ADO agents restored after the upstream MCP toolset consolidation
  (issue #31).** The `azure-devops-mcp` server merged its per-operation tools
  into grouped tools driven by an `action` parameter. Every `ado-*` agent named
  the old ids, so all four stopped working at once.

  The failure mode is what makes this worth recording: an unknown tool id fails
  prompt validation and is dropped **silently**. The agents did not error — they
  ran with a reduced toolset and reported plausible-looking task failures, which
  is far more expensive to diagnose than a crash.

  Migrated across 7 files. The issue's own migration matrix covered `wit_*` and
  `repo_*`; `pipelines_*` and `wiki_*` had consolidated too and were equally
  broken, and the damage reached past the agent files into
  `quality-gates.instructions.md` and two `ado-*` skills. Fixing only what the
  issue described would have left half the regression in place.

  Two latent defects surfaced on the way. `ado-pr-manager` instructed calling
  `wit_add_artifact_link` in prose while that tool had never been in its
  frontmatter, so the deferred work-item linking fallback could never have
  worked — predating this regression entirely. And `ado-shared` required "the
  resolved organization" to construct artifact links with nothing in the
  framework defining it; `ADO_ORGANIZATION` now does.

  New guard: `.github/scripts/check-mcp-tool-ids.py`, wired into the existing
  `session-mcp-readiness` **SessionStart** hook and gated on
  `ADO_CAPABILITY_MODE != off`. Deliberately a **denylist**, not an allowlist
  against the current toolset — an incomplete allowlist produces false
  positives, and a stale one produces silent false negatives, which is the exact
  failure this guard exists to prevent. A denylist cannot go stale in a way that
  fakes a pass, and every hit carries its migration target. The hook invokes the
  Python checker rather than mirroring the 70-entry id table into PowerShell and
  Bash, accepting one process spawn per session to avoid the dual-maintenance
  pattern that caused the regression in the first place.

  Also adds an authentication and toolset-drift runbook to `ado-shared`. Auth
  was previously undocumented anywhere in the payload. The runbook separates
  three faults that present the identical symptom *"the tool does not exist"*:
  upstream consolidation, tool filtering (`-d` locally, `X-MCP-Toolsets`
  remotely), and identity/tenant failures.

  Version pinning was evaluated and deliberately declined — `@latest` stays, on
  the explicit condition that drift is now *detected*. Migration to the remote
  MCP server was evaluated and deferred; see issue #32 for the blockers and the
  re-evaluation triggers.

  **Deployers note:** `af-env.conf` is `[customizable]`, so `ADO_ORGANIZATION`
  is not written into existing projects on update. Add it manually to any
  project that uses the ADO workers.

- **Ignore hygiene reaches `tests/` (issue #18).** `check-python-quality.py`
  enforces that every `# noqa` / `# type: ignore` / `# pyright: ignore` carries
  an explicit rule code and a justification — but both stop hooks invoked it on
  the `SRC_DIR/` set only. A suppression in `tests/` was never checked.

  That was defensible while the quality gate was source-only. #13 made it a
  problem: `# noqa: RULE  # reason` is now the sanctioned way to acknowledge an
  inherited lint violation, and the canonical inherited file is a Red-phase
  file in `tests/`. The acknowledgement path ran exactly through the one place
  the justification check did not reach, so `# noqa` alone would have silenced
  the gate with nothing recorded.

  `check-python-quality.py` gains `--checks all|ignore-hygiene`. The hooks now
  run the full gate on `SRC_DIR/` as before, plus a hygiene-only pass over the
  rest of the lint set. The *checks* split stays in the script; the *mapping*
  from file class to check set stays in the hooks, so the `SRC_DIR`/`tests`
  convention does not leak into the checker.

  Scope follows #13: the hygiene set is the branch delta minus the files that
  already got the full gate. Without that, the #13 blind spot simply reappears
  one level up — an acknowledgement committed in an earlier phase would be
  invisible to every later phase. Type hints and docstrings stay current-step
  and source-only; those are authorship claims about this step.

  Regression suite 17 → **21 scenarios**. All four fixtures suppress the `F401`
  as far as ruff is concerned, so the lint gate goes quiet and only hygiene can
  still see them — the scenarios cannot pass for the wrong reason. Red 18/21
  (bare `# noqa`, unjustified `# noqa: F401`, and the same defect inherited
  from an earlier phase), Green 21/21. `quality_gate_not_applied_to_tests` still
  passes: the new block message deliberately avoids the `type hints/docstrings`
  wording that scenario asserts against.

  Also corrects two stale rows in `quality-gates.instructions.md` that still
  described the lint gate as current-step scoped after #13 widened it.

- **The lint gate now covers what the branch merges, not just the current step
  (issue #13).** Fourth finding in the same area as #6, #10 and #12, this time
  about the gate's *input set*. Both stop hooks linted the current step's diff
  (`--cached`, falling back to `HEAD`). But the coordinator commits the
  Red-phase test files before the implementer ever starts, so by the Green step
  those files are in neither diff — invisible to every later phase, and shipped
  unlinted. The gate was reachable (#12), correct (#10), and correctly wired
  (#6), and still let a whole file class through.

  The input set is now the **branch delta**: `merge-base(HEAD, BASE_BRANCH)..HEAD`,
  filtered to `SRC_DIR/` and `tests/` `.py` files that still exist in the
  worktree. The unit of accountability is what the merge adds, not what the
  last agent happened to touch. Only the **lint** gate widens — provenance and
  python-quality keep the current-phase set, since those are authorship claims
  about this step.

  The two sets are linted in **separate ruff invocations**, so pre-existence is
  part of the decision rather than lost in a merged report:
  - Current-step violations block exactly as before.
  - Inherited violations also block, but with a message that names them as
    earlier-phase debt and offers two legal moves: fix them, or acknowledge
    each with `# noqa: RULE  # reason` in its own standalone commit.

  Blocking with an acknowledgement path was chosen over a warning and over a
  separate debt ledger. A warning is how the current silent carry-forward
  happens; a ledger file would be new machinery nobody reads. The
  acknowledgement path reuses gates that already exist and are already enforced
  (ignore justification, atomic ignore commits) and lands in the PR diff, so
  old debt is cheap to fix when it is easy and *explicitly decided* when it is
  not — but never carried silently. Volume is bounded because the branch delta
  contains one workflow's own output, not repo history.

  New `BASE_BRANCH` key in `af-env.conf` (default `dev`), deliberately separate
  from the capability-scoped `ADO_DEFAULT_TARGET_BRANCH` — the lint gate must
  work with no provider configured. Resolution tries the local ref then
  `origin/<name>`; if neither resolves, the inherited set is empty and the gate
  falls back to the previous scope. Degradation never becomes a block.

  Regression suite extended 13 → **17 scenarios**. The Red proof is the two
  `lint_covers_earlier_phase_commit_*` scenarios (a `F401` committed on the
  feature branch, clean working tree, both hooks must block): 15/17 against the
  unmodified hooks, 17/17 after. The other two are negative controls that must
  keep passing — an unresolvable base branch degrades instead of blocking, and
  an inherited violation carrying `# noqa: F401  # reason` passes. Applies to
  `implementer-stop` and `refactorer-stop`, `.ps1` and `.sh`.

- **The lint gate is reachable without pytest or a `tests/` directory (issue #12).**
  Third finding in the same area as #6 and #10, this time about *reach* rather
  than correctness. Both stop hooks opened with two early `exit 0`s: no `pytest`
  on `PATH`, or no `tests/` directory, ended the hook right there. Every gate
  behind them — linting, provenance markers, python quality, ignore hygiene —
  died with the test gate, even though ruff needs neither a test runner nor a
  test directory. The message said "Green gate skipped", which reads like one
  gate was waived; in fact the whole hook was.

  A missing test runner now skips **only** the test gate. Execution falls
  through to the remaining gates, and the skip reason is surfaced in the final
  message (`tests gate skipped (pytest not found)`) instead of being reported
  as an unqualified PASS. Applies to `implementer-stop` and `refactorer-stop`,
  `.ps1` and `.sh`.

  Regression suite extended 9 → 13 scenarios: a `F401` violation in `SRC_DIR/`
  must block for both hooks with no `tests/` directory and with no `pytest` on
  `PATH`, plus a negative control that a clean tree without `tests/` still
  passes *and* still reports the skip. All four fail against the previous hooks
  and pass against the fixed ones.

- **The lint gate no longer overrules the project's own ruff config (issue #10).**
  Follow-up to #6: once the gate actually ran, it turned out to ignore the
  consuming project's ruff configuration entirely. `check-python-linting.py`
  passed its strictness set as a CLI `--select`, and a CLI selector outranks
  `ignore` in `pyproject.toml`. In the first project it was deployed to,
  `ruff check mpusage/ tests/` reported `All checks passed!` while the gate
  reported **296 errors** — 290 of them `E501`, a rule that project explicitly
  ignores. A gate that contradicts the codebase's own contract gets switched
  off, so this was a credibility problem, not a cosmetic one.

  The rule is now **project refinement over framework default, with a
  non-overridable core**:
  - The strictness set is a **floor**, not a replacement.
  - An explicit `ignore` / `extend-ignore` / `per-file-ignores` in
    `.ruff.toml`, `ruff.toml` or `pyproject.toml [tool.ruff]` **wins** — it is
    passed through to ruff as `--ignore` / `--per-file-ignores`.
  - `select` is deliberately **not** honoured: not selecting a rule is not an
    exception, so the floor still applies.
  - **`F8` (unused imports, undefined names) is non-overridable.** No project
    config switches it off.
  - Every applied or rejected override is printed in the gate banner
    (`project_ignore=…`, `core_override_rejected=…`), so a suppression is
    visible rather than silent.

  Config is discovered per file by walking up to the nearest ruff config, so a
  monorepo with several configs is handled correctly (files are grouped and
  ruff is invoked once per group). On Python < 3.11 (no `tomllib`) the gate
  degrades to the old behaviour and says so via `LINTING_GATE_NOTICE`.

  Implementation note worth keeping: protecting the core needs **two**
  mechanisms, not one. A probe disproved the obvious design — ruff resolves
  selectors by **specificity, not CLI order**, so `--extend-select=F8` beats a
  broad `ignore = ["F"]` but *loses* to an exact `ignore = ["F821"]`. Hence
  `--extend-select=F8` **plus** stripping core-overlapping entries out of the
  passthrough.

  Regression proof: `test-lint-gate.ps1` grows from 5 to **9 scenarios** —
  project `ignore` honoured, floor still applied to an unselected rule, and the
  core surviving both an exact (`F821`) and a broad (`F`) project ignore while
  the non-core part of that same ignore is still respected. 9/9 pass. Verified
  end to end against the real project that exposed the defect: **296 → 6**
  findings, the 6 remaining being genuine `C901` complexity violations.

- **The Python lint quality gate now actually runs (issue #6).**
  `LINTING_STRICTNESS=strict` was configured in a consuming project, yet a PR
  merged with 41 ruff violations — 34 of them in `tests/`. `check-python-linting.py`
  was sound; everything around it was mis-wired. Four defects, all closed:
  1. **Scope.** The `refactorer-stop` lint gate diffed `SRC_DIR/` only, so
     `tests/` was never linted. The pathspec now covers `SRC_DIR/` **and**
     `tests/` (`.ps1` + `.sh`). Note the gate's file set was **split** rather
     than widened: `check-python-quality.py` (type hints + NumPy docstrings)
     keeps the `SRC_DIR/`-only set, because those rules do not apply to test
     functions and widening the shared variable would have blocked every
     legitimate test file.
  2. **Agent binding.** Linting hung off the *optional* Refactor step — a
     coordinator that skipped Refactor got no linting at all. The gate is now
     mirrored into `implementer-stop` (`.ps1` + `.sh`) and listed in the
     implementer's exit gates in `quality-gates.instructions.md`.
  3. **No repo-wide entry point.** Added `.github/scripts/run-lint.ps1` /
     `run-lint.sh` (`-Scope all|src|tests`, `-Fix`, `-Strictness`), modelled on
     `run-tests.*` for venv resolution and exit-code semantics (0 clean,
     1 blocked, 2 violations). The check path delegates to
     `check-python-linting.py`, so the rule set stays single-sourced.
  4. **Tasks bypassed the tooling.** The `lint:` tasks in `.vscode/tasks.json`
     invoked a bare `ruff`, which fails with `CommandNotFoundException` because
     task shells do not activate the venv — the documented fallback path for
     restricted agents was therefore dead. Lint tasks now call `run-lint.ps1`
     (plus new `lint: ruff check src|tests` and `lint: ruff fix`), and the
     `ruff format` tasks call `.venv\Scripts\python.exe -m ruff`.

  Two further defects surfaced while proving the fix:
  - `check-python-linting.py` passed `--output-format=text`, removed in ruff
    0.9. On any current ruff the gate blocked **every** handoff with a bogus
    "violations found" message. Now `concise`.
  - The same script mapped any non-zero ruff exit to "violations". ruff uses
    1 for violations and ≥ 2 for its own failures; a broken invocation now
    reports BLOCKED instead of masquerading as a code-quality problem.

  Regression proof: `.github/scripts/test-lint-gate.ps1` builds throwaway git
  repos, plants a real `F401` in `tests/`, and drives both stop hooks end to
  end — including a clean-tree negative control and an assertion that the
  quality gate is *not* applied to test files. 5/5 scenarios pass; the suite
  skips cleanly when ruff or Python is unavailable.

- **`createAndRunTask` works again — `tasks.json` is strict JSON.**
  The documented fallback for agents without terminal access (test-writer,
  implementer, refactorer) was dead: `createAndRunTask` cannot parse JSONC, and
  `.vscode/tasks.json` carried a 12-line `//` header. Combined with the broken
  lint tasks above, those agents had no working lint path at all. The header is
  removed; per-task explanation lives in the `detail` field (data, not
  comments), and the cross-cutting rules move to a new
  **`instructions/tooling.instructions.md`** scoped with
  `applyTo: '**/.vscode/tasks.json'` — so it loads exactly when an agent edits
  that file and costs nothing otherwise. It documents what the header said
  (labels are a stable API; task shells do not activate the venv) plus rules
  that were previously only implicit: fixed arguments only, no `${input:...}`
  prompts, and the mandatory `presentation` / `runOptions.instanceLimit` block.

  Enforcement instead of hope: the git `pre-commit` shim is generalised from a
  single large-file check to a **guard set**, and gains
  `check-strict-json.py`, which rejects a staged `.vscode/tasks.json` that is
  not strict JSON (override: `ALLOW_JSONC=1`). Without it the next `//` line
  would silently break the tool again.

- **Framework documentation re-synced with the code (wiki + README + MANIFEST).**
  The `docs/wiki/` knowledge base had drifted since 2026-07-03 and described a
  framework that no longer exists in several places. Corrected: slash commands
  renamed to the `af-*` prefix (`/af-tdd-feature`, `/af-setup-project`, …); the
  agent roster is **15** personas (1 coordinator + 10 core workers + **4** ADO
  workers — `ado-pipeline-manager` was missing from `MANIFEST.md`); the
  Software Development domain has **28** rules, not 27 (`R-SD-28` GitFlow
  Quality Gates was added without updating `core/domains/_index.md`); the
  README no longer advertises a stale `v1.17.0` header nor the withdrawn
  "agents have no model lists" claim (deploy-resolved `AF_MODEL_TIER_*` is the
  current design). Added the previously undocumented mechanisms: the
  **MCP deploy path** and its tool surface, the **deliver → onboard → curate**
  lifecycle, `CREATE`/`DEACTIVATED` deploy classes, **managed regions**,
  canonical-byte (UTF-8/LF) hashing, **model tiers**, the `FS_WRITE` autonomy
  category, the deployed **large-file commit guard**, `LARGE_FILE_*` /
  `ADO_PR_MERGE_STRATEGY` config keys, the single-active-worktree limitation,
  and the real per-agent hook inventory.

- **VS Code test tasks no longer trigger a "select an instance" prompt.**
  Restricted agents (test-writer, implementer, refactorer) run tests via
  fixed-arg `run_task` because they have no `run_in_terminal`. When a
  `type: shell` task label was re-triggered while a previous instance was still
  running and no `runOptions.instanceLimit` was set, VS Code interrupted with a
  "select an instance" prompt that blocked autonomous execution. Every task in
  `.vscode/tasks.json` now carries
  `"runOptions": { "instanceLimit": 1 }` and a dedicated-panel `presentation`
  block (`panel: dedicated`, `showReuseMessage: false`, `clear: true`), which
  removes the collision prompt. Task labels and `args` are unchanged (stable
  API preserved). The `terminal.integrated.defaultProfile` setting is
  deliberately left untouched to avoid imposing a platform-specific terminal
  profile on target repos. Fixes
  [#4](https://github.com/sefalk/AgenticAIGovernance/issues/4).

- **Deactivated skills no longer churn as a perpetual `CREATE`.** When a project
  turned off an active-by-default skill (e.g. `git-worktrees` with
  `WORKTREE_ENABLED=false`), `/af-curate-skills` used to *delete*
  `skills/{name}/`. The framework still shipped it, so every subsequent deploy
  re-`CREATE`d the folder (re-activating the skill), which the next
  `--reapply` removed again — an endless deploy↔reapply churn that also lost the
  skill content until the next deploy. Deactivation now **moves** the folder to
  `skills/_available/{name}/` (preserving it), and all three deploy paths
  (`deploy_core`, `deploy.ps1`, `deploy.sh`) classify a framework
  `skills/{name}/` file as **DEACTIVATED** — not `CREATE` — whenever the target
  has `skills/_available/{name}/`. DEACTIVATED files are never written or
  baselined, so a deactivated skill stays off across deploys. Verified by
  byte-parity dry-run tests against the real `deploy.ps1` and `deploy.sh`.

- **Deploy prompt: reapply curated skills AFTER conflict resolution.** The
  `/mcp.af.deploy` redeploy flow ran `--reapply` *before* resolving conflicts, so
  a curated agent that landed in CONFLICT got its curation re-applied to the
  stale base and then discarded when the conflict was resolved by taking the
  framework — silent curation loss on large version jumps. The `deploy_prompt`
  now orders redeploy as **apply → resolve conflicts (curated-agent conflicts
  take framework base) → reapply curated skills → single final `update_hashes`
  re-baseline**, so curation lands on the final base and future dry-runs show
  PRESERVE instead of CONFLICT.

- **Python bytecode caches no longer leak into the deploy payload.** A stray
  `__pycache__/*.pyc` (created whenever a hook/script test runs against the AF
  source) was picked up by the recursive payload enumeration and deployed as a
  spurious `CREATE` (e.g.
  `hooks/scripts/__pycache__/check-large-files.cpython-311.pyc`). Every
  source/target file enumeration in `deploy.ps1`, `deploy.sh`, and the MCP
  (`collect_source_files`) now excludes `__pycache__/` and `*.pyc`/`*.pyo`, and
  a repo `.gitignore` entry prevents accidental tracking.

- **EOL/BOM parity between the two deploy paths.** Switching between
  `deploy.ps1`/`deploy.sh` and the MCP deploy (`af_deploy_mcp`) no longer
  produces spurious whole-file diffs from line-ending drift (CRLF↔LF) or a
  UTF-8 BOM. All three tools now write one **canonical byte representation —
  UTF-8 without BOM, LF line endings, agent model-tier tokens resolved —** and
  hash over exactly those bytes, so a deploy via one tool leaves the other's
  dry-run/diff at zero changes. A repo `.gitattributes` (`* text=auto eol=lf`)
  makes the source blobs deterministic (and fixes CRLF `.sh`/hook shims); the
  deploy tools additionally canonicalize at write time, so parity holds even
  from a CRLF working tree or a stale bundled wheel. Binary files are never
  normalized.
  **Design decision:** canonical EOL = *preserve source as LF* (the git blobs
  are already LF), enforced by `.gitattributes` and backed by defensive
  write-time LF-canonicalization in both tools. Chosen over pure
  `.gitattributes` (which leaves an existing Windows working tree CRLF on disk
  until a destructive re-checkout) and over unconditional normalization
  (identical bytes, but the hybrid keeps "source is truth" while staying robust).
  **Migration:** existing targets with mixed EOL self-heal on the next deploy —
  non-customizable files are rewritten to LF as a one-time UPDATE pass; then run
  `-UpdateHashes` / `update_hashes` to re-baseline `.af-hashes`. Customizable
  files keep their EOL until an intentional edit.

### Changed

- **`ado-work-item-manager`: field-applicability guard for write operations.**
  Azure DevOps accepts a write to a valid field even when the target work-item
  *type does not carry it* — the value is stored but never rendered on the form,
  so the human never sees it (classic case: `AcceptanceCriteria` written to a
  **Task**). The agent now, before writing a type-specific field, confirms the
  field is in the target type's `wit_get_work_item_type` fields; if absent it
  chooses a type that carries the field, or mirrors the content into
  `System.Description` under a labeled heading, and always reports which path it
  took — never a silent invisible write. Scoped honestly to field *applicability*
  (the form layout is not exposed by the MCP tools). Backed by a new HARD gate in
  `quality-gates.instructions.md`.

- **Provenance markers no longer clutter the framework's own files.** Removed
  ~129 in-code `copilot:generated`/`copilot:modified` markers from AF-authored
  files (agents, instructions, skills, hooks, scripts, `mcp-deploy/**`, docs,
  this CHANGELOG). They loaded into agent context on nearly every request for no
  benefit — framework authorship is already traced by git history + this
  CHANGELOG. `instructions/provenance.instructions.md` now scopes the marker
  rule to **project deliverables inside a target repository** and explicitly
  exempts the framework's own files; `templates/*.md` keep their placeholder so
  generated plan/investigation docs still carry a marker. Marker documentation,
  the `.py` provenance-check hooks, and example snippets are unchanged.

### Added

- **Managed regions — CONFLICT-free project-owned content inside framework
  files.** A file may now carry an `AF:MANAGED:{name}:START/END` marker pair
  whose body is project territory: the deploy hashes the region-*stripped* file
  for classification and *transplants* the target's region body onto the incoming
  framework base on write. So a project can populate the region locally without
  ever tripping a CONFLICT on redeploy, while framework changes *outside* the
  region still UPDATE normally; empty regions strip to themselves, so
  never-populated projects stay UNCHANGED. Byte-identical strip/merge is
  implemented across all three deploy paths — `deploy_core.py` (regex),
  `deploy.ps1` (`[regex]::Replace`), and `deploy.sh` (an awk state-machine with a
  join model + `od`-based trailing-newline handling) — and guarded by cross-tool
  parity tests (PowerShell via AST extraction; bash via awk-program extraction,
  verified locally under gawk 5.0). First consumer: **curated agent skills.**
  `/af-curate-skills` now writes curated skill references *only* inside each
  agent's `AF:MANAGED:curated-skills` region (idempotent full-body replace) with
  **base dedup** (a skill promoted into an agent's base list is dropped from the
  region) and **defensive migration** (stale bare curated bullets are stripped);
  the bare→region transition is otherwise handled by the existing
  conflict-resolution → reapply deploy flow. `/af-curate-skills` also now warns
  and drops assignments that target a skill-less agent (`coordinator`,
  `compliance-checker`). Authoring guidance (`copilot-authoring.instructions.md`)
  documents the mechanism and the **use-sparingly, prefer `af-env.conf`** rule.

- **Proactive notebook artifact-weight hygiene (guidance).** The
  `notebook-execution` skill gains an *Artifact Weight Hygiene* section with
  library-agnostic principles to stop notebook-driven repo bloat before it
  happens: reference (CDN/URL) over self-contained embedding, strip outputs via
  the wired `nbstripout` filter, big binaries to Git LFS, and place interactive
  exports in a docs/wiki artifact store. The large-file commit guard's fix hint
  was generalized (reference-mode, not Plotly-specific) and now points at the
  skill.
  **Design decision:** deliberately *guidance-only* — no dedicated bloat
  detector hook. A format-specific detector (e.g. grepping HTML for embedded
  `plotly.js`) would be a leaky, false-positive-prone abstraction that largely
  duplicates the existing size guard for the real (multi-MB) pain; the size
  guard remains the reactive backstop.

- **Large-file commit guard (real git pre-commit hook).** A `pre-commit` hook
  at `.github/hooks/git/pre-commit` (a POSIX-sh shim) runs
  `.github/hooks/scripts/check-large-files.py` on every `git commit` and blocks
  staging any file whose **staged index blob** exceeds `LARGE_FILE_MAX_BYTES`
  (`.github/af-env.conf`, default 1 MB / 1,048,576 bytes). Deliberate large
  files are exempted via `LARGE_FILE_ALLOWLIST` (comma-separated fnmatch globs
  against the repo-relative staged path); a one-off commit can override with
  `ALLOW_LARGE_FILES=1`. It is a *real* git hook (not a VS Code agent hook), so
  it enforces whether a human or an agent commits, and it measures the staged
  blob (`git ls-files -s` → `git cat-file -s`), i.e. exactly what would be
  committed. The checker is stdlib-only and **fail-closed** on git plumbing
  errors (exit 2); the shim is **fail-open** when the checker or a Python
  interpreter is missing. Wired per clone via
  `git config core.hooksPath .github/hooks/git`, set automatically by
  `bootstrap-python-env.ps1`/`.sh` (existing clones must re-run bootstrap once —
  hook wiring is not retroactive).
  **Design decision:** the shim lives under `.github/hooks/git/` rather than a
  repo-root `.githooks/` so it deploys through the existing `.af-manifest`
  `hooks/` entry — no change to the deploy payload scope (which covers only
  `.github/` + `.vscode/`) was required. Ships with a portable regression suite
  (`.github/scripts/test-large-file-guard.ps1`, checker-direct) and documents
  **Git LFS** as the right tool for legitimately large binary assets — the
  `LARGE_FILE_ALLOWLIST` is for small, deliberate exceptions only.

- **AF deploy MCP server (experimental, parallel to the scripts).** A Model
  Context Protocol server (`af-deploy-mcp`, package `af_deploy_mcp`, server id
  `af`) that exposes the framework deploy as MCP tools/prompts, so an agent can
  deploy AF into a target workspace **without cloning the AF repo next to it** —
  the `.github/` + `.vscode/` payload is bundled into the wheel (hatchling
  `force-include`), and the package **version tracks the AF `VERSION` file**
  (hatchling dynamic version) so a built wheel advertises the framework release
  it froze. Read tools (`status`, `dry_run`, `conflict_diff`, `list_orphans`)
  and guarded write tools (`apply`, `write_resolved`, `update_hashes`,
  `prune_orphans`, `prune_backups`; `confirm`-gated, workspace-scoped, backed
  up) mirror `deploy.ps1` classification and hashing (SHA-256, agent model-tier
  resolution) with verified parity. `list_orphans`/`prune_orphans` clean up
  framework files a rename or manifest change left behind (baselined in
  `.af-hashes`, no longer deployable) — project-created files are never touched.
  Prompts `/mcp.af.deploy` and `/mcp.af.resolve_conflicts` are **lifecycle-
  aware**: on first-time setup (no `.af-manifest` yet) the deploy prompt chains
  `/af-onboard-project` + an initial `/af-curate-skills`; on redeploy it restores
  curated skills via `--reapply` (falling back to a full curate when a project
  was never curated) and routes CONFLICT files to conflict resolution.
  Optional hash-pinned **remote payload** (`AF_PAYLOAD_URL` + `AF_PAYLOAD_SHA256`)
  for central governance without a hosted compute server. Runs **parallel to**
  `deploy.ps1`/`deploy.sh`; it does not deprecate them.

- **Per-agent model tiers (deploy-resolved).** Subagents now pin their model via
  a tier placeholder (`__AF_TIER_PREMIUM__` / `__AF_TIER_BALANCED__` /
  `__AF_TIER_EFFICIENT__`) in their `.agent.md` frontmatter; the deploy replaces
  it with the concrete model list from the target `af-env.conf`
  (`AF_MODEL_TIER_*`) or the curated built-in defaults, writing a prioritized
  YAML array so VS Code tries each model until one is available (drift-resilient
  — VS Code does not understand tier tokens natively, so the deploy resolves
  them). The **coordinator stays unpinned** (inherits the model picker). Tiers:
  PREMIUM = arbiter, code-critic; BALANCED = planner, implementer, test-critic;
  EFFICIENT = test-writer, refactorer, documenter, researcher,
  compliance-checker, and the ado-* workers. This stops every subagent from
  inheriting a premium model (previously nothing was pinned, so an Opus pick ran
  the whole pipeline on Opus). Token resolution is hash-stable (baseline hashes
  the resolved content, so re-deploys are no-ops) and byte-identical for the
  ~136 non-agent files. Documented in `copilot-authoring.instructions.md`.

- **`FS_WRITE` autonomy category** in the `block-dangerous` classifier: an
  opt-in tier for *harmless, non-read-only* local filesystem writes — `Out-File`,
  `Set-Content`, `Add-Content`, `New-Item`/`mkdir`, `Move-Item`/`Copy-Item`,
  `mv`/`cp`, a `> file` redirect, and **single-file** `Remove-Item`/`rm`.
  Recursive/force deletes and broad `rm` stay hard-denied. Default `ask`
  (`auto` only at the `autonomous` level); set `AUTONOMY_CAT_FS_WRITE=auto` to
  stop prompts for scratch writes. This lets a project allow harmless writes
  while still asking/blocking the critical ones, complementing the existing
  read-only vs durable distinction.

### Changed

- **`ado-shared` reference hygiene now requires clickable links.** Every ADO
  artifact an `ado-*` worker mentions (work item, pull request, wiki page,
  build/pipeline run, repository, branch) must be rendered as a clickable
  Markdown link `[<label>](<web-url>)` in its returned summary -- using the web
  URL from the MCP response (`webUrl`/`remoteUrl`/`_links.html.href`), or the
  canonical `https://dev.azure.com/{org}/{project}/...` pattern only as a
  fallback -- so the coordinator surfaces clickable references in chat instead
  of bare ids.

### Fixed

- **Deploy: customizable-file detection for files inside directories (Windows).**
  `deploy.ps1` built hash keys with backslashes on Windows while the
  `[customizable]` set (and the `.af-manifest`) use forward slashes, so
  customizable files *inside directories* (e.g. `scripts/run-tests.sh`,
  `skills/INDEX.md`) were not recognized as customizable and could be reported
  as `UPDATE`/`CONFLICT` instead of `PROTECT`/`PRESERVE`. Path keys are now
  normalized to forward slashes everywhere (source traversal + hash-file read),
  and existing backslash baselines migrate transparently on read. `deploy.sh`
  normalizes baseline keys on read too, for cross-platform compatibility.
  (Surfaced by the deploy-as-MCP PoC, which reimplements this correctly.)

- **Work-item status decoupled from git/PR (WIT drift fix).** Two state machines
  were fighting over work-item status: ADO auto-transitions items on PR
  completion while governance sets status evidence-based via the
  work-item-manager — causing premature auto-close, mis-attributed branches
  (work pinned to the wrong item), WIT-less units of work, and reactively-created
  items. Now: (A) `transitionWorkItems: false` is a **HARD gate** on the
  `ado-pr-manager` autocomplete call — the PR never touches WIT status; (B) a
  new coordinator **Step 0a "Work-Item First"** resolves/creates the item, sets
  it **Active**, and puts its id in the branch slug *before* the branch exists —
  one work item per unit of work, no branch without a WIT; (C) lifecycle follows
  commits (New→Active→Resolved on post-merge with AC-map→Closed at
  verification); (D) the R-SD-08 compliance gate now also checks the branch-slug
  WIT id **equals** the PR-linked id and that the item was Active at work start;
  (E) a **post-merge reconciliation** step is the single point where code and
  WIT state reconnect (evidence-based). The **work-item-manager is the sole
  authority over WIT status.** Touches `coordinator`, `compliance-checker`,
  `ado-pr-manager`, `git-workflow.instructions.md`, and `quality-gates`.

- **`ado-pr-manager` work-item auto-transition hardening.** The autocomplete call
  now **always** passes `transitionWorkItems: false` in the *same*
  `repo_update_pull_request` call that enables autocomplete. The azure-devops-mcp
  default is `true`, so merely "not setting it to true" was insufficient — a fast
  autocomplete merge could transition (close) linked work items and outrun a
  separate corrective call. Applied to both the `ado-pr-manager` agent and the
  `ado-pr` skill.

- **`block-dangerous` classifier precision** (fewer spurious prompts, same
  safety floor):
  - **Quote-aware segment splitting** — `;` / `|` *inside* a quoted string
    (e.g. a commit message or `-Pattern 'a|b'`) no longer splits the command.
  - **ASK scan runs on the quote-stripped command** — a commit message
    mentioning e.g. "databricks … export" no longer false-triggers an ASK rule.
  - **`git config <key>` reads** (no value) are recognized as read-only.
  - **`pip show/list/freeze/check` via a call operator / quoted interpreter
    path** (`& ".venv/Scripts/python.exe" -m pip show …`) is recognized as
    read-only; a leading `& "path"` call operator and a leading `$var =`
    assignment are unwrapped before classification; `Join-Path`/`Split-Path`/
    `Resolve-Path` are treated as pure helpers; `databricks current-user` is a
    read.
  - Stale hook tests updated to the three-tier classifier (destructive commands
    now assert `deny`, `git merge` asserts `allow`); added regression tests for
    each fix above.

- **Wiki placement routing** in `ado-wiki-manager` + `ado-wiki` skill: content
  is routed by scope — general / project-wide notes go to the **project wiki**
  (`ADO_WIKI_IDENTIFIER`), repo-specific docs are versioned in the code as a
  **code wiki** at the new configurable `ADO_CODE_WIKI_PATH` (default
  `docs/wiki`). Added `ADO_CODE_WIKI_PATH` to the `af-env.conf` template.
- **Wiki schema, health check & index conventions** in the `ado-wiki` skill
  (adapted from the LLM-Wiki pattern): enumerated page types + required YAML
  frontmatter with a controlled vocabulary to curb taxonomy drift; a
  new-page-vs-edit heuristic and minimalism/synthesis rule; an index/routing
  page plus a change-log convention (git history for code wikis, an append-only
  `## [YYYY-MM-DD]` changelog for the project wiki); and a **wiki lint pass**
  (deterministic schema/broken-link/orphan/duplicate checks as HARD, plus
  qualitative staleness/contradiction/drift/coverage checks as SOFT) with a
  maker-checker publish gate. The `ado-wiki-manager` gained matching
  responsibilities and a `LINTED` status.
- **Branch-to-Work-Item Association (R-SD-08)** operationalized in
  `git-workflow.instructions.md`: when tracker capability is active
  (`ADO_CAPABILITY_MODE != off`) the branch slug carries the work item id
  (`agent/{work-item-id}-{workflow-id}`) and the work item must link the branch
  + plan path; missing association is a HARD compliance post-flight gate.
  Enforced by the `compliance-checker` and the quality-gates spec. Backflowed
  from a downstream project where it was already in use.
- **Protected-wiki (`TF402455`) handling** in `ado-wiki-manager` + `ado-wiki`
  skill: a PR-required `wikiMaster` policy no longer causes blind retries — the
  agent takes the PR route (branch + wiki page + PR, human-completed) and falls
  back to a DEGRADED handoff with ready page markdown. Documents the known
  `wiki_create_or_update_page` `branch`-param limitation. Added
  `repo_create_branch` / `repo_create_pull_request` to the worker's tools.

## [1.19.0] -- 2026-07-02

### Added

- **Three-tier terminal autonomy classifier** (`block-dangerous` hook rewrite):
  every terminal command is classified `allow` (auto-approved), `ask` (prompt),
  or `deny` (hard-blocked) instead of the previous prompt-only pattern list.
  Auto-approval is segment-based (safe only when every `;`/`&&`/`||`/`|`/newline
  segment is individually safe), branch-aware (feature-branch git auto;
  protected-branch push/reset/rebase/branch-deletion hard-denied), and fail-safe
  (grouping/subshell/`$(...)`/backticks/file-write redirects never auto-approve;
  DENY is scanned across the whole command string). Configurable via
  `AUTONOMY_LEVEL` (`conservative` | `balanced` | `autonomous`) and per-category
  `AUTONOMY_CAT_*` overrides (`GIT_READ`, `GIT_FEATURE`, `GIT_MERGE`, `TESTS`,
  `FS_READ`, `PKG_INSTALL`, `DATABRICKS`, `CLOUD_READ`) in `af-env.conf`. Cloud reads that
  touch secrets/credentials/tokens are excluded and always prompt.
  Reversible topology changes (`git pull`/`merge`/`cherry-pick`/`revert`,
  reflog-recoverable) and merged non-protected branch deletion (`git branch -d`,
  which git allows only for fully-merged branches) auto-approve at `balanced`;
  force deletion (`-D`/`--force`), `reset --hard`, and `rebase` stay denied.
  Path-invoked tools (`.venv\Scripts\pytest.exe`, `.venv/bin/ruff`, …), static
  analysis tools (`radon`/`bandit`/`flake8`/`pylint`/`vulture`/`pip-audit`),
  `Push-Location`/`Pop-Location`, and branch-aware bare `git push` (auto only
  when the current branch is a non-protected feature branch) are recognised.
- **Researcher web-fetch allowlist**: `researcher-pretooluse` auto-approves
  fetches to `WEB_FETCH_ALLOWLIST` domains (official docs) and prompts for other
  domains with an offer to add them; credential-bearing URLs no longer
  short-circuit the allowlist decision.
- New `af-env.conf` keys: `AUTONOMY_LEVEL`, `AUTONOMY_CAT_*`,
  `PROTECTED_BRANCHES`, `WEB_FETCH_ALLOWLIST`.
- **Work item board routing** — new optional `af-env.conf` keys
  `ADO_DEFAULT_AREA_PATH`, `ADO_DEFAULT_ITERATION_PATH`, `ADO_DEFAULT_TEAM`.
  The `ado-work-item-manager` now sets `System.AreaPath` / `System.IterationPath`
  from these on create so new items land on the owning team's board (previously
  new items fell to the project default area — this key existed in a downstream
  project but was never generalized). Documented in the `ado-workitem` skill,
  the core `ado_work_item_management` skill, and a new SOFT routing gate.
- **Auto-version pre-commit hook** (`.githooks/pre-commit`) — bumps the patch
  component of `VERSION` whenever `flavors/github-copilot/**` or `core/**`
  source changes and `VERSION` was not itself staged (a deliberate minor/major
  cut stages `VERSION`, so the hook skips). Prevents the version drift that
  stranded `1.18.26`. Enable once with `git config core.hooksPath .githooks`.
- **Optional `ado-pipeline-manager`** capability worker: registers/runs/monitors
  an Azure DevOps PR quality-gate pipeline via MCP and emits Build Validation
  branch-policy settings for a human to apply (no MCP tool exists for policy
  creation). Terminal-free (MCP only), gated by `ADO_CAPABILITY_MODE`, with gate
  branches read from `ADO_GATE_BRANCHES`. Integrated into the coordinator
  (roster + optional pipeline workflow) and the per-agent quality-gate exit
  gates. New optional config key `ADO_GATE_BRANCHES` in `af-env.conf`.
- **Optional `ado-pr-manager`** capability worker + **`ado-pr`** skill:
  request-based integration via Azure DevOps pull requests with a
  branch-scoped completion policy (integration branch autonomous via
  autocomplete; protected branch human-only). Terminal-free (MCP only) — the
  coordinator pushes the feature branch, the worker manages the PR.
- Two-path integration model in `git-workflow.instructions.md`: pure git
  (default; push/merge human-controlled) vs optional request-based
  integration, gated by `ADO_CAPABILITY_MODE`.
- Optional PR config keys in `af-env.conf`: `ADO_DEFAULT_TARGET_BRANCH`,
  `ADO_PR_AUTOCOMPLETE_BRANCHES`, `ADO_PR_HUMAN_ONLY_BRANCHES`,
  `ADO_PR_DEFAULT_REVIEWERS`.
- **Closure acceptance-criteria gate** (two-stage, post-merge) and
  **multi-phase spec modeling** in `ado-work-item-manager`: finalize only
  Resolves (never Closes), an AC coverage map is posted before any closure,
  closure happens post-merge against merged evidence, no bulk-close, and
  multi-phase work is modeled as a Feature with phase child stories
  (deterministic detection; mis-typed single stories are flagged, not closed).
  The `ado-pr-manager` never sets `transitionWorkItems` (no PR-driven
  auto-close).

### Changed

- **PR review hardening:** the traceability thread must be posted with a
  resolved status (so a `comment resolution = Required` policy cannot block
  the PR's own autocomplete); autocomplete is only set after the work-item
  link is confirmed (so a `linked work items = Required` policy cannot stall
  an autocompleting PR).
- **compliance-checker** now enforces the integration path post-flight
  (request-based vs pure git) as a HARD gate.
- **session-mcp-readiness** probe validates PR completion config keys
  (`ADO_DEFAULT_TARGET_BRANCH`, `ADO_PR_AUTOCOMPLETE_BRANCHES`,
  `ADO_PR_HUMAN_ONLY_BRANCHES`) when ADO capability is active.
- **ado-shared** is documented as the canonical (DRY) source for shared
  `ado-*` worker boilerplate (execution defaults, repo resolution, gate
  summary). Provider neutrality is labeled a design goal, not yet delivered.
- `block-dangerous` hook is now a three-tier autonomy classifier (see Added):
  feature-branch pushes auto-approve; force pushes and pushes naming a
  protected branch are hard-denied (previously prompt-only).
- `MANIFEST.md` git conventions and coordinator workflow are now
  integration-path aware (pure git vs request-based).

- `databricks-execution-patterns` skill: deterministic Databricks workflow
  orchestration — UC/hive_metastore detection, run-type selection, output
  retrieval, evidence gating, cluster management, and escalation rules.
- `templates/af-env.conf.databricks`: project configuration template for
  job registry, fallback cluster, and authentication profile.
- `docs/DATABRICKS_SETUP.md`: step-by-step integration guide for new projects.
- Optional Azure DevOps capability workers for work item and wiki lifecycle
  handling: `ado-work-item-manager` and `ado-wiki-manager`.
- Shared ADO integration skills for provider defaults, optional probe
  handling, and non-destructive update guidance.
- Generic governance updates for platform optionality, graceful degradation,
  and fallback traceability when ADO is unavailable or out of scope.

### Changed

- Coordinator, manifest, and quality-gate docs now treat ADO integrations as
  optional capabilities rather than hard requirements.
- Project and flavor guidance now use the provider-scoped `ado-` naming
  convention consistently.

## Versioning Rules

- **Major** — breaking changes: removed files, renamed agents, changed contract
  formats, restructured directories
- **Minor** — new capabilities: new skills, new instructions, new prompts, new
  templates, new agents
- **Patch** — fixes: typos, threshold corrections, frontmatter fixes, doc
  clarifications

---

## [1.18.26] -- 2026-04-16

### Fixed

- **Worktree-aware hook scripts** via `.github/.active-worktree` sentinel file.
  All CWD-anchored hook scripts (`implementer-stop`, `refactorer-stop`,
  `test-writer-stop`, `test-writer-pretooluse`, `refactorer-pretooluse`,
  `coordinator-posttooluse`, `coordinator-postmerge`) now resolve two paths:
  - `$mainRoot`: main checkout (derived from `$PSScriptRoot`), used for
    `.github/` files (config, scripts, test-log).
  - `$codeRoot`: active worktree path read from `.github/.active-worktree`
    when present, otherwise `$mainRoot`. Used for `git` operations, pytest,
    and source file lookups.
  Previously, all hooks used `Get-Location` (VS Code CWD = main checkout),
  so quality gates silently ran against the wrong directory when a worktree
  was active. See `ideas/feature-git-worktrees.md` §12.

- **Coordinator Step 0d** now writes `.github/.active-worktree` (absolute path)
  immediately after `git worktree add`.

- **Coordinator Step 8** now deletes `.github/.active-worktree` before removing
  the worktree, returning hooks to main-checkout mode.

- **`WORKTREE_ENABLED` default restored to `true`** (was temporarily set to
  `false` in v1.18.25-patch while the hook issue was unresolved).

### Known Limitation

- Only **one active worktree at a time** is supported by the sentinel approach.
  Parallel worktrees require Option B (auto-deploy into each WT) — see
  `ideas/feature-git-worktrees.md` §13 for the decision analysis.

## [1.18.25] -- 2026-04-15

### Added

- **Worktree Python interpreter mode config** in `.github/af-env.conf`:
  - New key: `WORKTREE_VENV_MODE=shared|isolated`.
  - Default: `shared` (reuse parent repo `.venv`).
  - `isolated` creates a dedicated `.venv` in each worktree.

### Changed

- **Coordinator Step 0d** now includes explicit Python interpreter setup policy:
  - Reads `WORKTREE_VENV_MODE`.
  - Configures `python.defaultInterpreterPath` in worktree settings.
  - Falls back from `shared` to `isolated` when parent `.venv` is missing.
  - Avoids prompting the human for interpreter selection unless both strategies fail.

- **Coordinator Step 8** now documents isolated venv cleanup before worktree removal.

- **Worktree bootstrap scripts** (`setup-worktree.ps1/.sh`) now:
  - Read `WORKTREE_VENV_MODE` from `af-env.conf`.
  - Use path-based interpreter configuration (`python.defaultInterpreterPath`).
  - Support `shared` and `isolated` execution modes without symlink/junction dependency.

### Documentation

- Updated `README.md` to document `WORKTREE_VENV_MODE` and interpreter prompt avoidance.

## [1.18.24] -- 2026-04-15

### Added

- **Optional worktree support** via `WORKTREE_ENABLED` configuration flag.
  - New config: `WORKTREE_ENABLED=true|false` in `.github/af-env.conf` (default: `true`).
  - When `false`, agent workflows run in main checkout (useful for CI/CD or single-threaded environments).
  - When `true` (default), coordinator bootstraps worktrees at Step 0d (existing behavior preserved).

- **Auto-computed worktree paths** based on project name.
  - `WORKTREE_DIR` now defaults to empty in `af-env.conf`.
  - If `WORKTREE_DIR` is empty, coordinator auto-computes:
    ```
    ../{git_repo_folder_name}_worktrees
    ```
    Example: `MP Field Data Analysis CT` → `../MP Field Data Analysis CT_worktrees`
  - Projects can still override by setting `WORKTREE_DIR` explicitly.

- **Auto-add worktree folder to VS Code workspace**.
  - When coordinator creates a worktree (Step 0d), it automatically creates or updates
    `.code-workspace` file to include the worktree folder.
  - Worktree folder appears in VS Code Explorer as a separate workspace root.
  - On cleanup (Step 8), worktree folder is removed from workspace.

### Changed

- **Coordinator Step 0d (Worktree Bootstrap):** Restructured with explicit WORKTREE_ENABLED check.
  - If disabled: proceed to Step 1 in main checkout.
  - If enabled: perform full worktree setup + VS Code workspace registration.
  - Auto-computes `WORKTREE_DIR` from repo name if not configured.
  - Added workspace folder management logic.

- **Coordinator Step 8 (Worktree Cleanup):** Updated to respect `WORKTREE_ENABLED` flag.
  - Skip cleanup if `WORKTREE_ENABLED=false`.
  - Added workspace file cleanup on removal.

- **Subagent Context Injection:** Updated `work_location` field to handle optional worktrees.
  - Context now uses `Work location: Worktree: {path}` or `Work location: Main checkout (worktrees disabled)`.

### Documentation

- Updated `.github/af-env.conf` template with comprehensive `WORKTREE_ENABLED` and `WORKTREE_DIR` docs.
- Clarified that `WORKTREE_DIR` auto-derives from project folder name if left empty.

## [1.18.7] -- 2026-04-14
---

## [1.18.23] -- 2026-04-15

### Added

- **Coordinator AF version awareness at Step 0.**
  - Coordinator reads `.github/.af-version` at the start of every workflow
    and logs the active framework version (`AF vX.Y.Z`) in its opening narration.
  - Includes a "context hygiene" notice: if a deploy happened since the
    conversation started, agents advise the human to start a new conversation
    so all agents pick up the latest instructions from disk.
  - `PLAN.md` template gains an `AF Version:` metadata field, making the
    deployed version traceable per workflow artifact.
  - Documenter YAML log schema gains an `af_version:` field.

---

## [1.18.22] -- 2026-04-15

### Added

- **Deploy hardening set (backup lifecycle + safer preflight + dry-run contract).**
  - Backup retention config key in `.github/af-env.conf`:
    `BACKUP_PRUNE_DAYS=14`.
  - Retention precedence in deploy scripts:
    `CLI override > af-env.conf > default (14)`.
  - `-UpdateHashes` / `--update-hashes` now also cleans leftover
    `.af-backup-*` conflict backups.
  - New preflight check for notebook projects:
    if `NOTEBOOKS_ENABLED=true`, `.gitattributes` must include
    `filter=nbstripout`.
  - Deploy prints warning when target repository is on `agent/*` branch.
  - Dry-run output now includes machine-readable line:
    `DRYRUN_JSON {...}` for CI/log parsing.
  - New regression smoke script:
    `.github/scripts/test-deploy-flags.ps1`.

### Changed

- `README.md` documents backup retention config and expanded quick preflight
  scope for notebook filter alignment.

---

## [1.18.21] -- 2026-04-15

### Added

- **Automatic stale backup pruning in deploy scripts.**
  - `deploy.ps1` adds `-BackupPruneDays <N>` (default: `14`, `0` disables).
  - `deploy.sh` adds `--backup-prune-days <N>` / `-b <N>` with same behavior.
  - During deploy, stale `.af-backup-*` directories in the target root older
    than the configured threshold are pruned automatically.
  - Current run backup behavior remains unchanged: conflict backups are still
    preserved for manual recovery.

---

## [1.18.20] -- 2026-04-15

### Added

- **Jupyter notebook output stripping anchored in AF (`NOTEBOOKS_ENABLED`).**
  - New `NOTEBOOKS_ENABLED=false` key in `af-env.conf` template. Set to `true`
    for Python projects using Jupyter notebooks.
  - `bootstrap-python-env.ps1` / `.sh` now run `nbstripout --install` when
    `NOTEBOOKS_ENABLED=true`, registering the git clean filter automatically on
    every clone/environment setup. This prevents notebook outputs from dirtying
    git status after cells are run.
  - Warns if `.gitattributes` is missing the `filter=nbstripout` entry.
  - New reference template: `.github/templates/gitattributes-notebooks.txt`.

---

## [1.18.19] -- 2026-04-15

### Added

- **Recommended deployment policy documented in README.**
  Added an explicit split between:
  - developer iteration mode (`-Preflight` / `--preflight`, quick)
  - release handoff mode (`-RequirePreflight` / `--require-preflight`, full)

  This formalizes when preflight is advisory vs when it is a hard gate.

---

## [1.18.18] -- 2026-04-15

### Added

- **Deploy preflight checks in both deploy scripts.**
  - PowerShell: `deploy.ps1` now supports:
    - `-Preflight` (run checks, non-blocking)
    - `-RequirePreflight` (run checks, block on failure)
    - `-PreflightMode quick|full` (default: `quick`)
  - Bash: `deploy.sh` now supports:
    - `--preflight` (run checks, non-blocking)
    - `--require-preflight` (run checks, block on failure)
    - `--preflight-mode quick|full` (default: `quick`)

### Preflight Profiles

- `quick`:
  - hook integration tests (`.github/scripts/test-hooks.ps1`)
  - skills validation (`.github/scripts/validate-skills.py`)
  - tool audit (`.github/scripts/audit-tools.ps1`)
- `full`:
  - quick profile + worktree integration tests (`.github/scripts/test-worktree-scripts.ps1`)

### Notes

- `-RequirePreflight` / `--require-preflight` provides a true deployment gate.
- Optional preflight mode still reports failures but allows deployment to continue.

---

## [1.18.17] -- 2026-04-14

### Added

- **Python environment bootstrap scripts**
  - `.github/scripts/bootstrap-python-env.ps1`
  - `.github/scripts/bootstrap-python-env.sh`
  Creates `.venv` when missing, upgrades pip/setuptools/wheel, and installs
  runtime + dev dependencies from `af-env.conf`.

- **Coordinator pretooluse bootstrap interception** (configurable)
  - New config keys in `.github/af-env.conf`:
    - `PROJECT_LANGUAGE=python`
    - `PY_ENV_BOOTSTRAP=ask|always|off` (default: `ask`)
  - In Python projects, when `.venv` is missing and coordinator runs
    Python-related terminal commands, the hook now:
    - `ask`: requests human approval to run bootstrap
    - `always`: auto-runs bootstrap script before continuing
    - `off`: disables interception

### Changed

- `README.md` prerequisites now document bootstrap behavior.
- `.github/.af-manifest` now includes bootstrap scripts.

---

## [1.18.16] -- 2026-04-14

### Fixed

- **HARD gate consistency for linting:** `refactorer-stop.ps1/.sh` now blocks
  handoff when linting cannot run (`ruff` missing), instead of reporting PASS
  with a `BLOCKED` lint status. This aligns behavior with the Quality Gate
  model for BLOCKED hard gates.

- **Dependency guidance sanitization:**
  - `README.md` now marks `ruff` as required (not optional) because the
    refactorer linting gate is hard-enforced.
  - `.github/af-env.conf` comments now state that missing `ruff` blocks
    refactorer handoff.

### Verification

- Hook integration suite: **53/53 PASS**
- Skills validation: **51/51 PASS**
- Tool audit: all registered tools valid; no duplicate tool definitions detected.

---

## [1.18.15] -- 2026-04-14

### Fixed

- **Hook test regressions (3 cases):** `test-hooks.ps1` still asserted `Allow` for
  test-writer/refactorer file operations on `main`. Since v1.18.10 the branch-context
  gate correctly denies those — tests updated to `Assert-Deny` with accurate descriptions.
  Suite now passes 53/53 (was 50/53).

- **`git-worktrees` SKILL.md missing YAML frontmatter:** Skills validator reported
  `invalid or missing YAML frontmatter`. Added `name`, `description`, and
  `argument-hint` frontmatter block. Skills validation now passes 51/51.

- **Refactorer pass message inaccuracy:** Stop hooks claimed `linting clean` even when
  ruff was not installed (BLOCKED) or the gate was skipped. Both `refactorer-stop.ps1`
  and `refactorer-stop.sh` now track a `$lintStatus` / `lint_status` variable
  (`clean` | `BLOCKED (ruff not installed)` | `skipped (script/python not available)`
  | `no src changes`) and emit it in the `systemMessage`.

- **CHANGELOG wrong date:** Entry `[1.18.7]` had date `2026-06-27` (future). Corrected
  to `2026-04-14`.

---

## [1.18.14] -- 2026-04-14

### Changed

- **Default linting strictness is now strict.**
  `LINTING_STRICTNESS` in `af-env.conf` now defaults to `strict` instead of
  `standard`, so refactorer lint hard-gates use the full rule set by default.

---

## [1.18.13] -- 2026-04-14

### Added

- **Linting Hard Gate — `scripts/check-python-linting.py`.**
  Dependency-light ruff wrapper that enforces linting quality on changed
  source files during the Refactor phase.
  Reads `LINTING_STRICTNESS` from `af-env.conf`:
  - `minimal` → F8 (unused imports + undefined names)
  - `standard` → E,F,I (+ pycodestyle errors + isort)
  - `strict` → E,F,I,B,UP,SIM,C90 (+ bugbear, pyupgrade, simplify, complexity)
  Exit 0 = pass, 1 = ruff not installed (BLOCKED — advisory skip, not deny), 2 = fail.

- **`refactorer-stop.ps1/.sh` — Gate 5 (Linting).**
  Calls `check-python-linting.py` on all changed `SRC_DIR/**/*.py` files.
  HARD gate: if exit 2, blocks with `ruff check --fix` remediation hint.
  BLOCKED state (ruff missing) is advisory — does not deny the commit.

- **`af-env.conf` template — two new configurable keys:**
  - `LINTING_STRICTNESS=standard` — controls ruff rule set
  - `PYLANCE_TYPE_CHECKING=strict` — documents Pylance strictness for agents

- **`.vscode/settings.json` — `python.analysis.typeCheckingMode: "strict"` default.**
  Anchors Pylance strict type checking in the workspace settings.
  Projects can override per `[customizable]` convention.

- **`quality-gates.instructions.md` — Refactorer linting HARD gate.**
  Explicitly documents the new gate: `check-python-linting.py` on changed
  source files; BLOCKED (not FAIL) if ruff is absent.

---

## [1.18.12] -- 2026-04-14

### Added

- **Git Worktrees — Phase 4: Integration Tests.**

  **`scripts/test-worktree-scripts.ps1`**
  19 integration tests covering the full lifecycle of `setup-worktree.ps1` and `cleanup-worktree.ps1`.
  Creates isolated temp git repos and exercises:
  - Setup: valid IDs, parallel worktrees, validation gates (bad slugs, collisions, bad base branch)
  - Cleanup: clean removal, unregistered IDs, dirty worktree blocking, force-remove override
  - Round-trip: create → [work implied] → cleanup → verify purged

  All tests run in isolation with no side effects (temp repos auto-deleted).
  Exit: 0 = all passed, 1 = failures.

  **`scripts/cleanup-worktree.ps1` — `-Force` fix:**
  The `-Force` flag now **skips the dirty check**, allowing safe recovery removal
  of abandoned/corrupted worktrees. Prints confirmation and proceeds directly to
  `git worktree remove --force`.

  **Feature Status: COMPLETE**
  - Phase 1 ✅ Spec + documentation
  - Phase 2 ✅ Hard gates (pre-tool + post-merge hooks)
  - Phase 3 ✅ Bootstrap & cleanup scripts (setup-worktree, cleanup-worktree)
  - Phase 4 ✅ Integration tests (19 cases, 100% pass)
  All four phases deployed. Worktree workflow ready for production use.

---

## [1.18.11] -- 2026-04-14

### Added

- **Git Worktrees — Phase 3: Bootstrap & Cleanup Scripts.**

  **`scripts/setup-worktree.ps1/.sh`**
  Human-runnable script to bootstrap a new agent worktree.
  Reads `WORKTREE_DIR` / `WORKTREE_BRANCH_PREFIX` from `af-env.conf`.
  Steps: validates workflow ID slug, stale worktree audit + prune,
  path collision guard, base branch health check, `git worktree add`,
  venv bootstrap (symlink/junction to main `.venv`, or fresh install
  via `run-deps` if no shared venv), hooks accessibility check.
  Prints exact path + `code "<path>"` open command on success.

  **`scripts/cleanup-worktree.ps1/.sh`**
  Safe coordinator/human-runnable script to remove a worktree after merge.
  Steps: verifies worktree is registered in `git worktree list`,
  checks `git status --porcelain` (empty = clean), removal via
  `git worktree remove` (with optional `--force`), prune, verification.
  On dirty worktree: halts with actionable options (commit/discard/stash).
  On locked worktree: prints `git worktree unlock` command.

  **`.af-manifest`** — all 4 scripts registered.

  **Not yet implemented (Phase 4):** Integration tests.

---

## [1.18.10] -- 2026-04-14

### Added

- **Git Worktrees — Phase 2: Hard-Gate Hooks.**

  **`coordinator-pretooluse.ps1/.sh` — Worktree Creation Gate (HARD)**
  When the coordinator runs `git worktree add`, the hook validates:
  - Branch name matches `^agent/[a-z0-9-]+$` — rejects invalid slugs.
  - Worktree path does not already exist — prevents collision with running tasks.
  - Main repository is healthy (`git status` exit 0) — halts on corrupt repo state.
  On any violation: `deny` decision with a specific remediation message.

  **`test-writer-pretooluse.ps1/.sh` — Branch Context Proof (HARD)**
  Before any file edit/create, verifies `git branch --show-current` returns
  `agent/*`. Blocks if running on `main`, `dev`, or any non-agent branch.
  Error includes worktree setup reminder (Step 0d).

  **`refactorer-pretooluse.ps1/.sh` — Branch Context Proof (HARD)**
  Same check as test-writer. Applied before both the no-new-files gate
  and any file edit, so context is verified regardless of tool type.

  **`coordinator-postmerge.ps1/.sh` (new) — Worktree Audit at Session End**
  Fires on coordinator Stop event. Lists all active `agent/*` worktrees
  with their paths and branch names. Warns about prunable stale entries.
  Added to coordinator.agent.md Stop hooks.

  **`.af-manifest`** — `coordinator-postmerge.ps1/.sh` registered.

  **Not yet implemented (Phases 3–4):** `setup-worktree` and
  `cleanup-worktree` scripts; integration tests.

---

## [1.18.9] -- 2026-04-14

### Added

- **Git Worktrees — Phase 1: Spec & Skill.** Enables parallel agent task
  execution. Each `agent/{id}` task runs in an isolated `../wt/{id}` worktree
  backed by the shared `.git`. Human’s main checkout stays on `dev` and is
  never disturbed.

  **`git-workflow.instructions.md`**
  - Expanded Autonomy Boundary table: `git worktree add/remove/prune/list`
    are now coordinator-permitted local operations.
  - New section **Worktree Lifecycle:** path convention (`../wt/{id}`),
    Create / Work / Merge / Cleanup lifecycle, context proof requirements,
    stale worktree audit, and full recovery table (locked, dirty, diverged,
    stale, path collision).
  - New section **Worktree and VS Code:** how to open worktrees as workspace
    folders, `.gitignore` recommendations.

  **`coordinator.agent.md`**
  - New **Step 0d: Worktree Bootstrap** — creates the worktree before Red
    phase; reads `WORKTREE_DIR` from `af-env.conf`; checks for stale trees;
    records worktree path in plan metadata.
  - New **Step 8: Worktree Cleanup** — after human confirms merge; verifies
    clean status; removes + prunes; narrates result.
  - Subagent context injection now includes `Worktree: {path}` and
    `Branch: agent/{id}` so all agents know their execution context.
  - Phase Checkpoint #1 updated to show `git worktree add` as the canonical
    branch creation path.

  **`af-env.conf`** (template defaults)
  - `WORKTREE_DIR=../wt` — sibling path to avoid repo pollution.
  - `WORKTREE_BRANCH_PREFIX=agent` — consistent with existing branch convention.

  **`skills/git-worktrees/SKILL.md`** (new)
  - 7-section practical guide: concepts, key commands, lifecycle,
    troubleshooting (7 common problems + resolutions), verification
    patterns, configuration reference, `.gitignore` recommendations,
    limitations and edge cases (OneDrive, submodules, file watchers).

  **`skills/INDEX.md`** — entry #17; agent matrix entry for coordinator.
  **`copilot-instructions.md`** — skills table entry added.
  **`.af-manifest`** — `skills/git-worktrees/SKILL.md` registered.

  **Not yet implemented (Phases 2–4):** Hard-gate hooks for worktree
  creation preconditions and context proof; `setup-worktree` and
  `cleanup-worktree` scripts; integration tests. See
  `ideas/feature-git-worktrees.md` for the full roadmap.

---

## [1.18.8] -- 2026-04-14

### Fixed

- **Root cause: generic commit messages from test-writer and implementer.**
  The Phase-to-Commit Mapping table and Phase Checkpoints in
  `coordinator.agent.md` showed commit messages as **literal complete strings**
  (`"[agent:test-writer] failing tests"`) rather than templates requiring a
  colon-separated description. The coordinator followed the spec correctly —
  the spec was wrong.

### Changed

- **`git-workflow.instructions.md` — Phase-to-Commit Mapping:** All 5 phase
  messages now show mandatory `{description}` suffixes after a colon separator:
  `[agent:test-writer] failing tests: {module/suite — what scenarios are covered}`.
- **`git-workflow.instructions.md` — Commit Rule 4:** Tightened to require
  `[agent:name] {phase}: {description}` format. States that generic phase-only
  labels are rejected by the hook.
- **`coordinator.agent.md` — Phase Checkpoints:** All 7 phase commit message
  examples updated to show required `{description}` suffix.

### Added

- **Hard gate — `coordinator-pretooluse.ps1` and `.sh`:** `run_in_terminal`
  calls containing `git commit -m "..."` are now intercepted. The hook rejects
  commit messages that match `[agent:name] phase` with no `: {description}` of
  ≥ 10 chars. Exempt patterns: `WIP checkpoint`, `task cancelled`,
  `justify ignore` (already validated by their own gates). On rejection the
  coordinator receives a `deny` decision with the required format and a
  concrete example.
- **`coordinator-pretooluse.sh`:** The bash hook previously had no terminal
  interception at all (pytest block existed only in the PS1 version). This
  release adds full terminal handling parity: pytest block + commit message
  validation.

### Added

- **`check-python-quality.py` — `# noqa` hygiene:** Checker now enforces that
  every `# noqa` suppression includes an explicit rule code (`# noqa: E501`) and
  a justification comment of at least 8 characters. Mirrors existing
  `# type: ignore` and `# pyright: ignore` hygiene.
- **Atomic ignore commit enforcement (4 stop hooks):** `implementer-stop.ps1/sh`
  and `refactorer-stop.ps1/sh` now inspect the staged diff and block when:
  - More than one new ignore statement appears in the same commit.
  - A new ignore statement is bundled with other code changes.
  Agents receive a clear `block` decision with the required commit message
  format: `[agent:name] justify ignore: file:line RULE -- reason`.
- **Git Workflow Rule 6:** Added Commit Rule 6 to `git-workflow.instructions.md`
  formalising the standalone-commit requirement for every `# type: ignore`,
  `# pyright: ignore`, or `# noqa` added to production code.

---

## [1.18.6] -- 2026-04-07

### Removed

- **Hardcoded model definitions** — removed `model:` fields from all 10 worker
  agents (implementer, test-writer, refactorer, planner, code-critic, researcher,
  test-critic, arbiter, documenter, compliance-checker). Previously these listed
  tiered prioritized models (Tier 1-3) that required manual updates on company
  model releases.

### Changed

- **Model selection:** All agents now use the user's selected model in Copilot Chat.
  This eliminates maintenance burden and ensures zero downtime on model availability
  changes.
- **README:** Updated "Model Prioritization" section to explain new behavior and
  legacy reference.

### Rationale

- Company model updates happen frequently; hardcoding in 11 files created
  drift risk and maintenance overhead.
- User-driven model selection is simpler, more flexible (e.g., A/B testing,
  cost optimization), and future-proof.
- VS Code's fallback behavior handles unavailable models automatically.

## [1.18.5] -- 2026-04-07

### Changed

- **Hook configuration transition** — wire formerly orphaned hooks (block-dangerous,
  scan-secrets, session-context, stop-tests) into agent frontmatter instead of
  relying on `.json` files. Coordinator now enforces 4 lifecycle events (SessionStart,
  PreToolUse, PostToolUse, Stop). File-writing agents (implementer, test-writer,
  refactorer, documenter) now scan for secrets post-tool.
- **hooks/README.md** — document per-agent hooks as primary method, clarify JSON
  hooks are legacy fallbacks for future VS Code feature stabilization.

### Notes

- `agent-hooks.json` remains in place and is auto-generated if needed; it will
  not break if VS Code enables JSON loading in the future.
- All 4 orphaned hook scripts are now active via agent frontmatter.

## [1.18.4] -- 2026-04-01

### Removed

- **hook-utils.ps1** -- deleted. Custom trace logging replaced by VS Code's
  native `GitHub Copilot Chat Hooks.log` (zero runtime overhead).
- **Write-HookTrace calls in all 13 hooks** -- removed dot-source and all
  trace invocations. Scripts are now self-contained again.
- **Section 8 (trace telemetry) in test-hooks.ps1** -- 6 trace test cases
  removed. Total: 53 tests (down from 59).

### Added

- **test-hooks-integration.ps1** -- parses VS Code's native hook log to
  verify hooks actually fire. Supports `-All` (all sessions) and `-Verbose`
  (per-invocation detail). Detects orphaned scripts and confirms global
  hook non-firing.
- **Pytest terminal guard in coordinator-pretooluse.ps1** -- denies
  `run_in_terminal` when command matches `\bpytest\b|\bpy\.test\b`.
  Returns hint to use `execute/runTests` tool or predefined tasks.

### Fixed

- **refactorer-stop.ps1** -- fixed corrupted line containing literal `\n`
  embedded in source.

## [1.18.3] -- 2026-04-01

### Added

- **hook-utils.ps1** -- shared trace logging utility for all hooks. Writes
  JSONL entries to `.github/logs/hook-trace.jsonl` with timestamp, hook name,
  event type, tool name, and detail. Proves hooks fire during real agent runs.
- **Trace calls in all 13 hooks** -- dot-source `hook-utils.ps1` and log at
  decision points (deny/ask/block/warn) plus `invoked` events for stop hooks
  and session-context.
- **Trace verification in test-hooks.ps1** -- 6 new test cases confirm trace
  entries are written and valid JSON. Total: 54 tests.

### Fixed

- **test-writer-pretooluse.ps1** -- tool-name pattern `edit|create|write|file`
  falsely matched `readFile`, blocking the test-writer from reading production
  code. Tightened to `editFile|createFile|createDir|editNotebook`.
- **coordinator-pretooluse.ps1, scan-secrets.ps1** -- same pattern tightened
  for consistency (not exploitable due to earlier guards, but fragile).

## [1.18.2] -- 2026-04-01

### Added

- **test-hooks.ps1** -- integration test suite for all 13 Copilot agent hooks.
  Exercises PreToolUse (block-dangerous, coordinator, test-writer, refactorer,
  researcher), PostToolUse (scan-secrets), and edge cases (empty/malformed JSON).
  48 test cases. Task: `test: hooks`.

## [1.18.1] -- 2026-03-31

### Added

- **Tool audit system** — `audit-tools.ps1` script validates agent tool
  assignments against `tools-reference.txt` baseline and `TOOLS.md` matrix.
  Reports unknown, undocumented, and orphaned tools. Tasks: `audit: tools`,
  `audit: tools verbose`.
- **Extension tools assigned to agents** — `ms-toolsai.jupyter/configureNotebook`
  (implementer, refactorer, code-critic, test-writer),
  `ms-python.python/configurePythonEnvironment` (same 4),
  `vscode/askQuestions` (coordinator, planner),
  `vscode.mermaid-chat-features/renderMermaidDiagram` (planner, documenter),
  `ms-toolsai.jupyter/listNotebookPackages` (code-critic).
- **tools-reference.txt** expanded from 30 built-in to 43 registered tools
  (built-in + extension).

### Changed

- **TOOLS.md** — added extension tools and VS Code UI sections to matrix;
  updated exclusion tables with correct frontmatter keys.
- **audit-tools.ps1** — renamed "built-in" to "registered" to reflect
  built-in + extension coverage; fixed Unicode characters for PS 5.1.

### Fixed

- **deploy.ps1** — added version-stale detection: warns when deploying
  updated files without a VERSION bump (prevents silent version drift).

## [1.18.0] -- 2026-03-27

### Added

- **12 new skills from ai-dev-kit** — databricks-agent-bricks, databricks-apps,
  databricks-bundles, databricks-connect, databricks-dbsql, databricks-jobs,
  databricks-mlflow-eval, databricks-model-serving, databricks-sdp,
  databricks-synthetic-data, databricks-unity-catalog, python-dev.
  Available skills library expanded from 22 to 34.
- **validate-skills.py** — Automated skill validation script. Checks YAML
  frontmatter (name, description, argument-hint), directory-name consistency,
  and INDEX.md cross-references. Supports `--deep-available`, `--root`, `--ci`.
  Integrated into validate-framework.prompt.md step 7.

### Changed

- **data-pipeline-design skill enhanced** — Added medallion architecture,
  Delta Lake patterns, and Spark Streaming guidance.
- **secrets-management skill enhanced** — Added Databricks secret scopes
  and dbutils.secrets patterns.

### Fixed

- **deploy.ps1 skill INDEX.md protection** — Marked `skills/INDEX.md` as
  `[customizable]` in `.af-manifest`. Previously, deploy would overwrite
  project-specific skill activations with the AF template index.
- **deploy.ps1 stale activation warning** — Post-deploy check now warns
  when activated skills have a newer version in `_available/`.
- **validate-framework.prompt.md** — Step 7 now references the automated
  validation script as the preferred check method.

## [1.17.0] -- 2026-03-24

### Changed

- **README restructured for team distribution** — Two-tier layout: quick-start
  for newcomers (Why Use This → Prerequisites → Quick Setup → Your First Week)
  and collapsible deep-dive sections (File Map, Model Prioritization, Tool
  Configuration). Value proposition section added. Prerequisites moved before
  Quick Setup. "Adopting Incrementally" promoted to "Your First Week" with
  table format. Links bar with version badge, Changelog, and Troubleshooting.
- **Scope-aware test execution** — Agents now follow per-agent test budgets
  (implementer: 0× all-scope, test-writer: Red-phase only, refactorer: 1× all).
  Persistent `.github/test-log.json` tracks cumulative test results across
  sessions. Stop hooks invoke the canonical test runner script instead of raw
  pytest. Git-based change detection replaced hardcoded time limits for
  freshness checks.
- **Pure bash hook scripts** — Removed python3 dependency from all `.sh` hook
  scripts (`run-tests.sh`, `session-context.sh`, `implementer-stop.sh`,
  `refactorer-stop.sh`). Reimplemented JSON merging and date formatting with
  sed, tr, date, and printf.

### Fixed

- **Stop hooks now use canonical test runner** — `implementer-stop` and
  `refactorer-stop` hooks invoke `run-tests.ps1/.sh` instead of raw pytest,
  ensuring test-log.json is always populated (P0).
- **Implementer test budget contradiction** — Resolved conflict between
  "1× all" budget and "Do NOT run all" instruction; standardised on 0× all
  (P1).
- **git diff missing HEAD** — Added `HEAD` to all `git diff` commands in hook
  scripts to correctly detect staged and committed changes (P2).
- **Stale pytest commands in testing instructions** — Replaced raw pytest
  invocations with canonical runner references (P3).
- **Error summary chrome stripping** — Stop hooks now strip pytest `===` banner
  lines from error summaries injected into agent context (R1).
- **Known-schema comment** — Expanded documentation of sed JSON parsing safety
  assumptions in `run-tests.sh` (R3).

---

## [1.16.0] -- 2026-03-16

### Added

- **Idea 46 -- Task-Based Test Execution System** -- Back-ported from live
  project work. Agents now use pre-defined VS Code Tasks (`execute/runTask`)
  instead of calling pytest directly.

  - **Canonical test runner** -- `run-tests.ps1/.sh` wraps pytest with scope
    selection, coverage, fail-fast, output file, and PySpark stderr suppression.
  - **VS Code tasks** -- 12 test tasks, 5 git tasks, 3 lint tasks defined in
    `.vscode/tasks.json`. Agents invoke via `execute/runTask`.
  - **VS Code settings** -- `.vscode/settings.json` enables hook system
    (`chat.useCustomAgentHooks: true`) and pytest integration.
  - **Tool sets** -- `.vscode/tool-sets.jsonc` defines reusable tool groups
    (`reader`, `dev`, `python-analysis`, `python-environment`, `notebooks`).
  - **Agent tool grants** -- `execute/runTask` added to coordinator,
    implementer, refactorer, code-critic, test-critic, test-writer, documenter,
    planner. Implementer also gets `execute/createAndRunTask`.
  - **Testing instruction** -- New "Agent Test Execution" section with task
    table, phase-specific strategy, and 7 rules.

  **Files created (5):** `.vscode/settings.json`, `tasks.json`,
  `tool-sets.jsonc`, `scripts/run-tests.ps1`, `.sh`
  **Files modified (10):** 8 agent `.agent.md` files, `testing.instructions.md`,
  `.af-manifest`

- **Idea 41 -- Coordinator Delegation Enforcement Hooks** -- Three-layer
  safeguard preventing the coordinator from directly modifying files.

  **Background:** During live project work, the coordinator bypassed all
  workflows and directly edited 4 files. Investigation revealed the "never
  modify files" Cardinal Rule was enforced only by prose instruction -- no
  programmatic guard existed.

  - **Layer 1: PreToolUse hook (HARD deny)** -- `coordinator-pretooluse.ps1/.sh`
    blocks `editFiles`, `createFile`, `createDirectory` tool calls. Allows
    `runInTerminal` and all read/search tools. Deny message redirects to the
    correct subagent and workflow.
  - **Layer 2: PostToolUse hook (detective advisory)** --
    `coordinator-posttooluse.ps1/.sh` fires after terminal commands. Runs
    `git status --porcelain -- mpusage/ tests/` to detect indirect file writes
    via terminal escape hatch (`Set-Content`, `echo >`, `sed -i`). Injects
    warning via `additionalContext`.
  - **Layer 3: Prose (existing)** -- Cardinal Rule #1 reinforced by Layer 1
    deny messages.

  Scripts follow the established agent-scoped hook pattern from Idea 39
  (test-writer PreToolUse, refactorer PreToolUse). Coordinator is the 5th
  agent with scoped hooks.

  **Files created (4):** `coordinator-pretooluse.ps1`, `.sh`,
  `coordinator-posttooluse.ps1`, `.sh`
  **Files modified (1):** `coordinator.agent.md` (hooks frontmatter)

- **Idea 43 -- Remaining Hook Iteration 3 (37a + 39-H3)** -- Completed the
  two remaining low-priority hook tasks.

  - **37a: Provenance marker check in scan-secrets** -- Extended
    `scan-secrets.ps1/.sh` with a SOFT advisory that checks `.py` files for
    `copilot:generated|modified` markers in the first 5 lines. Emits JSON
    warning; does not block.
  - **39-H3: Researcher PreToolUse credential-URL scan** -- Created
    `researcher-pretooluse.ps1/.sh`. Scans `web/fetch` URLs for basic auth,
    token query params, credential fragments. WARN advisory only — allows
    fetch, shows sanitized URL. Researcher is now the 6th agent with scoped
    hooks.

  **Files created (2):** `researcher-pretooluse.ps1`, `.sh`
  **Files modified (4):** `scan-secrets.ps1`, `.sh`, `researcher.agent.md`,
  `.af-manifest`

### Changed

- **Open task re-evaluation** -- Reviewed all remaining open items from
  Ideas 14, 37, 39.
  - Dropped **37b** (branch advisory in SessionStart) -- superseded by 3
    existing layers of branch awareness.
  - Corrected **39-H8** (planner Stop hook) -- the Stop hook itself
    remains infeasible (conversational output, not hookable), but the
    original drop reasoning was wrong. Investigation revealed a latent
    plan persistence gap, resolved by Idea 42.
  - Retained **39-P4** (PreCompact checkpoint) at MEDIUM priority.
  - Retained **37a** (provenance in scan-secrets) and **39-H3** (researcher
    URL scan) at LOW priority.

### Fixed

- **Idea 42 -- Plan File Persistence Gap** -- Coordinator Step 1 instructed
  "persist as {type}-{date}-{slug}.md" but neither the coordinator (no
  `edit/*` tools, PreToolUse hook denies) nor the planner (read-only) could
  actually write the file. Latent contradiction since Idea 35, masked until
  Idea 41 added programmatic enforcement.
  - Coordinator Step 1 now delegates plan file creation to the **documenter**.
  - Quick Fix investigation doc creation also delegated to documenter.
  - Documenter gained Responsibility #1 "Persist plan files when delegated";
    existing responsibilities renumbered #2--#6.
  - **Files modified (2):** `coordinator.agent.md`, `documenter.agent.md`

- **Idea 44 -- Coordinator PreToolUse False-Positive Fix** -- The `file`
  pattern in the coordinator hook matched read-only tools (`read_file`,
  `readFile`, `fileSearch`) causing false-positive denials. Added a
  read-only tool allowlist (`read|search|find|list|get|problems`) that
  exits early before the `file` catch-all. 14/14 tool scenarios pass.
  - **Files modified (2):** `coordinator-pretooluse.ps1`, `.sh`

- **Idea 45 -- Hook-Agent Alignment Audit** -- Cross-referenced all 11 agent
  tool definitions against hook enforcement, workflow semantics, and quality
  gates.
  - Removed `edit/createFile` + `edit/createDirectory` from refactorer tools
    (hook already blocks them — model was wasting turns).
  - Standardized researcher hook YAML format to match all other agents.
  - Added provenance marker check to `implementer-stop` as a HARD gate
    (quality-gates.instructions.md said HARD but only SOFT WARN existed).
  - HARD gate hook coverage improved from 56% (9/16) to 69% (11/16).
  - **Files modified (4):** `refactorer.agent.md`, `researcher.agent.md`,
    `implementer-stop.ps1`, `.sh`

---

## [1.15.0] -- 2026-03-11

### Changed

- **Idea 40 -- Deploy Mechanism Improvements** — Comprehensive overhaul of both
  deploy scripts (`deploy.ps1` and `deploy.sh`) based on peer review (planner +
  code-critic). All improvements applied to both scripts for full parity.

  - **D2: Fix -Diff exit code bug** — `-Diff` mode now wrapped in try/catch
    (PowerShell) to prevent `$ErrorActionPreference = 'Stop'` from converting
    non-terminating errors into exit code 1. Explicit `exit 0` added at end of
    both Diff and Deploy modes.

  - **D3+D9: Manifest annotation system** — `.af-manifest` now supports
    annotations at end of line: `path  [annotation1, annotation2]`. Three
    annotations defined:
    - `[customizable]` — file contains project-specific content; protected on update
    - `[optional]` — directory or file may not exist in AF source; no warning
    - `[vscode]` — file deployed to `.vscode/` instead of `.github/`
    Eliminates hardcoded `$CustomizableFiles` array and hardcoded `.vscode/toolsets.jsonc`
    special case. Both are now driven entirely by manifest annotations.

  - **D4: Content diff on CONFLICT** — When a CONFLICT is detected (both AF and
    project changed), `Show-ContentDiff` / `show_content_diff` displays up to 15
    lines of diff output. Uses `git diff --no-index` when available, falls back to
    `Compare-Object` (PowerShell) or `diff -u` (bash).

  - **D5: Manifest validation** — After parsing, deploy scripts warn about manifest
    entries pointing to missing directories or files. `[optional]` entries are
    silently skipped. Catches manifest drift early.

  - **D6: Ephemeral backup** — Before overwriting files (UPDATE or Force), copies
    the existing file to `.af-backup-{timestamp}/`. If deploy completes with 0
    conflicts, the backup directory is automatically deleted. If conflicts remain,
    the backup persists with its path printed in the summary.

  - **D8: Bash parity** — `deploy.sh` completely rewritten to match `deploy.ps1`
    capabilities: full 3-way merge via `.af-hashes`, `--update-hashes` mode,
    PRESERVE/CONFLICT states, manifest annotation parsing, content diff on
    conflict, manifest validation, and ephemeral backup. Previously, `deploy.sh`
    had no 3-way merge and silently overwrote project customizations (data loss
    risk for UC2 on Linux/macOS).

  - **Customizable file handling improved** — Customizable files now participate
    in 3-way merge to provide better status messages:
    - AF changed, project unchanged → `PROTECT (AF has changes -- review manually)`
    - AF unchanged, project changed → `PRESERVE (project customization)`
    - Both changed → `CONFLICT` with content diff
    Previously all cases showed generic `PROTECT` message.

## [1.14.0] -- 2026-03-11

- **Idea 39 Iteration 2 -- Agent-Scoped Phase Gate Expansion** -- Adds
  machine-verified phase gates to test-writer, refactorer, and documenter.
  - **`test-writer:SubagentStop`** (P1a + H5) — Red phase gate: blocks if all
    tests pass (tests must FAIL to prove a requirement gap). Also checks
    provenance markers on newly created test files.
  - **`test-writer:PreToolUse`** (H2) — TDD phase isolation: blocks the
    test-writer from editing production code under `mpusage/`. Prevents the
    most fundamental TDD invariant violation.
  - **`refactorer:SubagentStop`** (H1) — Refactor phase gate: blocks if tests
    fail OR if new `.py` files were created under `mpusage/`/`tests/`. Scoped
    `git status` to avoid false positives on pre-existing untracked files.
  - **`refactorer:PreToolUse`** (H4) — Preventative layer: blocks
    `createFile`/`createDirectory` calls. Defence-in-depth with Stop hook.
  - **`documenter:SubagentStop`** (P1c) — Artifact gate: blocks documenter if
    workflow log YAML or retro snippet is missing for the current workflow-id.
  - Peer-reviewed: planner (6 new proposals) + code-critic (4 approved,
    1 approved with conditions, 1 rejected). H6 rejected (SubagentStart
    routing unverified, redundant with coordinator prompting).
  - Global Stop hook Gate 2 (workflow artifacts advisory) now complemented
    by documenter:SubagentStop hard gate — Gate 2 retained as session-end
    safety net.
  - **VS Code `Stop` event bug:** `Stop` hooks in `.agent.md` frontmatter
    crash subagent invocation. 7 of 8 events work; only `Stop` is broken.
    **Workaround:** use `SubagentStop` instead of `Stop` — functionally
    equivalent for subagent-only agents. All agents verified working.

## [1.13.0] -- 2026-03-11

### Added

- **Idea 39 -- Agent-Scoped Hooks (Iteration 1: Green Gate)** -- VS Code now
  supports hooks in `.agent.md` frontmatter that fire only when that agent is
  active. An agent's `Stop` hook should fire as `SubagentStop` when invoked as
  a subagent, but a VS Code bug crashes `Stop`; use `SubagentStop` instead.
  - **New `implementer:SubagentStop` hook scripts** (`implementer-stop.ps1/.sh`)
    — runs the test suite when the implementer subagent completes. Blocks the
    implementer from returning if tests fail (Green phase gate).
  - **Global Stop hook Gate 1 retired** — pytest enforcement removed from
    `stop-tests.ps1/.sh` (handled by per-agent SubagentStop hook at phase exit).
    Global Stop hook retains Gate 2 (workflow artifact advisory).
  - **`implementer.agent.md`** updated with `hooks.SubagentStop` in YAML
    frontmatter.
  - Requires `chat.useCustomAgentHooks: true` in `.vscode/settings.json`.
  - Peer-reviewed: planner (8 proposals) + code-critic (3 rejected, 3 approved
    with conditions, 1 deferred). P1b unanimously approved as highest ROI.

### Future iterations (from peer discussion)

- **P1a** `test-writer:Stop` — Red gate (tests must FAIL).
- **P1c** `documenter:Stop` — artifact existence gate.
- **P4** `coordinator:PreCompact` — workflow checkpoint before context compaction.

---

## [1.12.0] -- 2026-03-10

### Added

- **Idea 37 -- Bookend Compliance Pattern** -- New `compliance-checker` agent
  (11th agent) acts as a mandatory workflow watchdog. Invoked at two bookend
  checkpoints: pre-flight (before Step 1) and post-flight (after Step 7).
  - **Pre-flight checks:** branch not on main/master, plan directory resolved,
    WIP state consistent.
  - **Post-flight checks:** plan file marked COMPLETED, workflow log YAML
    exists, retro snippet exists, provenance markers present. Reports missing
    artifacts to the coordinator — the coordinator handles remediation by
    invoking the documenter (only it has the full workflow context).
  - **Read-only design:** compliance-checker detects gaps but never creates
    files. The documenter needs rich context (step summaries, critic findings,
    metrics) that only exists in the coordinator's conversation history.
  - **Stop hook enhanced** (Layer 3 safety net): `stop-tests.ps1` and
    `stop-tests.sh` now also check for workflow artifacts (log YAML, retro
    snippet, plan status) at session end. Emits advisory WARNING if missing
    — does not block.
  - **3-layer enforcement model:** (1) Coordinator instructions → (2)
    Compliance-checker bookends → (3) Stop hook detection. Each layer
    catches failures the previous layer missed.
  - Updated coordinator workflow diagrams, state machine, phase checkpoints,
    and narration examples.
  - Added compliance-checker exit gates to quality-gates.instructions.md.
  - Updated MANIFEST.md, README.md, skills/INDEX.md.

---

## [1.11.0] -- 2026-03-10

### Changed

- **Idea 38 -- Autonomous Local Git Execution** -- Coordinator now executes
  local git operations (branch creation, staging, committing) at reviewed
  checkpoints. Remote and destructive operations remain human-controlled.
  Unanimously approved by planner + code-critic peer discussion.
  - **Cardinal Rule replaced** with local/remote principle in
    `git-workflow.instructions.md`. Local git is coordinator-executed;
    remote git is human-controlled.
  - **Coordinator agent** gains permitted-command list, branch guard
    (never commit on main/master), explicit staging rules, and
    post-command verification protocol.
  - **Block-dangerous hook** expanded: `git push` (any form), `git merge`,
    `git branch -d/-D`, `git rebase` now trigger confirmation prompt.
    Previously only `--force` push and `--hard` reset were blocked.
  - **Documenter** no longer suggests git commits (responsibility fully
    moved to coordinator).
  - **MANIFEST.md** §7 Git Conventions updated to reflect two-tier model.

---

## [1.10.0] -- 2026-03-10

### Added

- **Idea 36 -- Researcher Agent** -- New 10th agent (`researcher.agent.md`)
  for external research and domain expertise. Unanimously approved by planner
  + code-critic peer discussion.
  - **Role:** Fetch and synthesize external documentation — third-party APIs,
    versioned library docs, external standards not in the codebase or skills.
  - **Tool profile:** Read-only + `fetch`. No write access. Most constrained
    agent in the framework.
  - **User-invocable:** Yes — standalone domain questions and coordinator
    pre-flight research.
  - **Coordinator integration:** Conditional pre-flight step before planner.
    Invoked only when task involves external APIs/libraries/standards not
    covered by existing skills. Anti-invocation rules prevent over-use.
  - **Security:** Structured artifact output only (no raw content forwarding),
    no autonomous URL following, source scope constraints. Human review gate
    for Standard+ tiers.
  - **Quality gates:** 3 HARD (citations, no secrets, structured output),
    1 SOFT (source authority), 1 ADVISORY (retrieval timestamps).
  - **Skills assigned:** data-pipeline-design, data-modeling, data-quality.

### Changed

- **coordinator.agent.md** -- Added researcher to agents list, Worker Agents
  table, workflow diagram. Added "Research Pre-Flight" section with invocation
  criteria and anti-invocation rules.
- **MANIFEST.md** -- Added researcher to Worker Agent Roles and Handoff Data
  Requirements tables.
- **skills/INDEX.md** -- Added researcher to Agent Skill Matrix.
- **quality-gates.instructions.md** -- Added Researcher per-agent exit gates.
- **README.md** -- Agent count 9→10, added researcher to file map.

## [1.9.0] -- 2026-03-10

### Changed

- **Idea 35 -- Plan and WIP Artefact Redesign** -- Plans and WIP files now
  follow clear naming, location, and lifecycle conventions.
  - **Plan naming:** unique per-workflow filenames using
    `{type}-{YYYY-MM-DD}-{slug}.md` (e.g., `feat-2026-03-10-bucketing-v2.md`).
    Type prefix: `feat`, `fix`, `refactor`, `adr`, `review`.
    Slug derived from branch name.
  - **Plan location:** `docs/plans/` (default). Coordinator discovers existing
    conventions at Step 0 (e.g., `docs/designs/`, `docs/rfcs/`).
  - **WIP naming:** keeps literal `WIP.md` (ephemeral, easy to find).
  - **WIP location:** `docs/plans/WIP.md` (co-located with plans, not project root).
  - **Coordinator determines filename** (knows date + branch name).
  - **Archival eliminated:** plans live in their final location from creation.
    Removed unimplemented "archives to `.github/logs/`" step.
  - **WIP template:** added `Plan File` reference field so `/af-resume` can
    locate the associated plan.
  - **Convention discovery:** coordinator Step 0 checks for existing `docs/`
    structure before defaulting.

### Files Modified (12)

- `agents/coordinator.agent.md` -- Step 0 convention discovery, Step 1 plan
  naming logic, Session Interruption WIP path
- `agents/planner.agent.md` -- return format mentions unique filenames
- `agents/documenter.agent.md` -- references plan file path instead of PLAN.md
- `instructions/git-workflow.instructions.md` -- naming convention, location,
  WIP section, archival removed
- `instructions/quality-gates.instructions.md` -- plan file references
- `MANIFEST.md` -- Planning Documents section, artifact lifecycle table,
  handoff data table
- `prompts/resume.prompt.md` -- WIP discovery in docs/plans/
- `prompts/draft-pr-description.prompt.md` -- plan file in docs/plans/
- `prompts/simulate.prompt.md` -- plan file reference
- `TROUBLESHOOTING.md` -- WIP.md location guidance
- `templates/PLAN.md` -- naming convention comments
- `templates/WIP.md` -- Plan File field, location comments

## [1.8.0] -- 2026-03-10

### Added

- **Idea 34 — AF Deployment Scripts** — Created `deploy.ps1` (Windows) and
  `deploy.sh` (macOS/Linux) for safe, repeatable AF deployment into projects.
  - Install mode: copies AF-owned files to project `.github/` + `.vscode/`
  - Dry-run mode (`-DryRun`/`--dry-run`): preview changes without writing
  - Diff mode (`-Diff`/`--diff`): bidirectional comparison for both UC1
    (update check) and UC2 (feedback collection)
  - Force mode (`-Force`/`--force`): overwrite customized files
  - Customizable file protection: `copilot-instructions.md` and
    `architecture.instructions.md` are never overwritten on update
  - Version tracking via `.github/.af-version`

### Changed

- **README.md** — Quick Setup now references deploy scripts instead of manual
  copy. Manual instructions preserved as collapsible fallback. Added
  "Updating the AF" subsection. Deploy scripts added to file map.
- **`.af-manifest`** — Added `.af-manifest` and `.af-version` as deployment
  metadata entries.

---

## [1.7.3] — 2026-03-10

### Changed

- **U-08 — Workflow-lifecycle merged into coordinator** — Deleted standalone
  `instructions/workflow-lifecycle.instructions.md` (~120 lines, `applyTo: **`).
  All unique content merged into `coordinator.agent.md`:
  - Workflow States table + state transition diagram added to Execution Protocol
  - Session Interruption enhanced with detailed 6-step checkpoint protocol
    (commit in-progress changes, use template, include step history)
  - Task Cancellation enhanced with PR preservation and branch cleanup steps
  - Escalation handling and resume logic were already present — no duplication
  Savings: ~120 lines no longer loaded for every non-coordinator agent.

### Removed

- `instructions/workflow-lifecycle.instructions.md` — content lives in
  coordinator.agent.md (the only consumer).

---

## [1.7.2] — 2026-03-10

### Changed

- **U-01 — Arbiter tool contradiction resolved** — Removed `test-runner` from
  arbiter’s tool list; updated description to say "does NOT modify files or
  run tests." Coordinator Worker Agents table updated to "Read-only advisory."
  Body already said "No execution — do NOT run tests"; now frontmatter agrees.
- **U-02 — Planner read-only wording clarified** — Body constraint changed
  from "read-only tools only" to "read-only for files" with explicit note that
  terminal commands and test-failure inspection are allowed for analysis.
- **U-03 — Skill table completed** — copilot-instructions.md skill table
  expanded from 9 skills to all 16 active skills with correct consumer
  mappings. Added cross-reference to `skills/INDEX.md` as canonical source.
- **U-04 — Gate Summary aligned** — MANIFEST § 13 Gate Summary template now
  includes the `Skills Read:` line, matching quality-gates.instructions.md.
- **U-05 — Pre-Delivery Checklist deduplication** — MANIFEST § 11 body
  replaced with a single-source-of-truth pointer to copilot-instructions.md
  § Pre-Delivery Checklist, eliminating the duplicate that had already drifted.

---

## [1.7.1] — 2026-03-10

### Changed

- **G-07 — Secret scan hardened** — PostToolUse secret-scan hook now exits
  with code 1 (blocking) when secrets are detected. Previously advisory-only
  (exit 0), which contradicted MANIFEST § 5 Gate 4 (HARD security gate).
  Both `.ps1` and `.sh` scripts updated.
- **G-06 — CVE scanning operationalized** — Code-critic Step 6 now instructs
  running `pip-audit` in terminal when new dependencies are added. R-SD-12
  mapping in MANIFEST § 12 updated to reference `pip-audit`.
- **G-10 — Layer override exemption** — Pure documentation changes (docstrings,
  comments) in domain core files no longer trigger the Standard tier override.
  Only logic changes count.

### Added

- **G-02 — Early-exit logging** — Coordinator writes a minimal YAML log
  when a workflow fails before Step 7, ensuring steps 1–6 are not lost.
- **G-03 — R-SD-23 cross-reference** — `provenance.instructions.md` now
  references governance L1 Principle 3 and domain rule R-SD-23.
- **G-04 — Mutation testing labeled** — MANIFEST § 2 Tier 3 (mutation tests)
  explicitly labeled as aspirational with a note about future tooling.
- **G-09 — Governance action items** — Documenter retro snippets gain a
  `## Governance Action` section for proposing workflow/governance
  improvements with affected L2 rule or AF element.
- **G-11 — R-SD-03 mapped** — Added R-SD-03 (code review scope) to
  MANIFEST § 12 cross-reference table, mapped to code-critic Steps 1–7.
- **G-12 — Lockfile check** — Code-critic Step 6 now checks for lockfile
  presence when new dependencies are added (R-SD-10).

### Fixed

- **G-01 — toolsets.jsonc** — Confirmed to exist at `.vscode/toolsets.jsonc`
  (was missed in audit due to gitignored path). No action needed.
- **G-05 — Context budget RED** — Already mandates halt ("HARD gate — Do NOT
  continue"); confirmed correct after Idea 31 recalibration.
- **G-08 — Credential scoping** — Already acknowledged as open gap in
  MANIFEST § 7. No action until CI/CD integration.

---

## [1.7.0] — 2026-03-09

### Added

- **Idea 29 — Skill Pruning** — 22 unassigned skills moved to
  `skills/_available/`. INDEX.md split into "Active Skills (16)" and
  "Available for Activation (22)". `/af-validate-framework` deep-scans only
  active skills (light scan for `_available/`). `/af-onboard-project` evaluates
  available skills against project tech stack and recommends activation.
- **Idea 30 — Non-Destructive Install** — `.af-manifest` created listing
  AF-owned paths. README Quick Setup documents file ownership boundary (AF
  does NOT overwrite workflows, CODEOWNERS, dependabot.yml). `/af-onboard-project`
  gains conflict detection (Steps 7-8): enumerates existing `.github/` files,
  offers to merge `copilot-instructions.md`, respects ownership boundary.
- **Idea 31 — Token Budget Feasibility** — Context budget heuristics
  recalibrated: ≥7 calls → YELLOW, ≥10 → RED (was ≥5/≥7, which triggered
  RED on every normal Full TDD workflow). `/af-simulate` gains Context
  Feasibility section (SINGLE-SESSION / MULTI-SESSION / AT-RISK). Advisory
  (SOFT) — does not block execution.
- **Idea 33 — Gate Audit Trail** — Coordinator cross-references gate claims
  against actual tool invocations. Unverifiable HARD gate claims downgraded
  to BLOCKED. Standard tier: SOFT enforcement. Deep tier: HARD enforcement.
  Narrated via progress protocol.

---

## [1.6.0] — 2026-03-09

### Added

- **Idea 24 — Supervised Execution Mode** — New `--supervised` flag for
  coordinator. Pauses after each step, presents output summary + verdict +
  gate summary, and waits for human "continue" or feedback. Trust ramp:
  simulate → supervised → autonomous.
- **Idea 27 — Partial Failure State Machine** — Workflow states enum
  (PLANNING through COMPLETED, FAILED_{step}, SKIPPED_{step}) documented
  in `workflow-lifecycle.instructions.md`. WIP.md template gains Step
  History table with per-step state, retry count, and outcome. Final
  Report gains Workflow Health section (skipped steps, retries, degraded
  gates).
- **Idea 28 — Skill Compliance Gate** — `Skills Read:` line added as SOFT
  gate for producer agents (test-writer, implementer, refactorer) in
  `quality-gates.instructions.md`. Critic flags missing/empty declarations.
  Gate Summary format updated with `Skills Read` field.

---

## [1.5.0] — 2026-03-09

### Added

- **Idea 22 — Smoke Test Playbook** — New `/af-smoke-test` slash command runs a
  canned `clamp(value, lo, hi)` task through the full TDD pipeline. Per-step
  health report (PASS/FAIL/SKIPPED) with raw output on failures. Disposable
  `agent/smoke-test` branch. References TROUBLESHOOTING.md on failure.
- **Idea 32 — Human Troubleshooting Guide** — New `TROUBLESHOOTING.md` with
  symptom → cause → fix tables covering: setup issues, workflow selection,
  subagent failures, gate failures, escalation, resume, and hook issues.
  Written for the human project owner, no agent jargon.

---

## [1.4.0] — 2026-03-09

### Added

- **Idea 25 — Verdict Parsing Hardening** — Coordinator now parses verdicts
  defensively: case-insensitive search, accepts any formatting, unparseable
  verdicts treated as BLOCKED (never silently APPROVED). MANIFEST § 13
  updated to document defensive parsing.
- **Idea 26 — Rejection Feedback Contract** — MANIFEST § 13 gains a
  Rejection Feedback Contract (findings, blocking_count, retry_guidance).
  Coordinator validates rejection fields before re-invoking makers. Both
  critic agents (code-critic, test-critic) updated with severity-tagged
  findings and rejection detail section in return format.
- **Idea 23 — Progress Narration Protocol** — Coordinator emits structured
  one-line status updates after each subagent returns. Emoji-coded step
  progress with verdict, retry count, and context budget indicators.

---

## [1.3.1] — 2026-03-09

### Added

- **Ideas 22–33** — 12 new improvement ideas from team brainstorm (planner,
  code-critic, test-critic). Organised into 4 implementation phases:
  Phase 1 (pre-flight): verdict hardening, rejection feedback, narration.
  Phase 2 (first run): smoke test, troubleshooting guide.
  Phase 3 (trust): supervised mode, state machine, skill compliance.
  Phase 4 (maturity): skill pruning, install safety, token feasibility, audit trail.

---

## [1.3.0] — 2026-03-09

### Summary

Autonomy review (Idea 20). Peer-reviewed by planner + code-critic. Addressed
the key gap: subagents ran under-informed because the coordinator didn't inject
skills, thresholds, or retro context into prompts.

### Added

- **Subagent Context Injection** — coordinator prepends a structured context
  block to every subagent prompt: complexity tier, target layers, quality
  thresholds, retro lessons, and skill-read reminders (A1 + A2)
- **Prompt taxonomy** — README now classifies 12 prompts into 3 tiers:
  workflow entry points (coordinator-routed), post-workflow reporting, and
  standalone utilities (A3)

### Changed

- **`coordinator.agent.md`** — all 7 subagent prompt templates now include
  `{context_block}` with tier, thresholds, layers, retro lessons, and
  explicit skill-read instructions; retro consultation now unconditional
  across all workflows (was Full TDD only); updated description to reflect
  primary entry point role
- **`prompts/resume.prompt.md`** — added `agent: coordinator` to route
  through coordinator Step 0 instead of standalone discovery (A5)
- **`prompts/validate-framework.prompt.md`** — Step 2 now flags uncustomized
  `applyTo` defaults like `src/**/*.py` as WARN (A6)
- **`README.md`** — slash commands section reorganised into 3-tier taxonomy

### Design Decisions

- **GOVERNANCE.md NOT auto-injected** — 300+ lines would waste context budget.
  Relevant rules are embedded in agent prompts and critic checklists. Drift
  risk mitigated by `/af-validate-framework`.
- **Standalone utility prompts kept standalone** — `/af-audit-config`,
  `/af-validate-framework`, `/af-find-skill`, `/af-simulate`, `/af-onboard-project`,
  `/af-retro-summary` are legitimately user-triggered maintenance operations
  that don't need coordinator orchestration.
- **Git stays human-controlled** — L1 §7 (Least Privilege). No change.

---

## [1.2.0] — 2026-03-09

### Summary

Governance audit of all 9 L1 Core Principles. Three-agent parallel review
(planner, code-critic, test-critic) produced 12 recommendations — all
implemented. Hook coverage expanded from 2 → 4 lifecycle events.

### Added

- **PostToolUse hook** — `scan-secrets.ps1/.sh` scans edited files for
  hardcoded secrets using gitleaks or regex fallback (advisory, never blocks)
- **Stop hook** — `stop-tests.ps1/.sh` runs `pytest tests/ -q --tb=line`
  before session ends with graceful fallback
- **Worker Uncertainty Protocol** — BLOCKED status format with structured
  triggers added to test-writer, implementer, refactorer
- **Over-engineering check** — added to code-critic Step 4 checklist

### Changed

- **`agent-hooks.json`** — 4 active hooks (was 2): SessionStart, PreToolUse,
  PostToolUse, Stop
- **`coordinator.agent.md`** — Step 0 reads `retros/auto/` for Full TDD
  workflows; Step 7 trivial tier skips documenter subagent
- **`documenter.agent.md`** — YAML log schema gains `review_details` field
  for persisting critic findings (severity, description, resolution)
- **`implementer.agent.md`** — removed `web/fetch` tool; added
  `human-escalation` skill
- **`test-writer.agent.md`** — added `human-escalation` skill
- **`refactorer.agent.md`** — added `human-escalation` skill
- **`quality-gates.instructions.md`** — retro snippet generation promoted
  to HARD gate for documenter
- **`skills/INDEX.md`** — `human-escalation` references updated (arbiter →
  test-writer, implementer, refactorer, arbiter)
- **`GOVERNANCE.md`** — R-SD-26 corrected: "present structured escalation
  summary" replaces "generate ESCALATION.md"
- **`MANIFEST.md`** — hooks table reflects 4 active hooks; credential
  scoping (R-SD-21/22) documented as deferred open gap
- **`README.md`** — hooks file tree and summary table updated

### Governance Audit Results

All 9 L1 Core Principles scored **PARTIALLY ENFORCED** — strong design but
enforcement relied on prompt guidance, not deterministic checks. The 12
recommendations address the gaps:

| # | Principle | Recommendation |
|---|---|---|
| R1 | Verifiability | Activate Stop hook (test gate) |
| R2 | Safety | Activate PostToolUse hook (secret scan) |
| R3 | Transparency | Persist critic findings in YAML log |
| R4 | Fail-Safe | Worker Uncertainty Protocol |
| R5 | Fail-Safe | Human-escalation skill for all producers |
| R6 | Continuous Improvement | Retro snippet as HARD gate |
| R7 | Continuous Improvement | Coordinator retro consultation |
| R8 | Separation of Concern | Fix R-SD-26 ESCALATION.md reference |
| R9 | Efficiency | Trivial tier minimal doc path |
| R10 | Least Privilege | Remove web/fetch from implementer |
| R11 | Least Privilege | Document credential scoping gap |
| R12 | Review | Over-engineering check for code-critic |

---

## [1.1.0] — 2025-07-16

### Summary

Batch 2 and 3 improvements — new prompts, workflow memory, context awareness,
skill discoverability, and versioning infrastructure.

### Added

- **`/af-draft-pr-description`** prompt — generate PR text from PLAN.md + YAML log
  + gate summary (Idea 13)
- **`/af-find-skill`** prompt — semantic search across the skill library (Idea 17)
- **`skills/INDEX.md`** — auto-generated index of all 38 skills with agent
  matrix and unassigned skills list (Idea 17)
- **`/af-retro-summary`** prompt — pull-model aggregator for workflow lessons (Idea 11)
- **`/af-resume`** prompt — discover paused workflows from WIP.md files (Idea 16)
- **`/af-audit-config`** prompt — detect drift between AF config and project state (Idea 12)
- **`/af-simulate`** prompt — dry-run workflow prediction without execution (Idea 19)
- **`VERSION`** file and **`CHANGELOG.md`** — semver tracking (Idea 18)
- **Context Budget Awareness** — GREEN/YELLOW/RED self-assessment protocol in
  coordinator with HARD gate on RED (Idea 15)
- **Retro snippet generation** — documenter auto-generates `retros/auto/{id}.md`
  after each workflow (Idea 11)

### Changed

- **`coordinator.agent.md`** — added Context Budget Awareness section
- **`documenter.agent.md`** — added responsibility #5 (retro snippet),
  expanded write permissions to `retros/auto/`, added return format entry

### Deferred

- **Idea 14** (Custom Workflow Definitions) — deferred until existing workflows
  have been exercised ≥3 times end-to-end

### Ideas Completed

| Idea | Summary |
|---|---|
| 11 | Workflow Memory & Auto-Retro (pull model) |
| 12 | Config Drift Detection (`/af-audit-config`) |
| 13 | CI/PR Integration (`/af-draft-pr-description`) |
| 14 | Custom Workflows — DEFERRED |
| 15 | Context Budget Awareness |
| 16 | Workflow Resume (`/af-resume`) |
| 17 | Skill Discovery Index (`/af-find-skill`) |
| 18 | Framework Versioning & Changelog |
| 19 | Dry-Run / Simulation (`/af-simulate`) |

---

## [1.0.0] — 2026-03-09

### Summary

Initial release after completing Ideas 1–10. The framework is self-contained,
internally consistent, and ready for adoption.

### Added

- **9 agents** — coordinator + 8 generic workers (planner, test-writer,
  test-critic, implementer, refactorer, code-critic, arbiter, documenter)
- **38 skills** — domain knowledge modules referenced by agents on demand
- **7 instructions** — auto-applied rules (architecture, copilot-authoring,
  git-workflow, provenance, quality-gates, testing, workflow-lifecycle)
- **6 prompts** — slash commands (onboard-project, validate-framework,
  tdd-feature, quick-fix, review-code, workflow-summary)
- **2 templates** — PLAN.md, WIP.md
- **Hooks** — SessionStart (git context), PreToolUse (formatter/linter)
- **GOVERNANCE.md** — L1 Core Principles, Meta-Rules, L2 Domain Rules (R-SD-01
  through R-SD-27), L3 Workflow definitions
- **MANIFEST.md** — 13 sections covering TDD, architecture, maker-checker,
  quality gates, escalation, git conventions, hooks, model prioritisation,
  tool sets, pre-delivery checklist, governing rules cross-reference,
  inter-agent contracts
- **Quality gate system** — HARD/SOFT/ADVISORY taxonomy, Trivial/Standard/Deep
  complexity tiers, per-agent exit gate tables, Gate Summary reporting format

### Foundation (Ideas 1–10)

| Idea | Summary |
|---|---|
| 1 | AF self-contained — zero AF references |
| 2a | Git workflow with atomic commits |
| 2b | Persisted planning documents (PLAN.md) |
| 3 | Structural peer review — all file types validated |
| 4 | Automated project onboarding (`/af-onboard-project`) |
| 5 | Pydantic skill for Python domain models |
| 6 | Dynamic agent creation → WONTFIX |
| 7 | Agents generic — shells + skill references |
| 8 | Documentation/logging streamlining + inter-agent contracts |
| 9 | Quality gate system — taxonomy, tiers, per-agent exit gates |
| 10 | AF self-validation (`/af-validate-framework`) |

