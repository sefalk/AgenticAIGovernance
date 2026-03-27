---
name: databricks-connect
description: Use Databricks Connect, Python SDK, and CLI to interact with Unity Catalog workspaces — session setup, table verification, schema discovery, serverless configuration, SDK API patterns, and migration patterns for Hive-to-UC transitions.
argument-hint: '[focus: setup|verify|migrate|unity-catalog|cli|sdk]'
---

# Databricks Connect, SDK & Unity Catalog

## When to Use

- When a project uses Databricks and has `databricks-connect` or
  `databricks-sdk` installed
- When migrating from Hive Metastore to Unity Catalog
- When verifying table existence, schema access, or permissions
- When configuring SparkSession for remote Databricks execution
- When using the Python SDK for workspace management (clusters, jobs,
  warehouses, secrets, volumes, serving endpoints)
- When the researcher cannot access external documentation (auth-gated
  wikis, internal portals) but the data is queryable via Databricks

## Discovery Checklist

Before planning any Databricks-related task, agents **must** check:

1. **Is `databricks-connect` installed?**
   ```bash
   pip show databricks-connect
   ```

2. **Is `databricks-sdk` installed?**
   ```bash
   pip show databricks-sdk
   ```

3. **Is there a Databricks CLI profile?**
   ```bash
   cat ~/.databrickscfg
   ```

4. **Is there a `databricks.yml` bundle config?**
   Look in the project root for workspace host, cluster ID, or
   serverless settings.

5. **Are there environment variables?**
   ```bash
   env | grep DATABRICKS
   ```

If any of these exist, the project has Databricks tooling available.
**Do not declare external data as "blocked on human"** without first
attempting programmatic verification via CLI, SDK, or Connect.

## Databricks CLI for Verification

The Databricks CLI can verify Unity Catalog objects without a running
cluster or serverless session. This is the **preferred first approach**
for table verification because it requires only REST API auth (no
compute).

### Common Verification Commands

```bash
# List catalogs (verify Unity Catalog access)
databricks --profile <PROFILE> catalogs list

# Check if a specific table exists (returns JSON metadata)
databricks --profile <PROFILE> tables get "<catalog>.<schema>.<table>"

# List tables in a schema (verify schema access)
databricks --profile <PROFILE> tables list "<catalog>" "<schema>"

# List schemas in a catalog
databricks --profile <PROFILE> schemas list "<catalog>"

# Check permissions on a schema
databricks --profile <PROFILE> grants get SCHEMA "<catalog>.<schema>"
```

### Error Patterns

| Error | Meaning | Action |
|-------|---------|--------|
| `User does not have USE SCHEMA` | Missing schema-level permission | Request GRANT from DBA |
| `CATALOG_DOES_NOT_EXIST` | Catalog name wrong or no access | Verify catalog name in mapping |
| `TABLE_DOES_NOT_EXIST` | Table not found | Check table name spelling / schema |
| `PERMISSION_DENIED` on Spark Connect | No serverless compute access | Use CLI instead, or request access |

## Databricks Connect Sessions

### Configuration Sources (priority order)

1. **Environment variables:** `DATABRICKS_HOST`, `DATABRICKS_TOKEN`,
   `DATABRICKS_CLUSTER_ID`
2. **`.databrickscfg` profiles:** `~/.databrickscfg` with `[PROFILE]`
   sections
3. **`databricks.yml` bundle:** workspace host, target configs
4. **Programmatic:** `DatabricksSession.builder.host(...).token(...)`

### Session Setup Patterns

```python
from databricks.connect import DatabricksSession

# Profile-based (reads ~/.databrickscfg)
spark = DatabricksSession.builder.profile("PROFILE").getOrCreate()

# Profile + serverless (no cluster ID needed)
spark = DatabricksSession.builder.profile("PROFILE").serverless(True).getOrCreate()

# Profile + specific cluster
spark = DatabricksSession.builder.profile("PROFILE").clusterId("0327-123456-abc").getOrCreate()

# Explicit configuration
spark = (DatabricksSession.builder
    .host("https://adb-xxx.azuredatabricks.net")
    .token("dapi...")
    .getOrCreate())
```

### Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Cluster id or serverless are required` | No cluster ID and serverless not enabled | Add `.serverless(True)` or `.clusterId(...)` |
| `PERMISSION_DENIED: Cannot access Spark Connect` | Auth valid but no compute permission | Request serverless/cluster access, or use CLI for read-only checks |
| `databricks-cli auth_type` with no token | OAuth/CLI auth expired | Re-authenticate via `databricks auth login --profile PROFILE` |

## Databricks Python SDK (WorkspaceClient)

The SDK provides typed Python access to all Databricks REST APIs. Use it
for workspace management tasks that don't require Spark execution.

