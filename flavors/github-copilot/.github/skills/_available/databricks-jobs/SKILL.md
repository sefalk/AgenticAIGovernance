---
name: databricks-jobs
description: Databricks Lakeflow Jobs — multi-task DAG workflows, scheduling, triggers, compute configuration, notifications, and monitoring. SDK, CLI, and Asset Bundle patterns.
argument-hint: '[focus: create|schedule|monitor|triggers|parameters]'
---

# Databricks Lakeflow Jobs

Orchestrate data workflows with multi-task DAGs, flexible triggers,
and comprehensive monitoring.

## When to Use

- When scheduling notebook or Python script execution
- When building multi-task ETL/ELT workflows with dependencies
- When setting up file arrival or table update triggers
- When configuring job alerting and monitoring
- When deploying production data pipelines

## Task Types

| Task Type | Use Case | Key Config |
|-----------|----------|------------|
| `notebook_task` | Run notebooks | `notebook_path`, `source` |
| `spark_python_task` | Run .py scripts | `python_file`, `parameters` |
| `python_wheel_task` | Run wheel packages | `package_name`, `entry_point` |
| `sql_task` | Run SQL queries | `warehouse_id`, `query`/`file` |
| `pipeline_task` | Trigger SDP/DLT pipelines | `pipeline_id` |
| `run_job_task` | Trigger other jobs | `job_id` |
| `for_each_task` | Loop over inputs | `inputs`, `task` |

## Trigger Types

| Trigger | When | Config |
|---------|------|--------|
| `schedule` (cron) | Time-based | `quartz_cron_expression`, `timezone_id` |
| `trigger.periodic` | Interval-based | `interval`, `unit` |
| `trigger.file_arrival` | New files in cloud storage | `url`, `min_time_between_triggers` |
| `trigger.table_update` | UC table changes | `table_names`, `condition` |
| `continuous` | Always running | `pause_status` |

## Asset Bundles (Recommended)

### Single-Task Job

```yaml
# resources/jobs.yml
resources:
  jobs:
    daily_etl:
      name: "[${bundle.target}] Daily ETL"
      schedule:
        quartz_cron_expression: "0 0 8 * * ?"
        timezone_id: Europe/Berlin
      tasks:
        - task_key: run_notebook
          notebook_task:
            notebook_path: ../src/notebooks/etl.py
```

### Multi-Task DAG

```yaml
resources:
  jobs:
    etl_pipeline:
      name: "[${bundle.target}] ETL Pipeline"
      tasks:
        - task_key: extract
          notebook_task:
            notebook_path: ../src/notebooks/extract.py

        - task_key: transform
          depends_on:
            - task_key: extract
          notebook_task:
            notebook_path: ../src/notebooks/transform.py

        - task_key: load
          depends_on:
            - task_key: transform
          run_if: ALL_SUCCESS
          notebook_task:
            notebook_path: ../src/notebooks/load.py

        - task_key: notify_on_failure
          depends_on:
            - task_key: load
          run_if: AT_LEAST_ONE_FAILED
          notebook_task:
            notebook_path: ../src/notebooks/alert.py
```

**`run_if` conditions:**
- `ALL_SUCCESS` (default) — all dependencies succeeded
- `ALL_DONE` — all dependencies completed (any status)
- `AT_LEAST_ONE_SUCCESS` — at least one dependency succeeded
- `NONE_FAILED` — no dependencies failed
- `ALL_FAILED` / `AT_LEAST_ONE_FAILED` — failure-based routing

### File Arrival Trigger

```yaml
resources:
  jobs:
    file_triggered:
      name: "[${bundle.target}] File Arrival Job"
      trigger:
        file_arrival:
          url: s3://my-bucket/incoming/
          min_time_between_triggers_seconds: 600
      tasks:
        - task_key: process_files
          notebook_task:
            notebook_path: ../src/notebooks/ingest.py
```

### Table Update Trigger

