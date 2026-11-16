**Workflow:** Bug Fix
**Branch:** `agent/547-af-github-namespace`
**Status:** IN PROGRESS
**AF Version:** 2.0.0

## Context

AF #547: in the Copilot harness, `gh-issue-manager` and `gh-pr-manager` run as subagents without GitHub tools, because `github/<tool>` grants do not resolve against a server named `github`. The same server under another name resolves with the slash form, read and write (AF #447 comment 6912410586). Owner decision: namespace `af-github`, registered by a repo-root `.mcp.json` that the deploy creates only when absent. 2.x only; Local resolves `github/*` against its own registration.

## References

- AF #547 — decision and acceptance criteria
- AF #447 comment 6912410586 — subagent grant measurements
- AF #528 — Copilot-harness migration epic

## Scope Assessment

- **Files affected:** 9
- **Layers touched:** Agent payload, deploy scripts, test harness
- **Complexity tier:** Standard
- **Estimated size:** small (3 subtasks)
- **Not in scope:** `mcp-deploy` engine, `.vscode/mcp.json` handling, Local release line, user-level MCP configuration, MP
- **Risks:** An existing project `.mcp.json` must never change. A dry run must write nothing. The bash deploy takes minutes to finish, so the registration step runs before the payload copy and the tests stop the deploy once it is past that step.

## Subtasks

### 1. Expressing the contract as failing tests

- **Action:** New suite `test-github-mcp-registration.ps1`: agent grants (no `github/` grant, both managers grant `af-github/`), and deploy.ps1 registration cases (absent → created, present without/with `af-github` → byte-identical with/without warning, dry run → nothing written). Bash twin cases in `test-deploy-nonrepo.sh`, which CI already runs. Register the new suite in `suite-scope.json` and `suite-budgets.json`.
- **Files:** `.github/scripts/test-github-mcp-registration.ps1`, `.github/scripts/test-deploy-nonrepo.sh`, `.github/scripts/suite-scope.json`, `.github/scripts/suite-budgets.json`
- **Acceptance criteria:** Each new case fails for the missing behavior, not for a harness error; existing cases keep passing.
- **Exit criterion:** The canonical runner reports the new PS suite failing on the grant and registration cases; the bash suite fails only on its new cases.
- **Status:** TODO

### 2. Shipping the `af-github` namespace and registration

- **Action:** Template `templates/mcp.json`; create-if-absent step in `deploy.ps1` and `deploy.sh` before the payload copy; grants and prose in both managers and the gh-issue skill; changelog fragment.
- **Files:** `templates/mcp.json`, `deploy.ps1`, `deploy.sh`, `.github/agents/gh-issue-manager.agent.md`, `.github/agents/gh-pr-manager.agent.md`, `.github/skills/gh-issue/SKILL.md`, `changelog.d/547-af-github-namespace.md`
- **Acceptance criteria:** All cases from subtask 1 pass; `test-suite-scope.ps1` and `test-suite-budgets.ps1` pass.
- **Exit criterion:** Scoped sweep and the bash deploy suite green locally and in CI.
- **Status:** TODO

### 3. Verifying in the probe after merge

- **Action:** Redeploy into the probe repo, register `af-github`, and let the unmodified gh-issue-manager post a comment as a subagent.
- **Files:** none in the AF repo (probe repo only)
- **Acceptance criteria:** Comment exists and is read back; evidence in AF #547.
- **Exit criterion:** Session events show the subagent calling `af-github/add_issue_comment` successfully.
- **Status:** TODO

## Implementation Sequence

1. Subtask 1 → observe Red with the canonical runner.
2. Subtask 2 → Green; scoped sweep.
3. PR to `dev`; subtask 3 after merge.

## Quality Gates

| Gate | Target | Type |
|---|---|---|
| Regression behavior | New cases Red before, Green after; scoped sweep green | HARD |
| Non-destructive deploy | Existing `.mcp.json` byte-identical; dry run writes nothing | HARD |
| Line isolation | Only the 2.x worktree | HARD |

- **Suggested workflow:** Full TDD
- **Skills consulted:** `git-workflow`, `unit-testing`, `test-execution`, `gh-issue`

## Plan Approval

**Approved by:** owner decision recorded in AF #547 (2026-11-16)
**Verdict:** APPROVED

## Change Log

| Date | Agent | Change |
|---|---|---|
| 2026-11-16 | coordinator | Initial plan from AF #547 |
