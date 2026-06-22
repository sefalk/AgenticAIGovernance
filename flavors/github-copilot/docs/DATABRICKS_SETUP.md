# Enabling Databricks Execution Patterns in Your Project

This guide explains how to enable the `databricks-execution-patterns` skill
for your project and configure it for deterministic Databricks workflow execution.

**Version:** 1.0 · **Skill:** `databricks-execution-patterns` · **Updated:** 2026-06-22

## Prerequisites

- Databricks CLI >= 0.213.0 (check with `databricks --version`)
- Authenticated Databricks profile (test with `databricks auth profiles`)
- At least one all-purpose cluster or job cluster in your workspace
- (Optional) Defined Databricks jobs for your project

## Step 1: Enable the Skill (Framework Setup)

The `databricks-execution-patterns` skill is provided as part of the framework.

**Check if active:**
```bash
ls -la .github/skills/databricks-execution-patterns/
```

**If not present:**
- Copy from `flavors/github-copilot/.github/skills/databricks-execution-patterns/SKILL.md`
- Or run `/validate-framework` to auto-discover available skills

**Register in `.github/copilot-instructions.md`:**

Add to the Skills section:

```markdown
| Skill | Directory | Primary Consumer |
|---|---|---|
| **databricks-execution-patterns** | `skills/databricks-execution-patterns/` | implementer, coordinator |
```

## Step 2: Configure Your Project (af-env.conf)

### Copy the Template

```bash
cp templates/af-env.conf.databricks .github/af-env.conf.databricks
```

### Populate the Template

#### 2a. Databricks Job Registry

If your project has defined Databricks jobs, list them here:

```bash
# Find job IDs
databricks jobs list -p <profile_name> --output json | jq '.jobs[] | {name, job_id}'
```

Then add to `.github/af-env.conf`:

```bash
# Copy relevant entries from template and populate
DATABRICKS_JOB_VALIDATION=<actual_job_id>
DATABRICKS_JOB_EVIDENCE_AB=<actual_job_id>
```

**If no defined jobs yet:** Leave placeholders, focus on cluster configuration first.

#### 2b. Fallback Cluster (PENDING Recovery)

This is an all-purpose cluster used when a run is stuck in PENDING > 60s.

```bash
# Find all-purpose clusters
databricks clusters list -p <profile_name> --output json | \
  jq '.clusters[] | select(.cluster_type=="ALL_PURPOSE") | {cluster_id, cluster_name}'
```

Add to `.github/af-env.conf`:

```bash
DATABRICKS_FALLBACK_CLUSTER_ID=0228-152403-ngdzmaae
```

#### 2c. Databricks Profile

This is your authentication context.

```bash
# Verify profile exists
databricks auth profiles -p <profile_name>
```

Add to `.github/af-env.conf`:

```bash
DATABRICKS_PROFILE=SHSXP
```

**If profile doesn't exist, create it:**

```bash
databricks configure --token -p <profile_name>
# Paste your personal access token when prompted
```

### Verify Configuration

Test your configuration:

```powershell
# Source the config (PowerShell)
$env:DATABRICKS_PROFILE = "SHSXP"

# Test auth
databricks auth profiles -p $env:DATABRICKS_PROFILE

# Test cluster access
databricks clusters list -p $env:DATABRICKS_PROFILE --output json | wc -l
```

## Step 3: Agent Configuration

### Coordinator

Update `.github/agents/coordinator.agent.md` to reference the skill:

```markdown
## Databricks Execution Pre-Flight (conditional)

Before any Databricks-heavy work, ensure workers read:
`skills/databricks-execution-patterns/SKILL.md`

Minimum behaviors:
1. Run-Type Decision Checklist before any submit/run-now call
2. Explicit Databricks profile on every CLI call
3. Task-level output retrieval for multi-task runs
4. Evidence gates: PASS + negative-test both met before closure
5. Escalate after 1 repeated failure mode
```

### Implementer

Update `.github/agents/implementer.agent.md`:

