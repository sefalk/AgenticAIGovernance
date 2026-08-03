# Workflow Logs

Structured YAML logs for agent workflows. One file per workflow.

## Schema

See the [documenter agent](../agents/documenter.agent.md) for the full YAML schema.

## Conventions

- **Filename:** `<workflow-id>.yaml`
- **Format:** YAML with 2-space indentation
- **Timestamps:** ISO 8601 with timezone (e.g., `2025-01-15T14:30:00Z`)
- **Retention:** 30 days locally, archive if long-term audit needed

## Never committed

The `.gitignore` in this directory keeps every log out of version control. It is
part of the deployed payload, so the rule arrives with the framework instead of
relying on someone adding it to the project's own `.gitignore` — and being
directory-scoped, it cannot clobber that file.

Two independent reasons, either sufficient on its own:

1. **Sensitivity.** `trigger:` holds the user request verbatim. Anything pasted
   into a prompt — a token, a customer name, an internal path — would be
   committed with it.
2. **Irrelevance.** These logs describe how the framework worked, not what the
   project does. They are neither source, nor documentation, nor audit evidence
   for the product.

A `.gitignore` does not untrack files that were committed before it existed.
If `git ls-files .github/logs` returns anything, removing it is a deliberate,
human-owned step — the framework will not do it for you.

## Generating Summaries

Use the workflow-summary prompt:

```
/af-workflow-summary <workflow-id>
```

Or ask the documenter agent directly.
