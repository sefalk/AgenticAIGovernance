---
category: devops
applies_to: [all]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-06-11
related: [documentation, configuration_management, ci_cd]
---
# Azure DevOps Wiki Management

## Purpose

Provide provider-specific guidance for Azure DevOps wiki lifecycle
operations (target resolution, create/update, section evolution, and
traceable publication behavior).

## Principles

- **Transparency (AAIG L1):** Wiki updates must produce auditable change
  summaries and stable references.
- **Separation of Concern (AAIG L1):** Keep wiki lifecycle in dedicated
  capability workers, separate from domain implementation workers.
- **Platform Optionality (AAIG L1):** If wiki capability is optional and
  unavailable, produce fallback markdown artifacts and mark pending sync.

## Techniques & Patterns

### Page Target Resolution

1. Resolve wiki identifier and path from context/config.
2. Read existing page before updates.
3. Select update mode: append, section rewrite, or full replace.

### Non-Destructive Content Evolution

- Preserve surrounding headings and prior rationale sections.
- Prefer section-targeted updates over full replacement.
- Use explicit "Changed" bullets for what/why summary.

### Reference Policy

- Prefer clickable references.
- Verify remote target availability before publishing links.
- If unavailable, mark `pending-sync` and include fallback reference path.

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| Target resolved (wiki + path) | 100% | Or explicit confirmation request |
| Existing content read before update | 100% | Except new page creation |
| Non-destructive policy applied | 100% | Update mode logged |
| References valid or pending-sync | 100% | No fabricated links |
| Change summary present | 100% | Suitable for tracker/comment sync |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Full-page overwrite by default | Destroys context and audit history | Use append/section rewrite first |
| Unverified links | Broken references in docs | Verify target or mark pending-sync |
| Implicit page targeting | Updates wrong wiki/path | Resolve explicitly and confirm if ambiguous |

## See Also

- [Documentation](../code_quality/documentation.md)
- [Configuration Management](../devops/configuration_management.md)
- [CI/CD](../devops/ci_cd.md)

## References

- Azure DevOps Wiki API: https://learn.microsoft.com/rest/api/azure/devops/wiki/pages
- Azure DevOps Wiki concepts: https://learn.microsoft.com/azure/devops/project/wiki/wiki-create-repo
