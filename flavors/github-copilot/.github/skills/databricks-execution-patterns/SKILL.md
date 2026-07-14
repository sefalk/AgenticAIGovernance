---
name: databricks-execution-patterns
description: 'Deterministic Databricks workflow orchestration — metastore detection, run-type selection, output retrieval, evidence gating, and cluster management. Framework-agnostic patterns for reliable execution.'
---

# Databricks Execution Patterns

## Purpose

Provide deterministic runbook patterns for Databricks job and notebook execution
to reduce trial-and-error loops, clarify tool choices, and enforce evidence gating.

This skill is designed as framework-agnostic and project-independent. It defines
**patterns and decision rules**, not project-specific configuration (jobs, clusters, profiles).
Projects must provide configuration via `.github/af-env.conf` or equivalent.

## When to Use This Skill

- Before executing any Databricks workload from VS Code (jobs, notebooks, diagnostics)
- When determining UC vs hive_metastore mode
- When choosing between defined jobs and ad-hoc runs
- When troubleshooting execution timeouts or cluster issues
- When evidencing run outcomes for decision-critical investigations

## Common Failure Patterns (Databricks-General)

1. Re-running commands without changing failure mode (spinner loops).
2. Using wrong metastore APIs (`catalogs list` in hive_metastore workspace).
3. Confusing parent run output with task run output in multi-task jobs.
4. Accessing job by name instead of explicit ID.
5. Using wrong cluster type (`existing_cluster_id` with job clusters).
6. Posting completion updates before evidence criteria are proven.

## Pre-Flight Checklist (Per Execution Session)

Before running any Databricks workload:

1. **Authenticate and verify profile:**
   ```
   databricks auth profiles -p <profile>
   databricks jobs list -p <profile> --output json | head -c 50
   ```
   (Tests auth + profile exists without full list cost)

2. **Profile selection discipline (critical):**
  - Never auto-select a profile when multiple profiles exist.
  - List available profiles and let user choose explicitly.
  - Use explicit profile on every command (`-p <profile>` or `--profile <profile>`).
  - Do not rely on implicit shell state for profile selection.

3. **Determine metastore mode:**
   - Will this task need table/catalog operations?
  - If NO: skip to step 4
   - If YES: run capability probe (see section below)

4. **Define run objectives and success criteria:**
   - PASS condition: What indicates success?
   - FAIL condition: What is the expected negative-test failure?

## Metastore Mode Detection (UC vs hive_metastore)

### Is the Distinction Necessary?

Yes, when workflow touches metadata or object discovery (tables, catalogs, schemas).
Not required for basic job submission/polling.

### Probe Strategy (Recommended Order)

**1. Metastores API (universal, works in both UC and hive):**
```powershell
$probe = databricks metastores list -p <profile> --output json 2>&1
if ($LASTEXITCODE -eq 0) { 
  # Succeeded → UC-aware workspace
  $mode = "unity_catalog"
}
```

**2. Fallback: Notebook-based probe (if metastores API unavailable):**
- Submit a notebook cell: `SELECT current_catalog()`
- UC workspace: returns catalog name
- hive_metastore workspace: error

### Interpretation

1. If metastores list succeeds OR notebook returns current_catalog → **`unity_catalog` mode**
2. If both fail with `No metastore assigned` or `Metastore not found` → **`hive_metastore` mode**
3. If fail for unrelated reasons (auth, network, permission), retry once
4. If retry still fails for unrelated, treat as infrastructure failure → **escalate**

**CRITICAL:** Never use `databricks catalogs list` as probe. It is UC-exclusive
and fails in hive_metastore workspaces with "Catalogs not supported", not "No metastore assigned".

Record the detected mode in run notes and evidence comments.

## Run-Type Decision Framework

Before submitting any workload, answer these deterministically:

### Question 1: Does a Defined Job Already Exist?

