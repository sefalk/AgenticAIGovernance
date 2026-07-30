---
name: 'Quality Gate System'
description: 'Generic quality gate framework — taxonomy, complexity tiers, per-agent exit gates, and handoff protocol. Applies to all agents and all file types.'
applyTo: '**'
---

# Quality Gate System

Every agent must satisfy its exit gates before handing off work. This
instruction defines what those gates are, how they scale with task
complexity, and how agents report gate status.

## Gate Taxonomy

Every quality gate is classified into one of three types:

| Type | Definition | Enforcement |
|---|---|---|
| **HARD** | Automated, measurable, binary pass/fail. Blocks handoff. | Agent verifies programmatically (run tool, check output). Coordinator rejects if missing or failed. |
| **SOFT** | Judgment-based. A reviewer (critic agent or human) decides pass/fail. | Listed in the agent's return for the reviewer to evaluate. Rejection triggers retry (MANIFEST § 4). |
| **ADVISORY** | Informational metric, never blocks. | Agent reports the value. Useful for trend tracking. |

**Maker-Checker rule:** An agent's self-check of its own structural output
is always SOFT, not HARD. Only a _different_ agent (critic) or an automated
tool can enforce a HARD gate. This prevents the cognitive bias of
proofreading your own work.

**BLOCKED state:** If a tool required for a HARD gate is unavailable
(terminal down, Pylance MCP unreachable, pytest not installed), report
the gate as **BLOCKED** — not PASS or FAIL — and include the reason.
The coordinator treats BLOCKED gates as escalation triggers.

## Complexity Tiers

The complexity tier determines which gates activate and at what strictness.
The planner sets the tier in the plan file; the coordinator sets it for Trivial Fix
and Quick Fix workflows.

| Tier | When | Examples | Gate Behaviour |
|---|---|---|---|
| **Trivial** | ≤ 2 files, no logic changes, no architectural impact | Rename, format, config edit, doc fix, typo | HARD: Gate 1 (Auto-Check) only. No SOFT gates. No critic invoked. |
| **Standard** | 3–5 files, within existing architecture | Bug fix, small feature, local refactor | HARD: Auto-Check + applicable skill gates. SOFT: Critics review. ADVISORY: Reported. |
| **Deep** | 6+ files, or new architectural elements, or cross-cutting | New module, new port/adapter, major feature | HARD: All gates at full thresholds. SOFT: All critics + arbiter available. ADVISORY: All reported. |

**Layer override:** If any touched file is in domain core or ports, the
minimum tier is **Standard** regardless of file count. Domain core changes
carry architectural risk disproportionate to their size.

**Exemption:** Pure documentation changes (docstrings, comments, README
updates) in domain core files do not trigger the layer override. The
change must affect **logic** (executable code, type signatures, imports)
to count.

**Human override:** The human can change the tier at plan approval time.

## Agent Naming Convention (Provider Workers)

Provider-scoped integration workers should use the pattern
`{provider}-{capability}-{role}` to keep responsibilities explicit and portable.

Examples:

- `ado-work-item-manager`
- `ado-wiki-manager`
- `ado-pr-manager`
- `ado-pipeline-manager`
- `gh-issue-manager`

Naming violations are SOFT unless they cause broken orchestration references,
which is treated as HARD.

## Per-Agent Exit Gates

Each agent must verify its applicable gates before returning. Gates
reference the metric thresholds from MANIFEST § 5.

### Planner

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| Every subtask has ≥ 1 testable acceptance criterion | SOFT | Self-check (self-checks are SOFT) | Standard+ |
| Dependencies between subtasks are acyclic | SOFT | Self-check: verify sequence has no cycles | Standard+ |
| Complexity tier assigned | SOFT | `complexity_tier` field present in output | Standard+ |
| Scope assessment complete (files, layers, size, risks) | SOFT | Self-check: all fields filled | Standard+ |
| Risk section populated (≥ 1 risk identified) | SOFT | Self-check | Deep |

### Test-Writer

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| All new tests FAIL (Red phase) | HARD | Run test suite, verify non-zero exit code for new tests | Standard+ |
| Zero syntax/import errors in test files | HARD | Run syntax checker (Pylance, `py_compile`) | Standard+ |
| Provenance marker on new test files | HARD | Verify `copilot:generated` header present | Standard+ |
| Skills read declaration | SOFT | `Skills Read:` line in Gate Summary (critic flags if missing) | Standard+ |
| Edge cases covered per acceptance criteria | SOFT | test-critic reviews | Standard+ |
| Property tests for wide input spaces | SOFT | test-critic reviews | Deep |

### Test-Critic

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| All checklist items evaluated | SOFT | Self-check: checklist completed | Standard+ |
| Verdict header is parseable | HARD | Verify `## Test Review Verdict: {V}` format | Standard+ |
| Anti-gaming scan performed | SOFT | Self-check: anti-pattern list checked | Standard+ |

