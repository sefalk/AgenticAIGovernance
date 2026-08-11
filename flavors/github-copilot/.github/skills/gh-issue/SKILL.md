---
name: gh-issue
description: 'GitHub issue lifecycle via MCP — repository routing (project vs framework upstream), duplicate search before create, evidence-grounded framework defect reports, sub-issue linking, and degraded-mode fallback.'
---

# GitHub Issues

Operational depth for `gh-issue-manager`. Two routes share one worker:

| Route | Target repo | Purpose |
|---|---|---|
| **project** | `GH_OWNER/GH_REPOSITORY` | The project's own issue tracker (GitHub analogue of `ado-work-item-manager`) |
| **upstream** | `AF_UPSTREAM_REPO` | Defects in the **Agent Framework itself**, reported from a consumer project |

The upstream route exists because a consumer's own tracker is the wrong place
for a framework defect: nobody who can fix it reads that board. It is
independent of which tracker the project uses for its own work — a project can
run `ADO_CAPABILITY_MODE=optional` for its work items and still report
framework defects upstream to GitHub.

**Coordinator contract.** The coordinator holds no `github/*` tools and
delegates every issue operation here. That is deliberate: a coordinator that
files its own issues is a coordinator whose tool surface grows without review.
What qualifies as a framework defect: a payload file that is wrong, a gate that
cannot pass, a script that fails on arrival — anything the consumer project
cannot fix on its own without diverging from the payload. When a route is gated
off and this worker returns a drafted body instead of filing it, the coordinator
surfaces that body in its final summary — a suppressed write must not become a
suppressed finding.

## 1. Capability Probe

Run once per workflow, before any write:

1. `get_me` — confirms the MCP server is reachable and yields the acting
   identity. Record it; a report filed under an unexpected identity is a
   finding, not a detail.
2. Resolve the target repo from the route (see table above). If the route is
   `upstream` and `AF_UPSTREAM_REPORTING=off`, do not file — return
   `SKIPPED` with the drafted body so the human can file it manually.

Outcome is one of:

- **READY** — reachable, repo resolves, identity known.
- **DEGRADED** — unreachable or repo unresolved while the mode is `optional`.
  Emit the full issue body as a fallback artifact marked `pending-sync`.
- **BLOCKED** — unreachable while the mode is `required`. Halt and escalate.

Never silently skip. A defect report that was never filed and never mentioned
is indistinguishable from a defect that does not exist.

## 2. Duplicate Search Before Create (mandatory)

Never create before searching. Two passes, because they fail differently:

1. `search_issues` with `repo:{owner}/{name} is:issue` plus 2–4 distinctive
   terms from the defect (a file name, a config key, an error string). Include
   **closed** issues — a closed duplicate means the fix exists and the consumer
   is on an old version, which is a different report entirely.
2. `list_issues` filtered by label when the defect belongs to a known category
   and the free-text search returns nothing.

Decision:

| Search result | Action |
|---|---|
| Clear duplicate, open | `add_issue_comment` with the new evidence; do **not** create |
| Clear duplicate, closed | Comment with the version you observed it on; create only if the fix is present and the defect persists |
| Related but distinct | Create, and reference the related issue by number in the body |
| Nothing | Create |

State which pass you ran and what it returned. "No duplicate found" without a
recorded query is an unverifiable claim.

## 3. Evidence-Grounded Framework Defect Reports

A framework defect report is only useful if the maintainer can act on it
without reproducing your entire session. Before filing, **verify the claim
against the framework source**, not against the deployed copy in the consumer
project — the deployed copy may carry local modifications, so a defect
observed there may not exist upstream.

Use `get_file_contents` (or `search_code` scoped to the upstream repo) to
confirm the offending line is present in the framework source. If it is not,
the defect is a local divergence in the consumer project and does **not**
belong upstream.

Body template:

```markdown
## What happened
{one paragraph, concrete, observed — not inferred}

## Where
`{payload path}` {line reference if applicable}
Framework version observed: `{contents of .github/.af-version}`
Verified present in framework source: {yes + how, or "no — local divergence"}

## Why it matters
{the consequence. Prefer the failure mode over the inconvenience.}

## Evidence
{command + verbatim output, or the file excerpt. No paraphrase.}

## Suggested direction
{optional. A direction, not a patch — the maintainer owns the design.}
```

Rules:

- **No secrets, no absolute user paths, no organization-internal identifiers.**
  A consumer project's issue text crosses an organizational boundary when it
  goes upstream. Redact `C:\Users\...`, tokens, internal host names, and
  internal work-item titles. Replace with `{redacted}` and say so.
- One defect per issue. A report bundling three findings gets fixed once.
- Prefer a failure the maintainer can reproduce from the framework repo alone.

## 4. Labels and Linking

- `get_label` before applying — applying a non-existent label silently drops it
  on some API paths. If the label is missing, file without it and note that.
- `sub_issue_write` links a report to an existing epic. Use it when the epic is
  known; do not invent an epic to hold a single report.
- Cross-reference sibling reports by `#number` in the body when they share a
  root cause. A batch of related findings is more actionable than a pile.

## 5. Non-Destructive Update Rules

- Read before update (`issue_read`) — never overwrite a body you have not read.
- Prefer `add_issue_comment` over editing the body. The body is the original
  report; comments are the trail.
- Closing: only close an issue you can evidence is resolved (merge commit,
  released version). Record the evidence in the closing comment.
- Never close an issue filed by someone else without explicit instruction.

## 6. Return Discipline

Report the issue **number and URL** for every create. A create without a
returned number cannot be verified and must be treated as a failed create,
not a successful one — re-run the duplicate search rather than re-creating
blindly.
