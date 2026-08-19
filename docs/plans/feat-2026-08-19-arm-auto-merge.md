<!-- copilot:generated | documenter | 2026-08-19 -->

# Implementation Plan: arming the merge nobody is there to arm

**Status:** IN PROGRESS
**Issue:** #150
**Branch:** `agent/150-arm-auto-merge`

## Context

Issue #150. #143 built a check GitHub can see, #147 versioned the rulesets, and
#146 gave the framework an agent that can open a pull request. The chain still
stops one step short of the request that started all of it — merge when all
conditions are met.

GitHub's auto-merge is opt-in per pull request. The repository setting *Allow
auto-merge* only makes the control exist; someone with write access must arm
each pull request, and the MCP server exposes no tool for that. PR #149 is the
evidence: `conclusion: success` at 07:16:33, `mergeable_state: "clean"`, and it
waited for a human click. Every condition was met and nothing happened.

## References

- Issue #150 — the gate says green and nothing merges
- Issue #146 / PR #149 — `gh-pr-manager`, which opens the pull request it
  cannot arm
- Issue #143 / PR #144 — the required check
- Issue #147 / PR #148 — the rulesets in `docs/rulesets/`
- Issues #125, #98, #27 — guards whose passing verdict carried no information

## Scope Assessment

- **Files affected:** 3
- **Layers touched:** repository infrastructure (one workflow at the repository
  root) and the framework changelog
- **Complexity tier:** Standard
- **Estimated size:** S
- **Risks:** the dominant risk is arming a pull request whose contents nobody
  vetted. The repository is public, so a fork pull request is the live attack
  path: arming one merges an outsider's code unattended. Mitigated by using
  `pull_request` rather than `pull_request_target` — the fork variant receives
  a read-only token — and by three independent conditions on the job. Second
  risk: arming silently failing, which produces a pull request waiting forever
  for something nobody is doing. Mitigated by letting the step fail the job.
  Third risk: a token-armed merge suppressing the post-merge `push: dev` run,
  because work done with `GITHUB_TOKEN` does not trigger further workflows —
  accepted and documented rather than discovered later.

## Subtasks

### 1. Add the arming workflow

- **Action:** add `.github/workflows/arm-auto-merge.yml`, triggered on pull
  requests into `dev`, running `gh pr merge --auto --merge`.
- **Files:** `.github/workflows/arm-auto-merge.yml`
- **Acceptance criteria:**
  - `pull_request`, never `pull_request_target`
  - the job runs only for same-repository pull requests authored by the
    repository owner, based on `dev`, and not draft
  - `permissions` is limited to `contents: write` and `pull-requests: write`
  - a failure to arm fails the job
  - the workflow lives at the repository root, not in the payload: consumers on
    other platforms do not need it and `.af-manifest` does not own workflows
- **Exit criterion:** a pull request into `dev` is armed without a human, and a
  fork pull request is not.

### 2. Measure what documentation cannot settle

- **Action:** determine on a real pull request whether a workflow-level
  `permissions:` block grants write when the repository default is read-only.
- **Files:** none — measurement only
- **Acceptance criteria:**
  - the answer comes from a workflow run, not from a documentation reading
  - if it is blocked, the required repository setting is named
- **Exit criterion:** the run either arms the pull request or fails with a
  permissions error that names what to change.

### 3. Let the change test itself

- **Action:** open the pull request as a **draft**, so the job skips; marking it
  ready fires `ready_for_review` and arms it.
- **Files:** none
- **Acceptance criteria:**
  - the human keeps control of the moment the automation first acts
  - the first real exercise of the workflow is the workflow's own pull request
- **Exit criterion:** marking the draft ready arms the merge, and the merge
  happens only after the required check passes.

## Quality Gates

- [ ] Workflow YAML parses
- [ ] `Regression Suites` green on the pull request
- [ ] Arming observed, or its failure reported with the setting it needs
- [ ] CHANGELOG entry references #150

## Follow-up

If arming is blocked by the repository's workflow-permissions default, that
setting becomes a documented deployment prerequisite rather than a silent one.
