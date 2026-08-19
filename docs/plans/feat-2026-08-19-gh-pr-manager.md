<!-- copilot:generated | documenter | 2026-08-19 -->

# Implementation Plan: a pull request an agent may open, and one branch it may not merge

**Status:** IN PROGRESS
**Issue:** #146
**Branch:** `agent/146-gh-pr-manager`

## Context

Issue #146. The merge gate from #143 is live: `dev` and `main` both report
`"protected": true` and both require the `Regression suites (Windows
PowerShell 5.1)` check. What the repository still lacks is an agent that can
open a pull request against them. `ado-pr-manager` exists and speaks only Azure
DevOps; the coordinator's request-based integration path names it explicitly
and has no GitHub branch. So on this repository the integration path is pure
git — the human pushes, opens, and merges everything — while the gate that was
built to make autonomy safe goes unused.

The obvious move is to port `ado-pr-manager`. The assumption underneath it does
not survive contact with GitHub, which is the substance of this change.

## References

- Issue #146 — no agent may open a pull request or knows which branch it must
  not merge into
- Issue #143 / PR #144 — the merge gate this depends on
- Issue #147 / PR #148 — the rulesets, versioned in `docs/rulesets/`
- Issue #22 — the epic this belongs to
- `agents/ado-pr-manager.agent.md` — the structural model
- `agents/gh-issue-manager.agent.md` — the `github/*` tool namespace and the
  `off → return the drafted body` precedent
- `skills/git-workflow/SKILL.md` § 2 — integration paths

## Scope Assessment

- **Files affected:** 7
- **Layers touched:** framework payload (new agent, configuration, coordinator
  wiring, naming convention, skill matrix, changelog) plus this plan
- **Complexity tier:** Deep — a new architectural element (a provider worker)
  with a new autonomy boundary
- **Estimated size:** M
- **Risks:** the dominant risk is that the agent closes an issue nobody
  verified. GitHub's closing keywords fire on merges into the default branch,
  so the risk is concentrated in one branch rather than spread across the merge
  logic. Mitigated by an allowlist that excludes it and a refusal that holds
  even if a human adds it. Second risk: mirroring `ado-pr-manager`'s
  autocomplete semantics onto a platform that has none, producing an agent that
  claims to have armed a merge which will never happen. Mitigated by
  establishing that no such tool exists before designing, and by giving the
  "platform refused" outcome its own status.

## Subtasks

### 1. Establish whether GitHub autocomplete is reachable at all

- **Action:** search the available MCP surface for an auto-merge tool before
  assuming the ADO design ports.
- **Files:** none — measurement only
- **Acceptance criteria:**
  - the result is a measured tool inventory, not an inference from the GitHub
    web UI, which does offer auto-merge
  - if absent, the consequence for the agent's status vocabulary is recorded
- **Exit criterion:** the tool inventory is known and the design either ports
  autocomplete or does not, on evidence.
- **Outcome:** absent. The surface exposes `create_pull_request`,
  `update_pull_request`, `pull_request_read`, `update_pull_request_branch` and
  `merge_pull_request`. Enabling auto-merge is a GraphQL mutation the server
  does not surface. `merge_pull_request` attempts the merge now, and the
  ruleset refuses it while a required check is unfinished — so the gate holds
  either way, and a refusal is a normal outcome.

### 2. Write the agent with an allowlisted merge policy

- **Action:** create `agents/gh-pr-manager.agent.md` with the branch-scoped
  policy expressed as an allowlist, the no-autocomplete finding stated where a
  reader looking for the ADO analogue will hit it, and the default-branch
  refusal as a HARD gate.
- **Files:** `flavors/github-copilot/.github/agents/gh-pr-manager.agent.md`
- **Acceptance criteria:**
  - no terminal and no git tool is granted
  - `merge_method` is fixed to `merge`; squash is refused with its reason
    (a squash commit does not contain the feature-branch tip, so post-merge
    `git branch -d agent/*` fails as "not fully merged")
  - the default branch is refused even when allowlisted
  - `NEEDS_CHECK_COMPLETION` and `NEEDS_HUMAN_MERGE` are distinct statuses and
    the file says why collapsing them breaks the coordinator
  - the agent never polls for a check to finish
  - the policy-not-platform limitation is stated in the agent file, per the
    issue's sixth acceptance criterion
- **Exit criterion:** all six acceptance criteria of issue #146 are traceable to
  a section of the agent file.

### 3. Add the configuration keys

- **Action:** add a `GH_PR_*` block to `af-env.conf`, gated independently of
  `GH_CAPABILITY_MODE`.
- **Files:** `flavors/github-copilot/.github/af-env.conf`
- **Acceptance criteria:**
  - `GH_PR_CAPABILITY_MODE` defaults to `off` and uses the established
    `off | optional | required` vocabulary
  - the warning against listing the default branch sits on the key it applies
    to, not in a document someone would have to go and find
  - separate gating from issues is justified in the comment: tracking issues
    and merging into a shared branch are different amounts of trust
- **Exit criterion:** a fresh deployment of the framework merges nothing until
  a human changes a value.

### 4. Wire it in

- **Action:** register the agent everywhere an existing provider worker is
  registered.
- **Files:** `coordinator.agent.md`, `instructions/quality-gates.instructions.md`,
  `skills/INDEX.md`, `CHANGELOG.md`
- **Acceptance criteria:**
  - `coordinator.agent.md` stays under `AF_AGENT_CONTEXT_BUDGET_TOKENS`; it had
    213 tokens of headroom before this change, so the budget check is run, not
    assumed
  - `.af-manifest` needs no entry — it registers `agents/` as a directory
  - no new skill is created. The operational content fits the agent file, which
    is loaded only when the agent runs; a skill would add an indirection
    without removing anything from context
- **Exit criterion:** the agent is discoverable from the coordinator and from
  the skill matrix, and no budget regressed.

### 5. Verify

- **Action:** run the context budget check and the affected regression suites.
- **Files:** none
- **Acceptance criteria:**
  - the agent frontmatter parses and every tool id resolves
  - budgets pass with measured headroom reported, not asserted
- **Exit criterion:** every suite touching plans, gates and budgets is green in
  this transcript.

## Quality Gates

- [ ] All subtasks complete
- [ ] Context budget check passes with reported headroom
- [ ] Agent and MCP tool-id suites pass
- [ ] CHANGELOG entry references #146
- [ ] Pull request opened against `dev`; the human merges
