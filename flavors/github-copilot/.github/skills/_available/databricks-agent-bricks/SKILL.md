---
name: databricks-agent-bricks
description: Databricks Agent Bricks — Knowledge Assistants (RAG), Genie Spaces (NL-to-SQL), and Supervisor Agents (multi-agent orchestration) for conversational AI applications.
argument-hint: '[focus: knowledge-assistant|genie|supervisor|tools]'
---

# Agent Bricks

Pre-built AI components for building conversational applications on
Databricks.

## When to Use

- When building document Q&A systems (Knowledge Assistants)
- When creating natural language to SQL interfaces (Genie Spaces)
- When orchestrating multiple agents (Supervisor Agents)
- When integrating UC functions, vector search, or MCP servers as tools

## Brick Types

| Brick | Purpose | Data Source |
|-------|---------|-------------|
| **Knowledge Assistant (KA)** | Document-based Q&A using RAG | PDF/text files in Volumes |
| **Genie Space** | Natural language to SQL | Unity Catalog tables |
| **Supervisor Agent (MAS)** | Multi-agent orchestration | Serving endpoints + Genie |

## Knowledge Assistant (KA)

RAG-based Q&A over documents stored in Unity Catalog Volumes.

### Setup

1. Upload documents to a UC Volume
2. Create the KA (via UI or SDK)
3. KA indexes documents automatically
4. Query via serving endpoint

### SDK Pattern

```python
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()

# KA is managed through the serving endpoints
# after creation via UI or Databricks Apps

# Query the KA endpoint
response = w.serving_endpoints.query(
    name="my-knowledge-assistant",
    messages=[{"role": "user", "content": "What is our return policy?"}],
    max_tokens=500
)
```

### Prerequisites

- Documents in a UC Volume (PDF, text, HTML, Markdown)
- Vector search index (created automatically by KA)
- Serving endpoint (provisioned automatically)

## Genie Space

Natural language interface over Unity Catalog tables — users ask
questions in plain English, Genie translates to SQL.

### Setup

1. Identify UC tables for exploration
2. Create Genie Space (via UI)
3. Add sample questions for guidance
4. Curate with instructions and certified queries

### Best Practices

- **Table selection:** Choose well-documented tables with clear column names
- **Sample questions:** Provide 5-10 example questions showing what users can ask
- **Certified queries:** Pre-approve common query patterns for accuracy
- **Instructions:** Guide the SQL generation (e.g., "Always filter by active status")

## Supervisor Agent (MAS)

Orchestrates multiple agents — routes user queries to the right
specialist agent based on the query intent.

### Architecture

```
User Query → Supervisor Agent
                ├── Knowledge Assistant (document Q&A)
                ├── Genie Space (SQL analytics)
                ├── Custom ML Endpoint (classification)
                ├── UC Function (data enrichment)
                └── MCP Server (external system)
```

### Agent Types in Supervisor

| Agent Source | Config Key | Use Case |
|-------------|-----------|----------|
| Knowledge Assistant | `ka_tile_id` | Document Q&A |
| Genie Space | `genie_space_id` | SQL-based data queries |
| Serving Endpoint | `endpoint_name` | Custom ML models/agents |
| UC Function | `uc_function_name` | Deterministic operations |
| MCP Server | `connection_name` | External system integration |

### Routing Instructions

```
Route queries as follows:
1. Policy/procedure questions → knowledge_base
2. Data analysis requests → analytics_engine
3. Classification tasks → ml_classifier
4. Customer lookups → data_enrichment
5. Ticket operations → ticket_system

If a query spans multiple domains, chain agents:
- First gather information (analytics or knowledge)
- Then take action (operations)
```

## UC Functions as Tools

Register Python functions in Unity Catalog for agents to call:

```sql
CREATE OR REPLACE FUNCTION catalog.schema.lookup_customer(
  customer_id STRING
)
RETURNS TABLE (name STRING, tier STRING, email STRING)
LANGUAGE SQL
RETURN SELECT name, tier, email
       FROM catalog.schema.customers
       WHERE customer_id = lookup_customer.customer_id;
```

**Agent SP needs:** `EXECUTE` privilege on the function.

## Vector Search for RAG

```python
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()

# Create vector search index
w.vector_search_indexes.create_index(
    name="catalog.schema.doc_index",
    primary_key="doc_id",
    index_type="DELTA_SYNC",
    delta_sync_index_spec={
        "source_table": "catalog.schema.documents",
        "embedding_source_columns": [{"name": "content"}],
        "pipeline_type": "TRIGGERED",
    }
)

# Search
results = w.vector_search_indexes.query_index(
    index_name="catalog.schema.doc_index",
    query_text="return policy details",
    columns=["doc_id", "content", "title"],
    num_results=5
)
```

## Provisioning

New KA and MAS bricks need time to provision:

| Status | Meaning |
|--------|---------|
| `PROVISIONING` | Being created (2-5 minutes) |
| `ONLINE` | Ready to use |
| `OFFLINE` | Not running |

## Quality Gates

| Gate | Type | How to Verify |
|------|------|---------------|
| Documents in managed UC Volume | HARD | Volume path starts with `/Volumes/` |
| Vector search index synced | HARD | Check index status |
| Supervisor routing tested | SOFT | Verify each agent type receives queries |
| Sample questions provided | SOFT | Genie/KA has examples |

## References

- Agent Bricks: https://docs.databricks.com/en/generative-ai/agent-bricks/
- Genie Spaces: https://docs.databricks.com/en/genie/
- Vector Search: https://docs.databricks.com/en/generative-ai/vector-search/
- UC Functions: https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-udf.html
