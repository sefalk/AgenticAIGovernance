---
name: databricks-unity-catalog
description: Unity Catalog system tables, volumes, lineage, audit logs, billing analysis, and data governance — query patterns for monitoring, compliance, and data profiling.
argument-hint: '[focus: system-tables|volumes|lineage|audit|billing]'
---

# Unity Catalog — System Tables & Governance

## When to Use

- When querying system tables (audit logs, lineage, billing, compute)
- When working with volumes (upload, download, list files)
- When tracking data lineage (table/column dependencies)
- When analysing billing and DBU consumption
- When monitoring job execution and query performance
- When profiling data quality or detecting drift

## System Tables

System tables live in the `system` catalog. Access requires explicit grants.

### Enable Access

```sql
GRANT USE CATALOG ON CATALOG system TO `data_engineers`;
GRANT USE SCHEMA ON SCHEMA system.access TO `data_engineers`;
GRANT SELECT ON SCHEMA system.access TO `data_engineers`;
```

### Table Lineage

```sql
-- What tables feed into this table?
SELECT source_table_full_name, source_column_name,
       target_column_name, event_date
FROM system.access.table_lineage
WHERE target_table_full_name = 'catalog.schema.my_table'
  AND event_date >= current_date() - 7
ORDER BY event_date DESC;

-- Column-level lineage
SELECT source_table_full_name, source_column_name,
       target_table_full_name, target_column_name
FROM system.access.column_lineage
WHERE target_table_full_name = 'catalog.schema.my_table'
  AND event_date >= current_date() - 7;
```

### Audit Logs

```sql
-- Recent permission changes
SELECT event_time, user_identity.email, action_name, request_params
FROM system.access.audit
WHERE (action_name LIKE '%GRANT%' OR action_name LIKE '%REVOKE%')
  AND event_date >= current_date() - 30
ORDER BY event_time DESC
LIMIT 100;

-- Who accessed a specific table?
SELECT event_time, user_identity.email, action_name
FROM system.access.audit
WHERE request_params.full_name_arg = 'catalog.schema.my_table'
  AND event_date >= current_date() - 7
ORDER BY event_time DESC;
```

### Billing & Usage

```sql
-- DBU usage by workspace (last 30 days)
SELECT workspace_id, sku_name,
       SUM(usage_quantity) AS total_dbus,
       COUNT(DISTINCT usage_date) AS active_days
FROM system.billing.usage
WHERE usage_date >= current_date() - 30
GROUP BY workspace_id, sku_name
ORDER BY total_dbus DESC;

-- Cost trend by day
SELECT usage_date, sku_name,
       SUM(usage_quantity) AS daily_dbus
FROM system.billing.usage
WHERE usage_date >= current_date() - 90
GROUP BY usage_date, sku_name
ORDER BY usage_date;
```

### Compute Usage

```sql
-- Cluster utilisation
SELECT cluster_id, cluster_name,
       SUM(uptime_seconds) / 3600 AS uptime_hours,
       AVG(driver_node_utilization) AS avg_driver_util
FROM system.compute.clusters
WHERE usage_date >= current_date() - 30
GROUP BY cluster_id, cluster_name
ORDER BY uptime_hours DESC;
```

### Query History

```sql
-- Slow queries
SELECT statement_id, executed_by, duration_ms,
       warehouse_id, LEFT(statement_text, 200) AS query_preview
FROM system.query.history
WHERE start_time >= current_date() - 7
  AND duration_ms > 60000  -- > 1 minute
ORDER BY duration_ms DESC
LIMIT 50;
```

### Job Execution

```sql
-- Job run history
SELECT job_id, run_id, run_name, result_state,
       execution_duration_ms / 1000 AS duration_seconds
FROM system.lakeflow.job_run_timeline
WHERE period_start_time >= current_date() - 7
ORDER BY period_start_time DESC;
```

## Volumes

Volumes provide managed file storage in Unity Catalog.

### CLI Operations

```bash
# List volumes
databricks volumes list catalog.schema

# List files in a volume
databricks fs ls /Volumes/catalog/schema/volume_name/

# Upload file
databricks fs cp local_file.csv /Volumes/catalog/schema/volume_name/

# Download file
databricks fs cp /Volumes/catalog/schema/volume_name/file.csv ./local/
```

### SDK Operations

```python
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()

# List volumes
for vol in w.volumes.list(catalog_name="cat", schema_name="schema"):
    print(vol.full_name)

# Upload file
w.files.upload(
    file_path="/Volumes/catalog/schema/volume/data.csv",
    contents=open("local_file.csv", "rb")
)

# Download file
resp = w.files.download(file_path="/Volumes/catalog/schema/volume/data.csv")
with open("local_copy.csv", "wb") as f:
    f.write(resp.contents.read())
```

### SQL Operations

```sql
-- Create a volume
CREATE VOLUME IF NOT EXISTS catalog.schema.raw_data;

-- Read files from a volume
SELECT * FROM read_files('/Volumes/catalog/schema/raw_data/*.csv');

-- Copy into a table
COPY INTO catalog.schema.my_table
FROM '/Volumes/catalog/schema/raw_data/'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'true');
```

## Data Profiling

```sql
-- Table-level profile: row count, column stats
DESCRIBE EXTENDED catalog.schema.my_table;

-- Compute table statistics
ANALYZE TABLE catalog.schema.my_table COMPUTE STATISTICS;

-- Column-level stats
ANALYZE TABLE catalog.schema.my_table
COMPUTE STATISTICS FOR COLUMNS col1, col2, col3;
```

## Best Practices

1. **Filter by date** — system tables can be large; always use date predicates
2. **Use appropriate retention** — check workspace retention settings
3. **Grant minimal access** — system tables contain sensitive metadata
4. **Schedule reports** — create scheduled queries for regular monitoring
5. **Volumes over DBFS** — prefer managed volumes for new file storage

## Quality Gates

| Gate | Type | How to Verify |
|------|------|---------------|
| System table queries have date filters | HARD | Check WHERE clauses |
| Volume paths use 3-level UC format | HARD | `/Volumes/catalog/schema/volume/` |
| Audit queries use appropriate scope | SOFT | Not overly broad |
| Billing queries anonymise where needed | SOFT | No PII in reports |

## References

- System Tables: https://docs.databricks.com/administration-guide/system-tables/
- Audit Logs: https://docs.databricks.com/administration-guide/account-settings/audit-logs.html
- Volumes: https://docs.databricks.com/en/connect/unity-catalog/volumes.html
