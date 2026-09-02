---
name: deployment
description: Framework delivery paths — release cut, routine upgrade, hotfix into a mid-flight project, conflict resolution — each ending in a verification that reads the artifact, not a counter.
argument-hint: '[situation] — release cut | upgrade | hotfix | conflict'
metadata:
  activation:
    agents: [coordinator]
    priority: recommended
---

# Framework Delivery

Read this before moving framework files anywhere. It exists because delivery
used to be knowable only from `docs/wiki/12-deployment.md`, which is not part of
the payload — an agent working inside a consumer project could not reach it.

Mechanism reference (merge classification, managed regions, model tiers):
[12-deployment.md](https://github.com/sefalk/AgenticAIGovernance/blob/main/docs/wiki/12-deployment.md).
This skill does not repeat it; it says which path you are on and how you know
it worked.

## Which path

| Situation | Path |
|---|---|
| Framework changes are merged and should become a version | [1 · Release cut](#1--release-cut) |
| A project should pick up the current framework version | [2 · Routine upgrade](#2--routine-upgrade) |
| A framework defect is blocking a project that is mid-task | [3 · Hotfix into a running project](#3--hotfix-into-a-running-project) |
| A deploy reported `CONFLICT` on one or more files | [4 · Conflict resolution](#4--conflict-resolution) |

If you are not sure between 2 and 3: path 3 is for when the project cannot
continue without the fix. It costs an interrupted working tree, so do not take
it for convenience.

## The rule every path shares

**Verify by reading the artifact, never by reading a counter.**

`Updated: 0`, `RESULT: ALL GREEN` and `state: up-to-date` are all consistent
with having shipped the wrong bytes. Three specific ways they lie:

- A `git checkout` after a deploy reverts the deployed files, but `.af-hashes`
  already records the new hash — so the next apply sees no difference and
  reports `Updated: 0` while the fix is gone.
- A test suite is green when its cases are absent. Count the cases, not the
  colour.
- The MCP server ships the payload bundled into its wheel at build time. A
  release cut does not change it. `af_status` now reports this as
  `payload_state: behind-repository`, but only when a checkout is visible to
  it — treat `unverifiable` as "unknown", not as "fine".

So every path below ends in an assertion naming something the change
introduced.

## 1 · Release cut

In the framework repository.

1. Confirm what is being released: `git log --oneline origin/main..origin/dev`.
2. Bump `flavors/github-copilot/VERSION` yourself for a minor/major (staging
   `VERSION` makes the auto-patch pre-commit hook stand down); let the hook
   handle a patch.
3. Move the `[Unreleased]` section of `flavors/github-copilot/CHANGELOG.md`
   under the new version heading.
4. Open the promotion pull request `dev -> main`. Leave both declaration lines
   in the template commented out — CI checks the contributing pull requests
   instead (#234).
5. **Rebuild and reinstall the MCP wheel.** The payload is copied in at build
   time; skipping this ships the previous version from every `af_apply` until
   someone notices.

   ```powershell
   cd flavors/github-copilot/mcp-deploy
   .\.venv\Scripts\python.exe -m build
   .\.venv\Scripts\python.exe -m pip install --force-reinstall (Get-ChildItem dist\*.whl | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
   ```

**Verification.** `af_status` on any project must report the new number as
`source_version` and `payload_state` as `current`. If it reports
`behind-repository`, step 5 did not take effect — the wheel in the environment
the MCP server actually launches from is not the one you just built.

## 2 · Routine upgrade

In the consumer project.

1. `af_status` — note `deployed_version`, and stop if `payload_state` is
   `behind-repository`; upgrading to a stale payload is a downgrade in
   disguise.
2. `af_dry_run` — read the classification. `PRESERVE` and `CONFLICT` entries
   are the only ones that need a decision.
3. `af_apply`.
4. Commit the framework files as their own commit, separate from project work.

**Verification.** Pick one line that this version introduced — a new hook
predicate, a new skill file, a changed instruction — and assert it is present
in the target:

```powershell
Select-String -Path .github\<file> -Pattern '<text the new version added>' -Quiet
```

`True` is the pass condition. `Updated: N` is not.

## 3 · Hotfix into a running project

The project is on a feature branch, possibly with uncommitted work, and a
framework defect blocks it. Order matters here.

1. **Record the local state before touching anything.**

   ```powershell
   git rev-parse --abbrev-ref HEAD; git status --porcelain
   ```

   Keep both. Step 4 restores against this record, not against memory.
2. **Fix in the framework repository and release it** (path 1, including the
   wheel rebuild). Do not hand-edit framework files inside the consumer project
   — the next deploy classifies them `CONFLICT` or silently overwrites them.
3. **Deploy onto the branch the project is already on.** Do not switch branches
   to deploy. If in-flight edits collide with framework files, stash only those
   files, deploy, then unstash.
4. **Restore the local state — and re-verify after every checkout.** This is
   the trap: the recorded branch predates the fix, so any `git switch` or
   `git checkout` back to it reverts the deployed files, while `.af-hashes`
   still records the fixed hash. A follow-up `af_apply` then reports nothing to
   do. After returning to the branch, re-run the content assertion below; if it
   fails, re-apply with force and re-baseline (`af_update_hashes`).

**Verification.** Assert the defect is gone by exercising it, not by observing
that the deploy finished: run the thing that was blocked. If the fix was in a
hook, trigger the hook. A hotfix whose only evidence is `Created: 0,
Updated: 12` has not been verified.

## 4 · Conflict resolution

1. `af_conflict_diff` for each conflicted file — three-way: bundled source,
   deployed baseline, local edit.
2. Decide per file. Local customisation that should survive: keep it. Framework
   change that must land: take it.
3. `af_write_resolved` with the merged content.
4. `af_update_hashes` to re-baseline, so the next deploy does not re-raise the
   same conflict.

**Verification.** Re-run `af_dry_run`. The previously conflicted files must
classify `UNCHANGED`, and the lines you chose to keep must still be readable in
the target file. A clean dry-run with your customisation gone is a failed
resolution, not a successful one.

## When a path has no verification you can write

Say so and stop. `Not verified` is a reportable outcome; a counter presented as
evidence is not.
