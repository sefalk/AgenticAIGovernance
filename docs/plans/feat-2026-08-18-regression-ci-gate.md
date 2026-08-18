<!-- copilot:generated | documenter | 2026-08-18 -->

# Implementation Plan: a regression gate GitHub can see

**Status:** COMPLETED
**Issue:** #143
**Branch:** `agent/143-regression-ci-gate`

## Context

Issue #143. The repository has fifteen regression suites and no continuous
integration: `.github/workflows` does not exist, there is no `.github`
directory at the repository root at all, and `dev` and `main` both report
`"protected": false` with an empty `required_status_checks.contexts`. Every
suite result therefore reaches the project as a claim in a chat transcript.

This is the blocking prerequisite for the request that produced the issue —
merging pull requests automatically once all conditions are met. There are no
conditions today, so a pull request is mergeable the instant it is opened and
auto-merge would merge on the author's own say-so. The suites have to become a
check GitHub can see before any autonomy is granted, not after.

## References

- Issue #143 — the suites run only on a maintainer's laptop
- Issue #22 — the epic this belongs to
- Issue #125 — a guard that passes because it never runs
- Issues #98, #27 — a verdict whose PASS carries no information
- `agents/ado-pr-manager.agent.md` — the branch-scoped autonomy policy this
  repository already applies on the Azure DevOps side, and the model for what
  comes after this gate exists

## Scope Assessment

- **Files affected:** 5
- **Layers touched:** framework payload (aggregate runner, manifest, changelog)
  and repository infrastructure (one workflow at the repository root)
- **Complexity tier:** Standard
- **Estimated size:** M
- **Risks:** the main risk is building the very defect the gate is meant to
  prevent — a check that reports green without asserting anything. Ten suites
  exit 0 when a prerequisite is missing and one suite cannot run on a hosted
  runner at all, so an exit-code-only runner would have been exactly that.
  Mitigated by classifying on output as well as exit code, by failing the run
  when a suite asserted nothing, and by requiring every CI exclusion to state
  its reason. Second risk: wall-clock time. The sweep takes about 16 minutes
  locally and a hosted runner is slower, which is friction on every pull
  request; accepted for now and left to be measured rather than guessed at.

## Subtasks

### 1. Measure whether the gate can be green at all

- **Action:** run all fifteen suites in one sweep before proposing a workflow,
  rather than assuming the suite set is CI-ready.
- **Files:** none — measurement only
- **Acceptance criteria:**
  - every suite is run, not a sample
  - each suite's prerequisite behaviour is read from its source, not inferred
    from its result on a machine that happens to satisfy it
- **Exit criterion:** 15 passed, 0 skipped, 0 failed, 956 s; ten suites found
  to bail out with `SKIP: ... exit 0`, and `test-hooks-integration.ps1` found to
  read VS Code's own hook log and so to be unable to run on a runner.

### 2. The aggregate runner

- **Action:** one entry point and one exit code for the whole suite set, which
  is what a CI job needs and what no script provided.
- **Files:** `scripts/run-all-tests.ps1`, `.af-manifest`
- **Acceptance criteria:**
  - each suite is classified PASS, SKIP, BLOCKED, FAIL or TIMEOUT, with SKIP
    detected from the suite's own output because the exit code cannot express it
  - under `-FailOnSkip` a suite that asserted nothing fails the run
  - a hung suite is killed rather than allowed to hang the job
  - a failing suite's full output is printed, so CI is diagnosable on its own
  - a suite can be excluded explicitly by name
- **Exit criterion:** `RESULT: ALL GREEN` over the full set, and the exclusion
  and `-FailOnSkip` paths exercised.

### 3. The workflow

- **Action:** run the runner on pull requests into `dev` and `main`.
- **Files:** `.github/workflows/regression.yml`
- **Acceptance criteria:**
  - `windows-latest`, because the suites are Windows PowerShell 5.1 scripts and
    hosted Linux runners have no `powershell`
  - the prerequisites that would otherwise cause silent skips are installed
  - a git identity is configured, because several suites commit inside
    throwaway repositories and a fresh runner has none
  - the one excluded suite carries its reason at the point of exclusion
  - the timeout is set above the measured runtime, not just above it
- **Exit criterion:** the file parses as YAML and the check runs green on the
  pull request that introduces it.

### 4. Documentation

- **Action:** record the finding and the deliberate limits of what was built.
- **Files:** `CHANGELOG.md`, `docs/plans/feat-2026-08-18-regression-ci-gate.md`
- **Acceptance criteria:**
  - the entry states that this is a prerequisite, not the requested feature
  - branch protection, auto-merge, head-branch deletion and issue closing are
    named as separate decisions that remain open
- **Exit criterion:** both plan guards pass.

## Quality Gates

- `run-all-tests.ps1` over all fifteen suites — 15 passed, 0 skipped, 0 failed
- The exclusion and `-FailOnSkip` paths exercised on a reduced set
- `regression.yml` parses under `yaml.safe_load`
- This document commits through both plan guards

## Plan Approval

Approved by: human approved automating the merge process; the sequencing —
continuous integration first, autonomy only afterwards — is an agent decision
taken while the human was unavailable, and is submitted for review with the
pull request. No repository setting was changed, and none can be by an agent.

### Open Findings

- The runner was initially built on `Start-Process -PassThru`, which leaves
  `ExitCode` empty without `-Wait`; an empty value compares as non-zero, so the
  first version reported every passing suite as failed. Caught by disagreeing
  with an earlier measurement of the same suite rather than by a test, which is
  the weaker way to catch it. The runner now uses `System.Diagnostics.Process`.
- `test-hooks-integration.ps1` is excluded from CI and so is verified nowhere
  automatically. It is a local diagnostic by design, but nothing now reminds
  anyone to run it.
- The sweep takes about 16 minutes locally. Whether that is tolerable as a
  required check on every pull request is a question for the first real runs,
  not for this plan.
- Nothing here grants any autonomy. Enabling auto-merge, protecting `dev`,
  deleting head branches on merge and closing issues from a merged pull request
  are four separate human decisions, and the last one carries a caveat this
  framework already documented on the Azure DevOps side: `ado-pr-manager`
  deliberately passes `transitionWorkItems: false`, because a fast merge would
  otherwise close every linked item, parents included, without anyone checking
  acceptance criteria.

## Change Log

| Date | Change |
|---|---|
| 2026-08-18 | Plan created and executed |