**YES** → Use **Defined Job Path** (see below)
**NO** → Use **Ad-hoc Path** (see below)

**Job Discovery:**
- Consult your project's job registry (format varies: `.github/af-env.conf`, `docs/databricks-jobs.md`, etc.)
- Job IDs must be explicitly configured, not guessed
- If uncertain whether a job covers the request, treat as NO

### Question 2: Are Run Objectives Clear?

- PASS condition: defined?
- Negative test (FAIL) condition: defined?

**NO** → Stop, clarify with human before proceeding
**YES** → Proceed to Question 3

### Question 3: Is This Decision-Critical?

Decision-critical = influences release, architecture, risk acceptance, or policy

**YES** → Evidence artifact mandatory (DBExperiments or equivalent)
**NO** → Standard evidence gate

## Defined Job Path (Preferred When Available)

### Prerequisites

- Job ID is in your project's registry
- Job status is enabled (not deprecated)
- Job parameters accept required inputs

### Execution

1. Retrieve job ID from registry
2. Trigger: `databricks jobs run-now <job-id> -p <profile> ... --output json`
3. Capture parent `run_id`
4. Proceed with polling and output retrieval (see below)
5. Record job-id, run-id, timestamp in evidence

### Post-Execution Governance

If this request recurs and no defined job covered it, create backlog task
to promote ad-hoc to defined job.

## Ad-hoc Submit Path (Controlled Exception)

### Prerequisites

- No suitable defined job exists
- Run objective and criteria are clear

### Execution

```
databricks jobs submit -p <profile> ... --no-wait --output json
```

1. Capture `run_id`
2. Poll status: `databricks jobs get-run <run_id> -p <profile>`
3. Retrieve output (see Output Retrieval Rules below)

### Governance

Track in work item or log as candidate for later promotion.
If repeated > 1x, create promotion task.

## Cluster Strategy

### For Short Diagnostic Runs

- Prefer running all-purpose cluster (faster startup than job cluster)
- Use cluster ID from project config

### If Run Stuck in PENDING

Decision tree:

```
Run in PENDING state > 60 seconds?
  YES → Is cluster startup known to be slow?
    YES → Cancel run
         → Retry with fallback cluster (all-purpose instead of job cluster)
         → Max 1 retry
    NO → Let run continue (normal startup time)
  NO → Continue waiting
```

After 1 retry, escalate. Do not loop indefinitely.

**Important:** Do not use `existing_cluster_id` with job clusters;
only all-purpose or job cluster creation (new_cluster).

## Output Retrieval Rules

### Single-Task Runs

**Parent run output is sufficient and reliable.**

```
databricks jobs get-run-output <run_id> -p <profile>
```

### Multi-Task Runs

**Parent run output is metadata-only. Retrieve from task run IDs.**

1. Get parent run details: `databricks jobs get-run <run_id>`
2. Extract `tasks[].run_id` for each task
3. For each task: `databricks jobs get-run-output <task_run_id>`

### Evidence Capture

Record in work-item or log:
- Parent run ID
- [if multi-task] Task run IDs and task names
- Lifecycle state (RUNNING, SUCCEEDED, FAILED, INTERNAL_ERROR, etc.)
- Error type/message (if failed) or success marker

## Evidence Gating for Work-Item Updates

### Do Not Mark Complete Unless

1. **PASS run** reached expected success state (exit 0 or status=SUCCEEDED)
2. **Negative test run** failed for expected reason (not unrelated infrastructure blocker)

### Checklist: Distinguish Expected Failure from Blocker

- [ ] Is error message related to test logic (assertion, expected condition)?
- [ ] Or is it infrastructure (missing table, auth error, cluster not ready, timeout)?

| Error Type | Action |
|---|---|
| Test logic (expected) | Document reason, proceed |
| Infrastructure (blocker) | Fix issue, retry test |

### If Gates Not Met

