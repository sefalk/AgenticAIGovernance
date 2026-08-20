---
name: work-item-state
description: 'Keep working state on the tracker rather than in agent context — the body-resident working-state block, dated decision records as comments, the read-both/update-on-landing rule, the narrow trigger, and the provider mechanics for GitHub issues and Azure DevOps work items.'
---

# Working State on the Tracker

Provider-agnostic. Both `gh-issue-manager` and `ado-work-item-manager` apply
this; the provider sections carry only what differs between them.

The problem it solves (#186): every issue reads as it did on the day it was
filed. What has been delivered, what is blocked, what was decided and why lives
in an agent's context window and in chat transcripts. When the context ends, the
knowledge ends with it, and the next agent re-derives it from scratch — or, worse,
reads a stale body and concludes the work was never started.

## 1. Why the body, and not only comments

Measured against the GitHub MCP server on 2026-08-20:

| Call | Returns |
|---|---|
| `issue_read` `method: get` | the issue **body**, plus `comments: N` — see below |
| `issue_read` `method: get_comments` | the comments — a separate, second call |
| `list_issues` | `number, title, body, state, user, assignees, created_at, updated_at`, plus `labels` and `comments` when non-empty. Its `totalCount` counts *issues*. |

An agent that reads an issue the obvious way therefore sees the body alone. A
convention that keeps delivery status only in comments is invisible to that
read: the agent gets a description months out of date and no signal that
anything else exists. That is not a preference about formatting — it decides
where the state has to live.

### The count exists, but only when it is non-zero

There **is** a count to branch on, and getting to it took two measurements
because the first one was misleading. #186 was read before and after a comment
was posted to it:

| Moment | Comments | `comments` field |
|---|---|---|
| before | 0 | **absent** from both `issue_read get` and `list_issues` |
| after | 1 | `comments: 1` present in both |

The server omits empty fields rather than sending zeros. #183, which has no
comments but does carry labels, returns `labels` and no `comments` — the same
serialisation, seen on a different field. Reading only issues that happened to
have no comments is what produced the earlier, wrong conclusion that no count
existed anywhere; that is recorded on #186 rather than quietly fixed.

The fetch rule follows:

| Observation | Action |
|---|---|
| `comments: N`, N ≥ 1 | `get_comments` is **mandatory** — no exceptions, no sampling |
| field absent | treat as zero, and **say so in the return**: `comments: 0 (field absent)` |

The second row is an inference, not a reading. Absence is not self-describing:
it is sound only while the server omits empty fields, which the table above
establishes on two different calls and two different fields. Recording the
inference is what keeps it honest — if that serialisation ever changes, the
returns show exactly which decisions rested on it, instead of comments silently
going unread and nobody noticing.

So the count says **whether** to fetch. The body block's `Decisions` line says
**which** comments matter and what they settled — that is what makes the second
call targeted rather than exploratory. The count never licenses skipping a
non-zero fetch, and the block never substitutes for one.

Comments are still necessary. They are ordered, attributable and append-only,
which the body is not. So the two carry different things:

| Artifact | Carries | Property that makes it right |
|---|---|---|
| **Body** — one working-state block | the *current* state | returned by the default read |
| **Comments** — dated decision records | *how the state was reached* | chronological, never rewritten |

Neither substitutes for the other. A body block without decision records is an
assertion with no reasoning behind it; decision records without a body block are
reasoning nobody fetches.

## 2. The working-state block

Appended to the **end** of the issue body, inside a marker pair so an updater
can replace exactly one region and touch nothing else:

```markdown
<!-- af:working-state:START -->
## Working state

- **Updated:** 2026-08-20 — coordinator, branch `agent/183-pytest-guard-invocation`
- **Delivered:** guard now matches an invocation, not the word — PR #187, merged into `dev`
- **Open:** none
- **Blocked on:** nothing
- **Next step:** close at the next `dev` → `main` promotion (`Closes #N` cannot fire from `dev` — #160)
- **Decisions:** comment 5355802160 (why acceptance criterion 2 stays unmet)
<!-- af:working-state:END -->
```

Rules:

1. **One block per issue**, always at the end of the body, always between the
   markers. Never a second block, never the same content restated above it.
2. **The original description is never rewritten.** The block is appended to it.
   The body above the `START` marker is the report as filed and stays that way.
3. **`Updated` carries a date and an actor.** A block without them cannot be
   judged stale, and a block that cannot be judged stale is worse than no block:
   it reads as current forever.
4. **`Open` names what the issue still asks for.** When every entry is resolved
   the issue is closable — and only then. The full acceptance-criterion →
   evidence map goes in a closing comment, not here; this line is the summary
   that makes the map's absence visible.
5. **`Delivered` names a locatable artifact** — branch, PR number, merge target.
   "Implemented" without a reference is not a working state, it is a claim.
6. **`Decisions` links the comments** by id or permalink, and says in a clause
   what each settled. This is the index from § 1: it is what makes the
   `get_comments` call targeted instead of exploratory.
7. **Keep it to the six lines above.** The block is a pointer, not a report. If
   an entry needs a paragraph to defend it, the paragraph is a decision comment
   and the block cites it. A block that grows into prose re-creates the problem
   it exists to solve — an unbounded body that every reader pays for on every
   read.

The marker is deliberately `af:working-state`, not the `AF:MANAGED:` prefix used
inside payload files. Those regions belong to the deploy tooling and are scanned
on disk; this one lives in a tracker field and must not be confused with them.

## 3. Decision records as comments

One comment per decision, dated, append-only. Never edit or delete a past
record — a decision that turned out wrong is superseded by a later comment, not
erased. The trail is the point.

A record states, in this order:

1. **What was decided**, in one sentence.
2. **The evidence** — measured numbers, timestamps, command output, or an
   explicit "inferred, not measured".
3. **What was explicitly _not_ concluded.** This is the part that saves the most
   work later: it stops the next agent from re-litigating a question that was
   already bounded, and it stops a partial result being read as a complete one.

Issue #170 carries a worked example.

## 4. The rule, in two halves

Either half alone fails, so both are binding:

- **Before acting on an issue, read the body _and_ its comments.** `get` first;
  then `get_comments` whenever the `comments` count it returned is non-zero, and
  when the field is absent, record the zero you inferred (§ 1). Acting on the
  body alone means acting on state that may be superseded, and the body carries
  nothing to warn you that it is.
- **Any workflow that lands work touching an issue updates that issue's
  working-state block before it finishes** — the same standing obligation as the
  CHANGELOG entry, and for the same reason.

## 5. When a block is required

The trigger is narrow and checkable: **an issue whose state changed.** This is
not an instruction to put a status banner on every issue.

| Event | Block required? |
|---|---|
| Work merged that addresses part or all of the issue | **yes** |
| A decision taken that changes scope, or defers closure | **yes**, plus a comment |
| An acceptance criterion evaluated — met or unmet | **yes**, plus a comment for unmet |
| A blocker found | **yes** |
| An issue filed and untouched since | no |
| A batch triaged or reordered | on the **tracking** issue only, not on each member |
| Progress with no change to what is delivered, open or blocked | no |

## 6. Provider mechanics

### GitHub (`gh-issue-manager`)

`issue_write` `method: update` **replaces** the body; it does not patch it.
Therefore, always:

1. `issue_read` `method: get` — take the current body verbatim.
2. Splice: replace the text between the markers, or append a whole block if the
   markers are absent.
3. `issue_write` `method: update` with the complete new body.

Writing a body you have not just read overwrites whatever changed in between.
This is the existing non-destructive rule in `skills/gh-issue/SKILL.md` § 5, and
the block is the one sanctioned exception to "prefer comments over body edits".

Decision records use `add_issue_comment`.

Reporting: state what the count said and what you did about it —
`read: get (comments: 3) + get_comments (3)`, or
`read: get (comments: 0 — field absent)`. A return that names only `get` while
the count was non-zero is a partial read, and § 4 makes it a gate failure rather
than a detail.

### Azure DevOps (`ado-work-item-manager`)

The equivalent placement is the work item's description field, with decision
records as work item comments — and `skills/ado-workitem/SKILL.md`'s existing
"append or targeted rewrite only" rule governs the splice.

**Not yet measured for this provider.** The § 1 constraint is a GitHub
measurement. Whether an Azure DevOps description field renders Markdown depends
on the process template, and whether the default work-item read returns comments
has not been probed here. Probe both once, on first use, and record the outcome
in this section rather than assuming the GitHub answer transfers.

## 7. Anti-patterns

- **A stale block.** An `Updated` date older than the merged work it fails to
  mention is a false negative: the reader now has a positive reason to believe
  nothing happened. If the block cannot be kept current, do not add it.
- **Status theatre.** "In progress" for weeks with no artifact named. Delivered,
  open, blocked — or nothing.
- **Restating the CHANGELOG.** The block says what landed and where; the reasons
  and the prose belong in the CHANGELOG and the decision comments.
- **Rewriting the filed description** to reflect what is now understood. That
  destroys the record of what was originally observed.
- **Editing a past decision comment.** Supersede it with a new one.
- **Treating the block as a substitute for the comments.** It is an index. A
  reader who acts on it without fetching what it points at has read a summary
  written by someone who is no longer in the room.
- **Closing on a block.** A block is a summary, not evidence. Closure needs the
  acceptance-criterion → evidence map, and every criterion met.
