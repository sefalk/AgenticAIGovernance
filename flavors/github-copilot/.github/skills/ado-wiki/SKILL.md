---
name: ado-wiki
description: Azure DevOps wiki lifecycle guidance — page targeting, non-destructive updates, section evolution, and traceable change summaries.
argument-hint: '[operation: resolve|create|update] [mode: append|section-rewrite|replace]'
disable-model-invocation: true
---

# ADO Wiki Skill

Provider-specific guidance for Azure DevOps wiki page operations.

## Target Resolution

1. Resolve wiki identifier and page path.
2. Read existing page before updates.
3. Use explicit update mode:
   - append
   - section-rewrite
   - full-replace (only when explicitly requested)

## Non-Destructive Policy

- Keep surrounding sections unchanged for partial updates.
- Preserve rationale/history sections unless obsolete by instruction.
- Emit concise change summary suitable for tracker linking.

## Reference Policy

- Use clickable references when verifiable.
- If remote target is unavailable, mark `pending-sync` and provide fallback path.