**Install:** `pip install databricks-sdk`
**Docs:** https://databricks-sdk-py.readthedocs.io/en/latest/

### Authentication

```python
from databricks.sdk import WorkspaceClient

# Auto-detect credentials from environment / .databrickscfg
w = WorkspaceClient()

# Explicit profile
w = WorkspaceClient(profile="MY_PROFILE")

# Explicit token auth
w = WorkspaceClient(
    host="https://adb-xxx.azuredatabricks.net",
    token="dapi..."
)

# Azure Service Principal
w = WorkspaceClient(
    host="https://adb-xxx.azuredatabricks.net",
    azure_workspace_resource_id="/subscriptions/.../providers/Microsoft.Databricks/workspaces/...",
    azure_tenant_id="...",
    azure_client_id="...",
    azure_client_secret="..."
)
```

### Unity Catalog — Tables, Schemas, Catalogs

```python
# List catalogs
for catalog in w.catalogs.list():
    print(catalog.name)

# List schemas in a catalog
for schema in w.schemas.list(catalog_name="my-catalog"):
    print(schema.name)

# List tables in a schema
for table in w.tables.list(catalog_name="my-catalog", schema_name="my-schema"):
    print(f"{table.full_name}: {table.table_type}")

# Get table metadata (columns, type, location)
table = w.tables.get(full_name="catalog.schema.table")
print([c.name for c in table.columns])

# Check table existence
exists = w.tables.exists(full_name="catalog.schema.table")
```

### SQL Statement Execution

Execute SQL without Spark Connect — uses a SQL warehouse:

```python
response = w.statement_execution.execute_statement(
    warehouse_id="abc123",
    statement="SELECT * FROM catalog.schema.table LIMIT 10",
    wait_timeout="30s"
)

from databricks.sdk.service.sql import StatementState
if response.status.state == StatementState.SUCCEEDED:
    for row in response.result.data_array:
        print(row)
```

### Jobs API

```python
from databricks.sdk.service.jobs import Task, NotebookTask

# List jobs
for job in w.jobs.list():
    print(f"{job.job_id}: {job.settings.name}")

# Run a job and wait for completion
run = w.jobs.run_now_and_wait(job_id=123)
print(f"Completed: {run.state.result_state}")
```

### Clusters & Warehouses

```python
# List clusters
for cluster in w.clusters.list():
    print(f"{cluster.cluster_name}: {cluster.state}")

# List SQL warehouses
for wh in w.warehouses.list():
    print(f"{wh.name}: {wh.state}")
```

### Volumes & Files

```python
# List volumes
for vol in w.volumes.list(catalog_name="cat", schema_name="schema"):
    print(vol.full_name)

# Upload file to volume
w.files.upload(
    file_path="/Volumes/catalog/schema/volume/data.csv",
    contents=open("local_file.csv", "rb")
)
```

### Secrets

```python
# List secret scopes
for scope in w.secrets.list_scopes():
    print(scope.name)

# Get a secret value
secret = w.secrets.get_secret(scope="my-scope", key="api-key")
```

### Direct REST API Access

For API endpoints not yet in the SDK:

```python
# GET request
response = w.api_client.do(method="GET", path="/api/2.0/clusters/list")

# POST with body
response = w.api_client.do(
    method="POST",
    path="/api/2.0/jobs/run-now",
    body={"job_id": 123}
)
```

### SDK Documentation URL Pattern

```
Base: https://databricks-sdk-py.readthedocs.io/en/latest/
Workspace APIs:  /workspace/{category}/{service}.html
Account APIs:    /account/{category}/{service}.html
```

| Category | Services |
|----------|----------|
| `compute` | clusters, cluster_policies, command_execution, instance_pools |
| `catalog` | catalogs, schemas, tables, volumes, functions, storage_credentials |
| `jobs` | jobs |
| `sql` | warehouses, statement_execution, queries, alerts, dashboards |
| `serving` | serving_endpoints |
| `pipelines` | pipelines |
| `workspace` | repos, secrets, workspace, git_credentials |
| `files` | files, dbfs |

### CRITICAL: Async Applications

The Databricks SDK is **fully synchronous**. In async code (FastAPI,
asyncio), wrap SDK calls with `asyncio.to_thread()`:

```python
import asyncio
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()

# WRONG — blocks the event loop
async def bad():
    return list(w.clusters.list())

# CORRECT — runs in thread pool
async def good():
    return await asyncio.to_thread(lambda: list(w.clusters.list()))
```

## Unity Catalog Migration Patterns

### Table Reference Formats

| Format | Example | Context |
|--------|---------|---------|
| **2-level (Hive)** | `schema.table` | Legacy Hive Metastore |
| **3-level (UC)** | `catalog.schema.table` | Unity Catalog |
| **Explicit HMS** | `hive_metastore.schema.table` | Transitional — reads from old HMS via UC |