1. Update work item as ACTIVE (not RESOLVED)
2. Post blocker details: run-id, task-id, error message
3. Do NOT post completion/closure wording

## Cluster and Resource Management

### Configuration Expectations

Projects must provide in `.github/af-env.conf` or equivalent:
- `DATABRICKS_PROFILE` — authentication context
- `DATABRICKS_FALLBACK_CLUSTER_ID` — all-purpose cluster for PENDING recovery
- `DATABRICKS_JOB_<NAME>` — explicit job IDs (registry)

### Cluster Validation (Optional per Project)

If your project has a deployment hook, validate:
- Fallback cluster exists and is all-purpose type
- Fallback cluster has minimum CPU/memory for diagnostics
- Job cluster definitions do not use `existing_cluster_id`

## PowerShell Error Handling (Structured)

When parsing Databricks CLI output in PowerShell:

```powershell
$result = databricks jobs get-run $runId -p $profile --output json 2>&1
if ($LASTEXITCODE -ne 0) {
  if ($result -match "not found|not exist") { 
    # Handle 404
  }
  elseif ($result -match "unauthorized|forbidden") { 
    # Handle auth error
  }
  elseif ($result -match "timeout|deadline") { 
    # Handle timeout
  }
  else { 
    # Handle other errors
  }
}
```

Do not mix stderr and stdout into single JSON parse.

## Databricks CLI Version Requirement

**Minimum: Databricks CLI >= 0.292.0**

For Lakeflow Jobs-heavy workflows, prefer CLI `>= 1.0.0`.

Supports:
- `jobs run-now` (required for defined job path)
- `metastores list` (required for UC/hive detection)
- `--output json` with proper exit codes

Check version:
```
databricks --version
```

## Unity Catalog CLI Guardrails (Common CLI Pitfalls)

Use positional arguments for UC schema/table commands.

Correct examples:
```
databricks schemas list <CATALOG> -p <profile>
databricks tables list <CATALOG> <SCHEMA> -p <profile>
databricks tables get <CATALOG>.<SCHEMA>.<TABLE> -p <profile>
```

Incorrect examples (do not use):
```
databricks schemas list --catalog-name <CATALOG>
databricks tables list --catalog <CATALOG>
```

Non-existent command family pitfalls:
```
databricks sql-warehouses list
databricks execute-statement
databricks sql execute
```

Prefer:
```
databricks warehouses list -p <profile>
```

When uncertain, check command help first:
```
databricks <command> --help
```

## Minimal Command Playbook

```
1. databricks auth profiles -p <profile>
2. databricks metastores list -p <profile> --output json       # probe
3. databricks jobs run-now <job-id> -p <profile> --output json # preferred
4. databricks jobs submit -p <profile> --no-wait --output json  # fallback
5. databricks jobs get-run <run_id> -p <profile>               # poll
6. databricks jobs get-run-output <task_run_id> -p <profile>   # retrieve
7. databricks jobs cancel-run <run_id> -p <profile>            # only if stuck
```

## Integration with Agent Framework

### Coordinator

- Invoke Databricks Execution Pre-Flight before any Databricks-heavy workflow
- Ensure Run-Type Decision Checklist is answered and recorded
- Escalate after 1 repeated failure mode (not indefinite retry)

### Implementer

- Read this skill before executing Databricks tasks
- Enforce Run-id discipline (capture before judging success/failure)
- Do not claim verification complete unless evidence gates are met

### Evidence & Work-Item Management

- Record run-id, task-id, mode (UC/hive), and outcome in work items
- Use `[RUN_TYPE_DECISION]` tag to mark decision point
- Use `[ESCALATION_CHECK]` template for S/M/L classification

## When to Escalate

Escalate to human when:

1. Same failure mode repeats after one strategy change
2. Missing prerequisite data invalidates both PASS and FAIL objectives
3. Infrastructure failure unrelated to test logic (auth, cluster, network)
4. Destructive operation required (drop, clear) without explicit approval