### Implementer

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| All tests pass | HARD | Run test suite, verify zero failures | Standard+ |
| Zero syntax/import errors | HARD | Run syntax checker | Standard+ |
| Python type hints complete (changed source files) | HARD | Verify all public functions have full argument+return annotations in changed `SRC_DIR/**/*.py` files | Standard+ |
| Python docstrings present and structured (changed source files) | HARD | Verify changed public functions include non-trivial docstrings with parameters/returns sections when applicable | Standard+ |
| Ignore statements justified | HARD | Reject `# noqa` / `# type: ignore` / `# pyright: ignore` without explicit rule code and justification comment, across `SRC_DIR/**/*.py` **and** `tests/**/*.py` — the acknowledgement path for inherited lint debt runs through test files. Same rule for a new `ignore` / `per-file-ignores` entry in the project's ruff config — the linting gate honours those, so each needs a comment stating why. | Standard+ |
| Linting clean (branch delta, source **and** tests) | HARD | Run `check-python-linting.py` on `SRC_DIR/**/*.py` **and** `tests/**/*.py` across the branch delta (`merge-base(HEAD, BASE_BRANCH)..HEAD`), not just the current step — files committed in an earlier phase ship on merge too. Rule set determined by `LINTING_STRICTNESS` in `af-env.conf`. Gate is BLOCKED (not fail) if `ruff` is not installed. Mirrored from the refactorer because the Refactor step is optional. | Standard+ |
| Line coverage ≥ threshold | HARD | Run coverage tool, compare to MANIFEST § 5 thresholds: Domain ≥ 90%, Ports ≥ 80%, Adapters ≥ 60%, Utilities ≥ 85% | Standard+ |
| No secrets in changed files | HARD | Grep for credential patterns, API keys | Standard+ |
| New deps declared in spec file | HARD | If a new package was `import`ed, verify it appears in the project dep file (`af-env.conf` → `DEP_FILE` / `DEP_DEV_FILE`) | Standard+ |
| Provenance markers on new/modified files | HARD | Verify markers present | Standard+ |
| Skills read declaration | SOFT | `Skills Read:` line in Gate Summary (critic flags if missing) | Standard+ |
| Architecture boundaries respected | SOFT | code-critic reviews | Standard+ |
| Complexity ≤ threshold | SOFT | code-critic verifies: Domain ≤ 10, Ports ≤ 5, Adapters ≤ 15, Utilities ≤ 8 | Deep |

### Refactorer

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| All tests still pass after each step | HARD | Run test suite after each refactoring | Standard+ |
| Zero syntax/import errors | HARD | Run syntax checker | Standard+ |
| Python type hints remain complete (changed source files) | HARD | Verify all changed public functions in `SRC_DIR/**/*.py` retain full annotations | Standard+ |
| Python docstrings remain complete (changed source files) | HARD | Verify changed public functions retain structured docstrings | Standard+ |
| Ignore statements justified | HARD | Reject `# noqa` / `# type: ignore` / `# pyright: ignore` without explicit rule code and justification comment, across `SRC_DIR/**/*.py` **and** `tests/**/*.py` — the acknowledgement path for inherited lint debt runs through test files. Same rule for a new `ignore` / `per-file-ignores` entry in the project's ruff config — the linting gate honours those, so each needs a comment stating why. | Standard+ |
| No new files created (refactoring only) | HARD | Self-check: only existing files modified | Standard+ |
| Linting clean (branch delta, source **and** tests) | HARD | Run `check-python-linting.py` on `SRC_DIR/**/*.py` **and** `tests/**/*.py` across the branch delta (`merge-base(HEAD, BASE_BRANCH)..HEAD`), not just the current step. Rule set determined by `LINTING_STRICTNESS` in `af-env.conf` (`minimal`/`standard`/`strict`). Gate is BLOCKED (not fail) if `ruff` is not installed. | Standard+ |
| Skills read declaration | SOFT | `Skills Read:` line in Gate Summary (critic flags if missing) | Standard+ |
| Complexity reduced or unchanged | ADVISORY | Run complexity tool, compare before/after | Standard+ |

### Code-Critic

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| Gate 1 auto-check items verified | HARD | Run syntax/import/lint/test checks | Standard+ |
| Architecture review completed | SOFT | Self-check: layer boundary analysis done | Standard+ |
| Metrics collected and compared to thresholds | HARD | Run coverage + complexity tools | Standard+ |
| Security checklist completed | SOFT | Self-check: Gate 4 items checked | Standard+ |
| Verdict header is parseable | HARD | Verify `## Code Review Verdict: {V}` format | Standard+ |