```markdown
## Skills

- **databricks-execution-patterns** (`skills/databricks-execution-patterns/SKILL.md`)
  — deterministic run orchestration, output retrieval, and evidence gating

## For Databricks Execution Tasks

6. **Run-id discipline** — capture parent + task run IDs before judging success
7. **Task-level output** — use task run output for multi-task runs
8. **Evidence gate** — do not claim completion unless PASS + negative-test both met
```

### ADO Work-Item Manager

Update `.github/agents/ado-work-item-manager.agent.md` to use S/M/L checklist:

```markdown
## Investigation Classification (S/M/L)

When Databricks investigation work is part of the workflow:

**S - Small check:** operational-only, no mandatory artifact
**M - Medium:** recurring diagnostic, structured notes in WIT
**L - Large:** decision-critical, mandatory DBExperiments artifact + commit

### Escalation Decision

Post WIT comment with `[ESCALATION_CHECK]`:
- Does this affect release? (Y/N)
- Does this affect architecture? (Y/N)
- Would this be needed for compliance? (Y/N)

If 2+ YES → Upgrade to L, require artifact.
```

## Step 4: Validation (Optional Hook)

If your project uses deployment hooks, consider adding a Databricks config validator.

Example hook (`<.github/hooks/check-databricks-config.sh`):

```bash
#!/bin/bash
# Validate Databricks configuration

source .github/af-env.conf

missing=()
[[ -z "$DATABRICKS_PROFILE" ]] && missing+=("DATABRICKS_PROFILE")
[[ -z "$DATABRICKS_FALLBACK_CLUSTER_ID" ]] && missing+=("DATABRICKS_FALLBACK_CLUSTER_ID")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: Missing Databricks config: ${missing[@]}"
  echo "See .github/templates/af-env.conf.databricks for template"
  exit 2
fi

# Test auth
databricks auth profiles -p "$DATABRICKS_PROFILE" > /dev/null 2>&1 || {
  echo "Error: Profile '$DATABRICKS_PROFILE' not found or not authenticated"
  exit 2
}

echo "✓ Databricks config valid"
exit 0
```

## Step 5: First Execution

When you first run a Databricks-backed task:

1. **Coordinator triggers Run-Type Decision Checklist**
   - "Does a defined job exist?" → lists registered jobs
   - "Are objectives clear?" → you confirm PASS/FAIL criteria
   - "Decision-critical?" → determines if DBExperiments required

2. **Implementer applies skill patterns**
   - Probes for UC vs hive_metastore
   - Chooses defined job or ad-hoc submit
   - Polls and retrieves output correctly

3. **Work-Item Manager records evidence**
   - Posts `[RUN_TYPE_DECISION]` in WIT comment
   - If investigation, posts `[ESCALATION_CHECK]` for classification

## Troubleshooting

### "Profile not found"

```bash
databricks auth profiles
databricks configure --token -p <new_profile_name>
```

### "Metastores list" returns error

```bash
# Check if hive_metastore workspace
databricks metastores list --output json | head
# If "No metastore assigned", you're in hive_metastore mode
```

### "Run stuck in PENDING"

1. Verify `DATABRICKS_FALLBACK_CLUSTER_ID` is all-purpose
2. Check cluster is running: `databricks clusters list -p <profile>`
3. If not, coordinator will retry with fallback

### Job not found by ID

```bash
# List and verify job IDs
databricks jobs list --output json | jq '.jobs[] | {name, job_id}'
# Update af-env.conf with correct ID
```

## Migration Path

### From Ad-hoc Experimentation

1. Start with no job registry (step 2a skipped)
2. Run ad-hoc using skill patterns
3. When request recurs 2+ times, promote to defined job
4. Register job in af-env.conf
5. Next execution uses defined job path

### From Existing Databricks Jobs

1. List existing jobs: `databricks jobs list --output json`
2. Register top 3–5 frequently-used jobs in af-env.conf
3. Remaining ad-hoc submissions follow ad-hoc path
4. Gradually formalize ad-hoc → defined

## Next Steps

- Review [databricks-execution-patterns SKILL](../skills/databricks-execution-patterns/SKILL.md)
- Set up your Job Registry (step 2a)
- Run first task with `@coordinator <task>`
- Observe Run-Type Decision Checklist in action
