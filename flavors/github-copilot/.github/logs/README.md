# Workflow Logs

Structured YAML logs for agent workflows. One file per workflow.

## Schema

See the [documenter agent](../agents/documenter.agent.md) for the full YAML schema.

## Conventions

- **Filename:** `<workflow-id>.yaml`
- **Format:** YAML with 2-space indentation
- **Timestamps:** ISO 8601 with timezone (e.g., `2025-01-15T14:30:00Z`)
- **Retention:** 30 days locally, archive if long-term audit needed

## Generating Summaries

Use the workflow-summary prompt:

```
/af-workflow-summary <workflow-id>
```

Or ask the documenter agent directly.