### Arbiter

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| Both positions read and summarised | SOFT | Self-check: positions quoted | Deep |
| Verdict header is parseable | HARD | Verify `## Arbiter Decision: {V}` format | Deep |
| Decision references a principle or precedent | SOFT | Human judgment on appeal | Deep |

### Documenter

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| Plan file status set to COMPLETED | HARD | Verify status field updated | Standard+ |
| YAML workflow log created and valid | HARD | Verify file exists, mandatory fields present | Standard+ |
| Provenance markers verified on all AI-touched files | HARD | Scan changed files for markers | Standard+ |
| Retro snippet generated in `retros/auto/` | HARD | Verify file created with required fields | Standard+ |
| Architecture docs updated (if new modules/ports) | SOFT | Self-check: applicable only if new elements | Deep |

### Researcher

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| Every factual claim has a source URL | HARD | Self-verify: no unsourced assertions | Standard+ |
| No credentials or tokens in fetched URLs | HARD | Grep output for secret patterns | Standard+ |
| Output is structured brief, not raw content | HARD | Self-verify: no verbatim page dumps | Standard+ |
| Sources are authoritative (official docs preferred) | SOFT | Consumer (planner/human) judges | Standard+ |
| Retrieval timestamp noted per source | ADVISORY | Informs staleness assessment | Standard+ |

### Compliance-Checker

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| Pre-flight: branch not on main/master | HARD | Check branch name | Standard+ |
| Pre-flight: plan directory resolved | HARD | Verify directory exists | Standard+ |
| Pre-flight: work-item first (tracker active) | HARD | When `ADO_CAPABILITY_MODE != off`: a resolved work item exists, is Active, and its id prefixes the branch slug | Standard+ |
| Post-flight: plan file status = COMPLETED | HARD | Read plan file, check status field | Standard+ |
| Post-flight: workflow log YAML exists | HARD | Check `.github/logs/{workflow-id}.yaml` | Standard+ |
| Post-flight: retro snippet exists | HARD | Check `retros/auto/{workflow-id}.md` | Standard+ |
| Post-flight: integration path matches capability mode | HARD | If `ADO_CAPABILITY_MODE=required`, a PR was opened; if `off`, no PR worker ran | Standard+ |
| Post-flight: branch-to-work-item association (R-SD-08) | HARD | When tracker capability is active (`ADO_CAPABILITY_MODE != off`): the branch-slug work item id equals the PR-linked work item id (no cross-attribution), the item was Active at work start, and it links the branch + plan path. Tracker off ⇒ local traceability artifact instead. | Standard+ |
| Post-flight: provenance markers on new files | SOFT | Read first 5 lines of new files | Standard+ |

### Ado-Work-Item-Manager

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| Capability classification acknowledged (required/optional) | HARD | Output explicitly states required/optional path | Standard+ |
| Availability probe outcome recorded | HARD | Probe result included (READY/DEGRADED/BLOCKED) | Standard+ |
| Required unavailable => BLOCKED | HARD | If required and unavailable, operation halts with escalation | Standard+ |
| Optional unavailable => fallback artifact | HARD | If optional and unavailable, fallback/pending-sync output exists | Standard+ |
| Board routing applied on create | SOFT | New items set Area Path from `ADO_DEFAULT_AREA_PATH` (and Iteration from `ADO_DEFAULT_ITERATION_PATH`), or the run warns that the project default area is used | Standard+ |
| Type-specific field applicability checked before write | HARD | Before writing a type-specific field (e.g. `AcceptanceCriteria`), the field is confirmed present in the target type's `wit_get_work_item_type` fields; an absent field is not written silently (a type carrying it is chosen, or the content is mirrored to `System.Description` and the path is reported) | Standard+ |
| Non-destructive update policy followed | SOFT | Reviewer checks append/targeted update behavior | Standard+ |
| No Close at finalize (Resolve only, pre-merge) | HARD | Finalize never sets Closed; item is Resolved or kept Active | Standard+ |
| AC coverage map posted before any closure transition | HARD | Verify an AC->evidence map comment exists for the item | Standard+ |
| Closure only against merged evidence | HARD | Closed only post-merge; otherwise `CLOSE_PENDING_MERGE` or `BLOCKED_CLOSURE` | Standard+ |
| AC fully covered (map correctness) | SOFT | Reviewer checks each AC maps to real evidence | Standard+ |
| No bulk-close of linked work items | HARD | Each linked item closed only after its own AC verification | Standard+ |
| Multi-phase detection is deterministic; child closed not parent | HARD | Feature/tag/child signal used; Feature stays open, delivered phase closed via child story | Standard+ |

