---
name: databricks-bundles
description: Databricks Asset Bundles (DABs) — project structure, resource configuration, multi-environment deployment, path resolution, and CI/CD patterns for Databricks workspaces.
argument-hint: '[focus: structure|deploy|resources|targets]'
---

# Databricks Asset Bundles (DABs)

## When to Use

- When a project has a `databricks.yml` file in the root
- When deploying notebooks, jobs, or pipelines to Databricks workspaces
- When configuring multi-environment targets (dev / staging / prod)
- When setting up CI/CD for Databricks artifacts
- When the project uses `databricks bundle` CLI commands

## Discovery Checklist

1. **Does `databricks.yml` exist in the project root?**
   If yes — the project uses DABs.

2. **Is there a `resources/` directory?**
   Check for `*.yml` files defining jobs, pipelines, dashboards.

3. **Is the Databricks CLI installed?**
   ```bash
   databricks --version
   ```

4. **What targets are defined?**
   Read `databricks.yml` for `targets:` section. Each target maps to
   a workspace and deployment mode.

## Bundle Structure

```
project-root/
├── databricks.yml          # Main bundle config
├── resources/              # Resource definitions (optional)
│   ├── jobs.yml
│   ├── pipelines.yml
│   └── dashboards.yml
├── src/                    # Source code deployed to workspace
│   └── notebooks/
└── tests/
```

### Minimal `databricks.yml`

```yaml
bundle:
  name: my-project

targets:
  dev:
    mode: development
    default: true
    workspace:
      host: https://adb-xxx.azuredatabricks.net

  prod:
    mode: production
    workspace:
      host: https://adb-xxx.azuredatabricks.net
    run_as:
      service_principal_name: my-sp@company.com
```

### Development Mode Behaviours

When `mode: development`:
- Resource names are prefixed with `[dev <username>]`
- Jobs get a schedule `pause_status: PAUSED`
- Pipelines get `development: true`
- Permissions and triggers are NOT applied

When `mode: production`:
- Resources deploy with exact names
- Schedules are active
- `run_as` is enforced (use a service principal)

## Resource Configuration

### Jobs

```yaml
# resources/jobs.yml
resources:
  jobs:
    etl_daily:
      name: "[${bundle.target}] Daily ETL"
      schedule:
        quartz_cron_expression: "0 0 8 * * ?"
        timezone_id: Europe/Berlin
      tasks:
        - task_key: extract
          notebook_task:
            notebook_path: ../src/notebooks/extract.py
        - task_key: transform
          depends_on:
            - task_key: extract
          notebook_task:
            notebook_path: ../src/notebooks/transform.py
```

### Pipelines (SDP / DLT)

```yaml
resources:
  pipelines:
    my_pipeline:
      name: "[${bundle.target}] My Pipeline"
      target: my_catalog.my_schema
      libraries:
        - notebook:
            path: ../src/pipeline/
      configuration:
        env: ${bundle.target}
```

### Dashboards

```yaml
resources:
  dashboards:
    usage_dashboard:
      display_name: "[${bundle.target}] Usage Dashboard"
      file_path: ../src/dashboards/usage.lvdash.json
```

## CRITICAL: Path Resolution

Paths in resource YAML files are **relative to the file they're in**:

```
project-root/
├── databricks.yml        # paths relative to project-root
├── resources/
│   └── jobs.yml          # paths relative to resources/
└── src/
    └── notebooks/
        └── etl.py
```

| File | Path to `src/notebooks/etl.py` |
|------|-------------------------------|
| `databricks.yml` | `./src/notebooks/etl.py` |
| `resources/jobs.yml` | `../src/notebooks/etl.py` |

**Common mistake:** Using `./src/...` in `resources/*.yml` — this
resolves to `resources/src/...` which doesn't exist.

## Variable Substitution

```yaml
# Available variables
${bundle.name}            # Bundle name
${bundle.target}          # Current target name (dev, prod)
${workspace.current_user.userName}  # Deploying user
${workspace.root_path}    # Workspace deployment root

# Custom variables
variables:
  catalog:
    default: dev_catalog
  warehouse_id:
    description: SQL warehouse for queries

targets:
  prod:
    variables:
      catalog: prod_catalog
```

## Common Commands

```bash
# Validate bundle syntax
databricks bundle validate

# Deploy to default target
databricks bundle deploy

# Deploy to specific target
databricks bundle deploy --target prod

# Run a specific job
databricks bundle run etl_daily

# Destroy deployed resources (use with caution)
databricks bundle destroy
```

## Multi-Environment Pattern

```yaml
targets:
  dev:
    mode: development
    default: true
    workspace:
      host: https://adb-dev.azuredatabricks.net
    variables:
      catalog: dev_catalog
      schema: ${workspace.current_user.userName}

  staging:
    workspace:
      host: https://adb-staging.azuredatabricks.net
    variables:
      catalog: staging_catalog
      schema: shared

  prod:
    mode: production
    workspace:
      host: https://adb-prod.azuredatabricks.net
    run_as:
      service_principal_name: prod-sp@company.com
    variables:
      catalog: prod_catalog
      schema: production
```

## Permissions

```yaml
resources:
  jobs:
    etl_daily:
      permissions:
        - level: CAN_VIEW
          group_name: data-readers
        - level: CAN_MANAGE_RUN
          group_name: data-engineers
        - level: IS_OWNER
          service_principal_name: prod-sp@company.com
```

| Resource | Permission Levels |
|----------|------------------|
| Jobs | CAN_VIEW, CAN_MANAGE_RUN, IS_OWNER, CAN_MANAGE |
| Pipelines | CAN_VIEW, CAN_RUN, CAN_MANAGE, IS_OWNER |
| Dashboards | CAN_READ, CAN_EDIT, CAN_RUN, CAN_MANAGE |

## Agent-Specific Guidance

### For the Planner

- Check `databricks.yml` early to understand the deployment model.
- Note which targets exist — this determines environment strategy.
- Factor bundle deployment as a subtask when modifying notebook code.

### For the Implementer

- Use `../src/` paths in `resources/*.yml` files (not `./src/`).
- Use `${bundle.target}` in resource names for environment clarity.
- Never hardcode workspace hosts or cluster IDs — use variables.

### For the Code-Critic

- Verify path resolution is correct for all `notebook_path` references.
- Check that production targets use `run_as` with a service principal.
- Flag any hardcoded cluster IDs, warehouse IDs, or workspace paths.

## Quality Gates

| Gate | Type | How to Verify |
|------|------|---------------|
| `databricks bundle validate` passes | HARD | Run CLI command, check exit code |
| No hardcoded cluster/warehouse IDs | HARD | `grep -rn` for ID patterns in YAML |
| Prod target uses `run_as` SP | SOFT | Review `databricks.yml` targets |
| Path resolution correct | HARD | Verify `../src/` in `resources/` files |
| Variables used for environment-specific values | SOFT | No literal catalog/schema in resources |

## References

- Databricks Asset Bundles: https://docs.databricks.com/dev-tools/bundles/index.html
- Bundle configuration reference: https://docs.databricks.com/dev-tools/bundles/settings.html