```yaml
resources:
  jobs:
    table_triggered:
      name: "[${bundle.target}] Table Change Job"
      trigger:
        table_update:
          table_names:
            - catalog.schema.source_table
          condition: ANY_UPDATED
      tasks:
        - task_key: process_update
          notebook_task:
            notebook_path: ../src/notebooks/process.py
```

## Compute Configuration

### Job Clusters (Shared Across Tasks)

```yaml
job_clusters:
  - job_cluster_key: shared_cluster
    new_cluster:
      spark_version: "15.4.x-scala2.12"
      node_type_id: "Standard_DS3_v2"
      num_workers: 2
      autotermination_minutes: 20

tasks:
  - task_key: my_task
    job_cluster_key: shared_cluster
    notebook_task:
      notebook_path: ../src/notebook.py
```

### Serverless (No Cluster Config)

```yaml
tasks:
  - task_key: serverless_task
    notebook_task:
      notebook_path: ../src/notebook.py
    # Omit cluster config = serverless
```

### Autoscaling

```yaml
new_cluster:
  autoscale:
    min_workers: 1
    max_workers: 8
```

## Python SDK

```python
from databricks.sdk import WorkspaceClient
from databricks.sdk.service.jobs import Task, NotebookTask, Source

w = WorkspaceClient()

# Create job
job = w.jobs.create(
    name="my-etl-job",
    tasks=[
        Task(
            task_key="extract",
            notebook_task=NotebookTask(
                notebook_path="/Workspace/Users/user@company.com/extract",
                source=Source.WORKSPACE
            )
        )
    ]
)
print(f"Created job: {job.job_id}")

# Run and wait
run = w.jobs.run_now_and_wait(job_id=job.job_id)
print(f"Result: {run.state.result_state}")

# Run with parameters
w.jobs.run_now(
    job_id=123,
    job_parameters={"env": "prod", "date": "2026-03-27"}
)

# List jobs
for job in w.jobs.list():
    print(f"{job.job_id}: {job.settings.name}")
```

## CLI

```bash
# Create job from JSON
databricks jobs create --json '{ "name": "my-job", "tasks": [...] }'

# Run job
databricks jobs run-now 12345

# Run with parameters
databricks jobs run-now 12345 --job-params '{"env": "prod"}'

# List jobs
databricks jobs list

# Deploy via bundle
databricks bundle deploy
databricks bundle run my_job
```

## Job Parameters

```yaml
# Define parameters with defaults
parameters:
  - name: env
    default: "dev"
  - name: date
    default: "{{start_date}}"

# Access in notebook
# dbutils.widgets.get("env")
```

## Permissions

```yaml
permissions:
  - level: CAN_VIEW
    group_name: data-analysts
  - level: CAN_MANAGE_RUN
    group_name: data-engineers
  - level: CAN_MANAGE
    user_name: admin@company.com
```

| Level | Capabilities |
|-------|-------------|
| `CAN_VIEW` | View job and run history |
| `CAN_MANAGE_RUN` | Trigger and cancel runs |
| `CAN_MANAGE` | Full control (edit, delete) |

## Common Issues

| Issue | Solution |
|-------|----------|
| Schedule not triggering | Check `pause_status: UNPAUSED` and timezone |
| Task dependency wrong | Verify `task_key` names match exactly in `depends_on` |
| Parameter not accessible | Use `dbutils.widgets.get()` in notebooks |
| File arrival silent | Ensure cloud storage path has correct permissions |
| Slow cluster startup | Use job clusters or serverless |

## Quality Gates

| Gate | Type | How to Verify |
|------|------|---------------|
| Bundle validates | HARD | `databricks bundle validate` |
| Job has appropriate permissions | SOFT | Review permissions in YAML |
| Production jobs use `run_as` SP | SOFT | Check for `run_as` in prod target |
| Triggers configured correctly | SOFT | Verify cron/interval/file patterns |

## References

- Jobs API: https://docs.databricks.com/api/workspace/jobs
- Jobs Documentation: https://docs.databricks.com/en/jobs/index.html
- DABs Job Tasks: https://docs.databricks.com/en/dev-tools/bundles/job-task-types.html