### Ado-Wiki-Manager

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| Capability classification acknowledged (required/optional) | HARD | Output explicitly states required/optional path | Standard+ |
| Availability probe outcome recorded | HARD | Probe result included (READY/DEGRADED/BLOCKED) | Standard+ |
| Required unavailable => BLOCKED | HARD | If required and unavailable, operation halts with escalation | Standard+ |
| Optional unavailable => fallback artifact | HARD | If optional and unavailable, fallback/pending-sync output exists | Standard+ |
| Existing page read before update | HARD | Update mode includes read-before-write (except create) | Standard+ |
| Change summary quality | SOFT | Reviewer checks traceability and clarity | Standard+ |

### Ado-Pr-Manager

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| No terminal/git operations performed | HARD | Verify the agent used only MCP/read tools (no push/merge) | Standard+ |
| Remote branch present before PR | HARD | Verify source branch exists on remote, or `BLOCKED (branch not published)` reported | Standard+ |
| Target branch resolved | HARD | Verify PR target branch present (default `ADO_DEFAULT_TARGET_BRANCH`) | Standard+ |
| PR created or existing PR updated (no duplicate) | HARD | Verify single active PR for the source branch | Standard+ |
| Work item linked to PR | HARD | Verify work item linked at creation, or `NEEDS_WORKITEM_LINK` reported for deferred linking, or explicit none-with-reason | Standard+ |
| Completion policy applied by target | HARD | Integration branch → autocomplete set; protected/unresolved → human-only, no autocomplete | Standard+ |
| No work-item auto-transition on autocomplete | HARD | The autocomplete call passed `transitionWorkItems: false` (never `true`; the azure-devops-mcp default is `true`) | Standard+ |
| Plan reference attached | SOFT | Reviewer checks clickable URL (remote-verified) or `pending push` fallback | Standard+ |
| Traceability thread posted | SOFT | Reviewer checks a PR thread summarizes work item, plan, and completion mode (idempotent) | Standard+ |
| Reviewers/PR description quality | SOFT | Reviewer checks description completeness and reviewer assignment | Deep |

### Ado-Pipeline-Manager

| Gate | Type | How to Verify | Tier |
|---|---|---|---|
| No terminal/git operations performed | HARD | Verify the agent used only MCP/read tools | Standard+ |
| Pipeline YAML present on the target branch | HARD | `repo_get_file_content` confirms the YAML on the branch | Standard+ |
| Definition registered or reused (no duplicate) | HARD | `pipelines_get_build_definitions` checked before create | Standard+ |
| Run triggered and final status reported | HARD | `pipelines_run_pipeline` + `pipelines_get_build_status` | Standard+ |
| Agent-pool readiness classified | HARD | Distinguish `queued-no-agent` from `started`; report BLOCKED on no agent | Standard+ |
| `ADO_PROJECT` injected on project-aware calls | HARD | Explicit project on every MCP call | Standard+ |
| Build Validation policy settings emitted for human | SOFT | Reviewer checks the policy settings block (buildDefinitionId, isBlocking, branch scopes from `ADO_GATE_BRANCHES`) | Standard+ |
| Never creates/relaxes branch policies or completes PRs | HARD | Verify no policy mutation and no PR completion | Standard+ |

## Agent Exit Protocol

Before returning results, every agent follows this protocol:

1. **Determine the complexity tier** from the plan file (or the coordinator's
   prompt for Trivial Fix and Quick Fix workflows). Default to **Standard** if unclear.
2. **Identify applicable gates** from the Per-Agent Exit Gates table
   above, filtered by the current tier.
3. **Evaluate HARD gates** using the specified verification method.
   - If a HARD gate fails: fix the issue and retry (internally, up to 2
     attempts).
   - If a required tool is unavailable: report the gate as **BLOCKED**.
   - If still failing after retries: report the failure (do not suppress).
4. **Report SOFT gates** as "evaluated" — the reviewer (critic or human)
   decides pass/fail.
5. **Report ADVISORY gates** as metric values.
6. **Include a Gate Summary** in the return format (see below).

## Gate Summary Format

Every agent appends this section to their return:

```markdown
### Gate Summary
- **Tier:** {Trivial | Standard | Deep}
- **HARD gates:** {passed}/{total} passed
- **SOFT gates:** {count} evaluated (reviewer decides)
- **ADVISORY:** {metric_name} = {value}
- **BLOCKED gates:** {list, or "none"}
- **Failed HARD gates:** {list, or "none"}
- **Skills Read:** {list of SKILL.md files read, or "none — no applicable skills"}
```

**Skills Read compliance (producer agents only — test-writer, implementer,
refactorer):** The `Skills Read:` line is a SOFT gate. If missing or empty,
the reviewing critic flags it as a SOFT gate failure. If the producer claims
"none — no applicable skills", that is acceptable — silence is not.

The coordinator uses this summary to decide next actions:
- All HARD passed → proceed to next step
- Any HARD failed → treat as implicit REJECTED (retry or escalate)
- Any HARD BLOCKED → escalate to human
