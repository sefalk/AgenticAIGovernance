---
name: databricks-apps
description: Build Python web applications on Databricks — Dash, Streamlit, Gradio, Flask, FastAPI framework patterns, OAuth auth, SQL warehouse/Lakebase connectivity, and deployment via CLI or Asset Bundles.
argument-hint: '[focus: framework|auth|data-access|deploy]'
---

# Databricks Apps

Build and deploy Python web applications on Databricks with managed
compute, auth, and data access.

## When to Use

- When building dashboards or data apps on Databricks
- When creating REST APIs backed by Delta Lake / SQL warehouse
- When deploying Streamlit, Dash, Gradio, Flask, or FastAPI apps
- When integrating apps with model serving endpoints

## Framework Selection

| Framework | Best For | Production Command |
|-----------|----------|--------------------|
| **Dash** | Production dashboards, complex interactivity | `["python", "app.py"]` |
| **Streamlit** | Rapid prototyping, data science apps | `["streamlit", "run", "app.py"]` |
| **Gradio** | ML demos, model interfaces, chat UIs | `["python", "app.py"]` |
| **Flask** | Custom REST APIs, webhooks | `["gunicorn", "app:app", "-w", "4"]` |
| **FastAPI** | Async APIs, auto-generated OpenAPI docs | `["uvicorn", "app:app", "--host", "0.0.0.0"]` |

**Default:** Streamlit for prototypes, Dash for production dashboards,
FastAPI for APIs, Gradio for ML demos.

## Project Structure

```
my-app/
├── app.py                 # Main application
├── models.py              # Pydantic data models
├── backend.py             # Data access layer
├── requirements.txt       # Additional dependencies
├── app.yaml               # Databricks Apps config
└── README.md
```

## app.yaml Configuration

```yaml
command: ["streamlit", "run", "app.py"]
env:
  - name: DATABRICKS_WAREHOUSE_ID
    valueFrom: "warehouse_id"   # Injected from workspace resource
  - name: APP_ENV
    value: "production"
```

## Authentication

### App Auth (Service Principal)

```python
from databricks.sdk.core import Config

# Auto-detects credentials from environment
# (DATABRICKS_CLIENT_ID / DATABRICKS_CLIENT_SECRET injected by runtime)
cfg = Config()
```

### User Auth (On-Behalf-Of)

```python
# User token forwarded by Databricks Apps runtime
def get_user_token(request):
    return request.headers.get("x-forwarded-access-token")
```

**Note:** User auth requires workspace admin to enable and is only
available when deployed (not locally).

## Data Access Patterns

### SQL Warehouse Connection

```python
import os
from databricks.sdk.core import Config
from databricks import sql

cfg = Config()
conn = sql.connect(
    server_hostname=cfg.host,
    http_path=f"/sql/1.0/warehouses/{os.getenv('DATABRICKS_WAREHOUSE_ID')}",
    credentials_provider=lambda: cfg.authenticate,
)

cursor = conn.cursor()
cursor.execute("SELECT * FROM catalog.schema.table LIMIT 100")
rows = cursor.fetchall()
```

### Lakebase (PostgreSQL)

For transactional / low-latency workloads:

```python
import os
import psycopg2

# Auto-injected env vars: PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD
conn = psycopg2.connect(
    host=os.getenv("PGHOST"),
    port=os.getenv("PGPORT"),
    dbname=os.getenv("PGDATABASE"),
    user=os.getenv("PGUSER"),
    password=os.getenv("PGPASSWORD"),
)
```

**Note:** `psycopg2` / `asyncpg` are NOT pre-installed — add to
`requirements.txt`.

### Backend Toggle Pattern

```python
import os

USE_MOCK = os.getenv("USE_MOCK_BACKEND", "true").lower() == "true"

if USE_MOCK:
    from backend_mock import MockBackend as Backend
else:
    from backend_real import RealBackend as Backend

backend = Backend()
```

## Deployment

### CLI

```bash
# Create app
databricks apps create my-app

# Deploy
databricks apps deploy my-app --source-code-path ./my-app/

# Check status
databricks apps get my-app

# View logs
databricks apps logs my-app
```

### Asset Bundles (DABs)

```yaml
# databricks.yml or resources/apps.yml
resources:
  apps:
    my_app:
      name: my-dashboard
      source_code_path: ../src/app/
      config:
        command: ["streamlit", "run", "app.py"]
        env:
          - name: DATABRICKS_WAREHOUSE_ID
            valueFrom: warehouse_id
```

```bash
databricks bundle deploy
```

## Platform Constraints

| Constraint | Detail |
|------------|--------|
| Runtime | Python 3.11, Ubuntu 22.04 |
| Compute | 2 vCPU, 6 GB RAM (default) |
| Pre-installed | Dash 2.18, Streamlit 1.38, Gradio 4.44, Flask 3.0, FastAPI 0.115 |
| Port | Must use `DATABRICKS_APP_PORT` env var (default 8000) |
| Network | Apps reach Databricks APIs; external depends on workspace config |

## Common Issues

| Issue | Solution |
|-------|----------|
| Connection exhausted | Use `@st.cache_resource` (Streamlit) or connection pooling |
| Auth token missing | `x-forwarded-access-token` only available when deployed |
| App won't start | Check `app.yaml` command matches framework |
| Resource inaccessible | Add resource via UI, verify SP permissions |
| Port conflict | Use `DATABRICKS_APP_PORT` env var, not hardcoded 8080 |
| Slow queries | Use Lakebase for transactional, SQL warehouse for analytical |

## Quality Gates

| Gate | Type | How to Verify |
|------|------|---------------|
| Uses `Config()` not hardcoded creds | HARD | Grep for tokens/passwords |
| Uses `valueFrom` for resource IDs | HARD | Check app.yaml |
| Production uses Gunicorn/uvicorn | HARD | Check app.yaml command |
| requirements.txt includes all deps | SOFT | Test deploy |

## References

- Databricks Apps: https://docs.databricks.com/aws/en/dev-tools/databricks-apps/
- Apps Cookbook: https://apps-cookbook.dev/
- app.yaml Reference: https://docs.databricks.com/aws/en/dev-tools/databricks-apps/app-runtime
