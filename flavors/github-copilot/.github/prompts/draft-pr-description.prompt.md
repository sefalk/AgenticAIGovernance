---
name: draft-pr-description
description: 'Generate a PR title, description, and quality gate checklist from the current branch workflow artifacts (plan file, YAML log, gate summaries).'
argument-hint: 'Optional: target branch (default: main), PR template style'
tools:
  - search
  - read
  - execute/runInTerminal
  - execute/getTerminalOutput
  - read/terminalLastCommand
  - read/terminalSelection
---

# Draft PR Description

Assemble a ready-to-paste PR description from the workflow artifacts on the
current branch. This command **only outputs text** — it never creates a PR,
pushes code, or interacts with any remote.

## Step 1: Gather Artifacts

Search the current branch for workflow artifacts:

1. **Plan file** in the plan directory (e.g., `docs/plans/{type}-{date}-{slug}.md`)
   -> task context, subtasks, acceptance criteria
2. **`.github/logs/*.yaml`** -> workflow log with step summaries, metrics
3. **Git log** -> commits on this branch (run `git log --oneline main..HEAD`)
4. **Changed files** -> run `git diff --name-only main` (or appropriate base)

If no plan file is found (Quick Fix workflow), derive context from commit
messages and the YAML log.

## Step 2: Extract Key Information

From the gathered artifacts, extract:

- **Title:** from plan file heading or first commit message
- **Context:** from plan file Context section
- **Changes:** from plan subtasks (completed) + git diff file list
- **Test results:** from YAML log or plan file metrics
- **Quality gates:** from YAML log gate summary or plan file quality gates
- **ADRs:** any new ADR files in `docs/adrs/`
- **Breaking changes:** any changes to public APIs, schemas, or contracts

## Step 3: Generate PR Description

Produce the description in this format (adjust to match project conventions
if a PR template exists in `.github/PULL_REQUEST_TEMPLATE.md`):

```markdown
## {PR Title}

### Context
{Why this change was needed -- from plan file context section}

### What Changed
{Bullet list of changes, grouped by subtask or module}

### Files Changed
{Grouped by type: source, tests, docs, config}

### Quality Gate Results

| Gate | Result |
|---|---|
| All tests pass | ✅ |
| Line coverage | {X}% (target: {Y}%) |
| Branch coverage | {X}% (target: {Y}%) |
| Architecture compliance | ✅ |
| Security checklist | ✅ |
| Provenance markers | ✅ |

### Test Summary
- Tests added: {count}
- Tests modified: {count}
- All passing: ✅

### Reviewers Should Focus On
{List any SOFT gates that passed on judgment only, any areas where
the code-critic had concerns, or any deviations from the plan}

### Related
- ADR: {link if applicable}
- Plan: see plan file in `docs/plans/` on this branch
- Workflow log: `.github/logs/{workflow-id}.yaml`

### Checklist
- [ ] Tests pass locally
- [ ] Coverage meets thresholds
- [ ] Architecture boundaries respected
- [ ] No secrets in code
- [ ] Provenance markers present
```

## Step 4: Present to Human

Output the complete PR description as a code block that the human can
copy-paste into their PR tool (Azure DevOps, GitHub, GitLab, etc.).

If any artifact was missing, note it:
> ⚠️ No plan file found -- description derived from commit messages only.

If the human specified a target branch other than `main`, adjust the
git diff base accordingly.
