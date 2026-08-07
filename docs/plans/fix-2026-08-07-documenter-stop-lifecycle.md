<!-- copilot:generated | documenter | 2026-08-07 -->

# Fix: the documenter's Stop gate knew only one question (issue #72)

- **Status:** COMPLETED
- **Issue:** [#72](https://github.com/sefalk/AgenticAIGovernance/issues/72)
- **Branch:** `agent/72-documenter-stop-lifecycle`
- **Complexity tier:** Standard
- **Date:** 2026-08-07

## Problem

`documenter.agent.md` charters the documenter with two incompatible lifecycles:

- Responsibility 1 — persist plan files **mid-workflow** (Step 1 of Full TDD).
- Responsibilities 2-6 — **finalise**: plan status COMPLETED, workflow log,
  provenance check, architecture docs, retro.

`documenter-stop` fired on every invocation and blocked unless
`.github/logs/{id}.yaml` and `retros/auto/{id}.md` already existed. Its only
escape was "not on an `agent/` branch", which never applies during a workflow.

So a mid-workflow documenter call had exactly one way to terminate: write a
workflow log marked `status: COMPLETED`, and a retro, for a workflow that was
still running. The gate did not merely permit the fabrication — it compelled
it. Observed three times in a consumer project (AF 1.21.43), most recently
emitting `.github/logs/3111-*.yaml` and `retros/auto/3111-*.md` marked
COMPLETED with two subtasks outstanding.

Three things made the damage durable:

1. The compliance-checker's post-flight HARD gate checked that the artifacts
   *exist*. A file written to satisfy a hook satisfies an existence check
   perfectly, so the one gate that runs once and could have caught this
   passed vacuously.
2. The artifacts are invisible in review: `.github/` is gitignored in target
   projects, and `documenter.agent.md` forbids staging `logs/` and
   `retros/auto/`. Nothing reaches a pull request.
3. The premature retro enters the coordinator's retro feedback loop as if it
   were a lesson from a finished workflow.

And `stop-tests` treated the identical missing-artifact condition as a
WARNING, so the framework disagreed with itself about how serious it was.

## Change

A Stop hook receives `session_id` and `transcript_path` on stdin and nothing
else. The invocation's intent is therefore not knowable from the payload — it
has to be read off the repository.

The honest signal is the plan file, because setting its status to COMPLETED
*is* the documenter's own declaration that it finalised. The gate now holds it
to that claim rather than to the mere fact of being called.

1. **New shared reader** — `Get-AfPlanLifecycle` (`_common.ps1`) and
   `af_plan_lifecycle` (`_common.sh`). Finds the plan file that names
   `agent/{workflow-id}` and returns its status.
2. **`documenter-stop` Gate 0** — plan COMPLETED ⇒ finalisation, artifact gate
   applies as before. Plan not COMPLETED ⇒ mid-workflow, gate skipped with a
   message naming the observed status. No plan names this branch ⇒ the call
   cannot be classified, so the hook says exactly that and names the
   compliance-checker post-flight gate as the enforcement point.
3. **`stop-tests`** — shares the same reader. It now judges the same condition
   as `documenter-stop`, differing in force rather than in what it considers
   wrong: `PENDING` while the workflow is open, `WARNING` when a plan marked
   COMPLETED is missing its closing artifacts.
4. **`compliance-checker.agent.md`** — post-flight gates moved from existence
   to content: the log's `status:` must be COMPLETED with `workflow_id`,
   `git_branch`, `completed:` and a non-empty `steps:` list; the retro must
   carry at least one concrete lesson.
5. **`documenter.agent.md`** — states which responsibility is mid-workflow and
   that such a call must stop without writing closing artifacts.

### Two refusals in the reader

**It does not match raw text.** `templates/PLAN.md` ships

```markdown
**Status:** <!-- DRAFT | APPROVED | IN_PROGRESS | COMPLETED -->
```

so a grep for COMPLETED calls an untouched template a finished workflow. HTML
comments are stripped first — with `awk` on the bash side, because `sed` has no
non-greedy match and `<!--[^>]*-->` stops at the first `>` inside a comment.

**It does not accept any plan in the directory.** A plan speaks for the one
workflow whose branch it names; `agent/72-x` is not satisfied by
`agent/72-x-followup`. `stop-tests` previously passed if *any* file under
`docs/plans/` mentioned COMPLETED anywhere, so a finished plan from an
unrelated workflow silenced it.

### Why the no-plan case is not silent

If nothing names the branch, the hook genuinely cannot tell a mid-workflow call
from finalisation. It passes — blocking on an unknown would recreate the
original coercion — but it says which of the two it is. Passing quietly is what
this entire issue family is about: a gate that cannot run and a gate with
nothing to say produce identical output, and every layer reads that silence as
consent.

The loophole this opens — "never mark the plan COMPLETED and the gate never
fires" — is closed at the right layer. The compliance-checker's post-flight
gate already requires plan status COMPLETED **and** the log **and** the retro,
and it runs exactly once per workflow.

## Acceptance criteria

- [x] A mid-workflow documenter invocation on an `agent/` branch can terminate
      without creating `.github/logs/{id}.yaml` or `retros/auto/{id}.md`.
- [x] End-of-workflow finalisation still cannot terminate without both.
- [x] A workflow log written before finalisation no longer satisfies the
      compliance-checker post-flight gate (content, not existence).
- [x] `documenter-stop` and `stop-tests` agree on the severity of the same
      missing-artifact condition.

## Verification

`test-hooks.ps1`: 162 passed / 0 failed (152 before).
`test-hooks.sh`: 69 passed / 0 failed (59 before).

Ten new cases per suite:

| Case | Binds |
|---|---|
| mid-workflow call is not forced to write a COMPLETED log | Gate 0 exists |
| finalisation without the artifacts is still blocked | the gate still gates |
| finalisation with both artifacts passes | no false block |
| an untouched plan template does not count as COMPLETED | status parser anchoring |
| a commented-out status line does not count as the status | comment stripping |
| another workflow's COMPLETED plan does not finalise this one | branch matching |
| with no plan file the gate says it could not classify the call | the message, not just the verdict |
| stop-tests treats an open workflow as pending | AC4 |
| stop-tests warns on the condition documenter-stop blocks on | AC4 |
| stop-tests does not accept another workflow's COMPLETED plan | AC4 |

Mutation-proven, because a green suite says nothing about whether a case binds:

| Mutation | Failures |
|---|---|
| Gate 0 removed (the pre-fix behaviour) | 4 |
| HTML comments no longer stripped | 1 |
| plan no longer has to name this branch | 1 |

The comment-stripping case was rewritten once during this work: the first
version used an inline comment, which the status parser's line anchoring
already rejected, so the mutation did not turn it red. A case that passes under
its own mutation is decoration. Replacing it with a block comment — the shape a
guidance section in a plan actually has — made it bind.

## Harness changes

`Invoke-HookInFixture` gained an optional `-Files` hashtable and the bash
harness a `stop_case` runner, both seeding relative paths into the fixture.
Lifecycle state lives on disk, so without seeding, a test would assert against
whatever the developer's checkout happened to contain.

Stop hooks emit `hookSpecificOutput.decision`, not `permissionDecision`, so the
existing verdict resolvers do not apply; the new runners read the decision
directly and treat a non-zero exit or unparsable output as failure.
