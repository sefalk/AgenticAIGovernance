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

## Wiki Schema & Conventions

Treat the wiki as a **compounding, LLM-maintained artifact** over an immutable
source of truth (the codebase, ADRs, work items) — not a re-derived dump. Every
page synthesizes and **cites** its sources; never invent facts the sources do
not support.

**Page types** (pick one; enumerated so new-vs-edit is decidable):
`overview`, `concept`, `architecture`, `pipeline`, `data`, `status`,
`ops-note`, `adr-link`.

**Required frontmatter** on every page (enables lint-by-frontmatter):

```yaml
---
title: <page title>
type: <one of the page types above>
description: <one-line summary>
tags: [<controlled vocabulary>]
updated: <YYYY-MM-DD>
sources: [<link to code/ADR/work item>, ...]
---
```

**Controlled vocabulary.** Reuse existing `type`/`tags` values before inventing
new ones — prevents taxonomy drift (`concept` vs `Concept` vs `topic`). When a
new tag is genuinely needed, add it deliberately, not incidentally.

**New page vs. edit heuristic:**

- **New page** when the subject is a distinct entity/concept you would link to
  from elsewhere.
- **Edit in place** when it is an attribute or update of an existing page.

**Minimalism.** Synthesize, don't accumulate — merge overlapping content into
the existing page rather than adding near-duplicate pages. Keep the active
surface small; a smaller, current wiki beats a large, stale one.

> Frontmatter and page-type conventions are advisory for one-off pages but
> expected for any wiki maintained as a growing tree.

## Index & Change Log

- **Index (routing file).** The wiki root page is a catalog: one line per page
  (link + one-line summary), grouped by area. Update the index entry on every
  create. Read the index first to locate pages, then drill in — do not scan
  every page body.
- **Change log.**
  - *Code wikis:* git history **is** the log — no separate `log.md`.
  - *Project wiki:* keep an optional `## Changelog` section with append-only,
    parseable entries: `## [YYYY-MM-DD] <action> | <page/title>`.

## Wiki Health Check (Lint)

When asked to lint / health-check a wiki, run these in order and produce a
report — do **not** silently mutate content pages.

**HARD (deterministic — pass/fail):**

1. **Schema integrity** — every page has the required frontmatter fields.
2. **Broken cross-links** — every internal link resolves to an existing page.
3. **Orphans** — flag pages with zero inbound links.
4. **Duplicates** — flag near-identical titles/paths.

**SOFT (judgment — reviewer decides):**

5. **Staleness** — surface the oldest pages by `updated`; check whether newer
   sources supersede them.
6. **Contradictions** — flag pages that disagree with newer pages.
7. **Overview drift** — flag the overview/index if it lags the newest pages by
   more than one update cycle.
8. **Coverage gaps** — concepts mentioned across pages that lack their own page.

**Hard rules for the lint pass:**

- **Never delete** files unilaterally — flag orphans/duplicates for approval.
- **Never create or rewrite content pages** during a lint pass (that is the
  authoring step). Repairing unambiguous frontmatter is allowed.
- Report a health status (🟢 / 🟡 / 🔴) plus a numbered next-steps list;
  note which steps need human approval.

**Publish gate (maker-checker).** For a growing wiki, authoring and review are
separate: the authoring pass writes/updates pages; a review pass (a critic or a
second instance) runs the deterministic lint **and** a qualitative read before
publish. Do not self-approve structural output — that is a SOFT gate for the
reviewer.

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