### Migration Strategy: Centralized Config

Create a single module for all catalog/schema/table constants:

```python
"""Unity Catalog table references."""

# Catalog
UC_CATALOG = "my-catalog"

# Read schemas (may differ per data domain)
UC_READ_EVENTLOG = f"{UC_CATALOG}.eventlog_schema.eventlog_table"
UC_READ_METADATA = f"{UC_CATALOG}.info_schema.metadata_table"

# Write schema
UC_WRITE_SCHEMA = f"{UC_CATALOG}.workzone"
UC_WRITE_PREFIX = UC_WRITE_SCHEMA  # for table_name = f"{UC_WRITE_PREFIX}.my_table"
```

**Key insight:** In Unity Catalog, read tables and write tables often
live in **different schemas** (or even different catalogs). Do not
assume a single shared schema. Each table constant should be fully
qualified with its own `catalog.schema.table` path.

### API Migration

| Old (Hive) | New (UC-compatible) | Notes |
|------------|---------------------|-------|
| `spark.catalog._jcatalog.tableExists(t)` | `spark.catalog.tableExists(t)` | Private Java API → public Python API |
| `spark._jsparkSession.catalog().tableExists(t)` | `spark.catalog.tableExists(t)` | Same fix |
| `spark.sql("USE DATABASE db")` | `spark.sql("USE SCHEMA catalog.schema")` | `DATABASE` → `SCHEMA` in UC |
| `DeltaTable.forName(spark, "schema.table")` | `DeltaTable.forName(spark, "catalog.schema.table")` | Works with 3-level names |
| `df.write.saveAsTable("schema.table")` | `df.write.saveAsTable("catalog.schema.table")` | Works with 3-level names |

### Verification Workflow

When migrating tables, verify **before** committing code changes:

1. **List target catalogs** via CLI (`catalogs list`) — confirm access
2. **Check each table** via CLI (`tables get`) — confirms existence and
   permissions without compute
3. **Test a SELECT** via Connect (if compute available) — confirms data
   access end-to-end
4. **Check write permissions** via CLI (`tables list` on write schema)

If CLI returns `PERMISSION_DENIED`, record the exact schema and
escalate to the DBA. Do not guess or use placeholder values.

### Workspace Path Migration

Databricks notebooks reference workspace paths for `%run` and
`%pip install`. These paths change when migrating workspaces:

```python
# Old workspace
%run /Workspace/Users/user@company.com/utils/DBSecrets.py

# New workspace (same user, different workspace instance)
%run /Workspace/Users/user@company.com/utils/DBSecrets.py
```

**Note:** Workspace user paths typically remain the same across
workspaces (they're based on user identity, not workspace ID). The
path only changes if the repository or file structure differs in the
new workspace. Verify with:

```bash
databricks --profile <PROFILE> workspace list /Workspace/Users/<email>/
```

## Agent-Specific Guidance

### For the Researcher

When external documentation is auth-gated (Azure DevOps wikis, internal
portals), check if the information can be obtained programmatically:

- **Table mappings** → `databricks tables get` / `tables list`
- **Schema structure** → `databricks schemas list`
- **Access permissions** → `databricks grants get`

### For the Planner

- Always include a "verify infrastructure" subtask before any migration
  implementation subtask.
- Do not declare table names as "human blocker" if Databricks
  CLI/Connect is available — try verification first.
- Factor in permission issues as risks (some schemas may require GRANT
  requests).

### For the Implementer

- Use the centralized config module pattern for table references.
- Replace all private Spark Java API calls (`_jcatalog`, `_jsparkSession`)
  with public Python API equivalents.
- Test table existence with `spark.catalog.tableExists()` (not the
  Java catalog accessor).

### For the Code-Critic

- Flag any remaining 2-level table references in source code.
- Flag any `_jcatalog` or `_jsparkSession` private API usage.
- Verify that the centralized config module has no I/O imports (it
  should contain only string constants).

## Quality Gates

| Gate | Type | How to Verify |
|------|------|---------------|
| No 2-level table refs in source | HARD | `grep -rn "schema\.table"` pattern |
| No private Java API calls | HARD | `grep -rn "_jcatalog\|_jsparkSession"` |
| All UC tables verified via CLI/SDK | HARD | CLI `tables get` or SDK `tables.get()` returns metadata |
| Centralized config has no I/O | HARD | No `import pyspark` / `import databricks` |
| SDK calls async-safe in async code | HARD | All SDK calls wrapped in `asyncio.to_thread()` |
| No hardcoded tokens/secrets | HARD | No `dapi` strings or plaintext tokens in source |
| Permission issues documented | SOFT | Risk register updated |
