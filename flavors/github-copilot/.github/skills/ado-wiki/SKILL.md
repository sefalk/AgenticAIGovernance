---
name: ado-wiki
description: Azure DevOps wiki lifecycle guidance — page targeting, non-destructive updates, section evolution, and traceable change summaries.
argument-hint: '[operation: resolve|create|update] [mode: append|section-rewrite|replace]'
disable-model-invocation: true
---

# ADO Wiki Skill

Provider-specific guidance for Azure DevOps wiki page operations.

## Wiki Placement Routing

Azure DevOps has two wiki kinds — route by content scope:

- **Project wiki** (`ADO_WIKI_IDENTIFIER`): general / project-wide content —
  cross-repo overview, operational notes, branch-policy guidance, conventions.
- **Code wiki** (in-repo, `ADO_CODE_WIKI_PATH`, default `docs/wiki`):
  repo-specific docs versioned with the code. Written as Markdown in the code
  repository (commit/PR on the repo's branch), *not* in the project wiki, so
  docs review and version together with the code.

Every repo can publish its own code wiki; the project wiki stays the central
index. `ADO_CODE_WIKI_PATH` is configurable per project in `.github/af-env.conf`.

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

## Protected Wiki (PR-required)

- A direct write that fails with `TF402455` means the wiki's default branch
  (`wikiMaster`) has a PR-required policy. Do not retry the direct write.
- Prefer the PR route: branch off `wikiMaster` in the wiki repo, write the page
  on the branch, open a PR (human completes). Note the known
  `wiki_create_or_update_page` `branch`-param bug (`version '{0}' invalid`) —
  if the branch write fails that way, fall back to a DEGRADED handoff with the
  ready page markdown.
- Never relax the wiki branch policy from an agent; that is a human/UI action.

## Reference Policy

- Use clickable references when verifiable.
- If remote target is unavailable, mark `pending-sync` and provide fallback path.
