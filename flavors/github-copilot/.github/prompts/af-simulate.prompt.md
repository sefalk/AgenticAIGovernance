---
name: af-simulate
description: 'Dry-run a task through the coordinator decision tree — predict workflow steps, agents, gates, and escalation risks without executing anything.'
argument-hint: 'Describe the task to simulate (e.g., "add bucketing for AQC telegrams")'
tools:
  - search
  - read
---

# Workflow Simulation (Dry Run)

Preview how the coordinator would handle a task **without invoking any
subagents or making any changes**. This is a read-only planning exercise.

## Step 1: Analyse the Task

Read the user's task description. Identify:

- **Task type:** new feature, bug fix, refactoring, documentation, review
- **Keywords:** extract domain concepts, file names, module names mentioned

## Step 2: Discover Affected Scope

Search the codebase to estimate:

- **Files likely affected:** list specific files with paths
- **Layers touched:** domain core / ports / adapters / orchestrators / config
- **New elements needed:** any new modules, ports, or adapter patterns?

## Step 3: Select Workflow

Based on the coordinator's workflow selection rules:

| Workflow | Criteria |
|---|---|
| Full TDD | Default for new features, refactoring |
| Quick Fix | Small bug fix, < 3 files, low risk |
| Review Only | User asks to review existing code |
| Plan Only | User asks to analyse or plan |

State which workflow would be selected and why.

## Step 4: Assign Complexity Tier

Using the quality gate system (`quality-gates.instructions.md`):

| Tier | When |
|---|---|
| Trivial | ≤ 2 files, no logic changes |
| Standard | 3–5 files, within existing architecture |
| Deep | 6+ files or new architectural elements |

Apply the layer override: domain core or ports → minimum Standard.
State the tier and reasoning.

## Step 5: Predict Workflow Execution

For the selected workflow, list each step:

```markdown
### Predicted Steps

1. **Planner** → decompose into {N} subtasks
   - Key subtasks: {list}
   - Estimated plan complexity: {small/medium/large}
   - Plan file: `docs/plans/{type}-{date}-{slug}.md`

2. **Test-writer** → create tests for {files}
   - Expected test count: ~{N}
   - Test types: unit / property / parametrized

3. **Test-critic** → review test quality
   - Likely focus areas: {what critic will scrutinise}

4. **Implementer** → modify {files}
   - Key changes: {summary}
   - Coverage target: {per module type from MANIFEST § 5}

5. **Refactorer** → clean up {if applicable}

6. **Code-critic** → review
   - Gates to check: {list applicable HARD gates}
   - Potential rejection areas: {what might fail}

7. **Documenter** -> plan file finalisation + YAML log
```

For Quick Fix, show only: Implementer → Code-critic → Documenter.

## Step 6: Identify Risks and Escalation Triggers

Check against the coordinator's mandatory escalation triggers:

- [ ] 4+ subtasks requiring human plan approval?
- [ ] New architectural element (port, adapter pattern)?
- [ ] Cross-layer changes (> 2 layers)?
- [ ] High-risk files (planner flags as "high")?
- [ ] Security-sensitive changes?
- [ ] Destructive actions (file deletion, schema changes)?

State which triggers might fire and at which step.

## Step 7: Suggest Parallelisation Opportunities

If the plan has independent subtasks:

- Which test files could be written in parallel?
- Which implementation subtasks have no dependencies?

## Output Format

```markdown
## 🔍 Simulation Result

### Task
{one-line summary}

### Predicted Workflow
**Type:** {Full TDD | Quick Fix | Review Only}
**Complexity tier:** {Trivial | Standard | Deep}
**Estimated agents invoked:** {count}

### File Impact
- {file} — {what changes}

### Step Sequence
{numbered list from Step 5}

### Risk Assessment
- **Plan approval needed:** {yes/no + reason}
- **Escalation triggers:** {list or "none expected"}
- **Highest-risk step:** {which step and why}

### Parallelisation
- {opportunities or "sequential — dependencies prevent parallel execution"}

### Context Feasibility
**Assessment:** {SINGLE-SESSION | MULTI-SESSION | AT-RISK}
- Estimated subagent calls: {N} (including likely retries)
- Context budget prediction: {GREEN throughout | YELLOW by Step N | RED risk}
- Recommendation: {proceed normally | consider --supervised | split into phases}

### Recommendation
{Any advice for the human before starting: "consider splitting into 2 tasks",
"this is straightforward — proceed", etc.}
```

**Context Feasibility rules:**
- **SINGLE-SESSION**: ≤ 7 subagent calls expected, low retry risk → GREEN.
- **MULTI-SESSION**: 8-12 calls expected (retries likely, or 4+ subtasks) →
  YELLOW probable. Suggest `--supervised` for visibility.
- **AT-RISK**: 13+ calls expected, or task complexity suggests multiple
  retry cycles → RED likely. Recommend splitting the task or phased execution.

This assessment is advisory (SOFT) — it does not block execution.
