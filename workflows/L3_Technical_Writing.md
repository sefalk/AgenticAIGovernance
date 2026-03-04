**Version: 1.0 | Date: 2026-03-04**
**Level: 3 | Domain: Technical Writing**
**Derived from:** [L2_Technical_Writing.md](../domains/L2_Technical_Writing.md) (Level 2)
**Operationalizes:** R-TW-01, R-TW-02, R-TW-03, R-TW-04, R-TW-05, R-TW-06, R-TW-08, R-TW-10, R-TW-12

---

# L3 Workflow — Technical Writing

## Purpose

This workflow defines the standard procedure for producing agent-authored documentation: API references, READMEs, guides, Architecture Decision Records (ADRs), changelogs, and runbooks. Its key differentiator from generic writing is the mandatory code-example verification step — all code samples must demonstrably execute before publication.

> **Adaptation Note:** Bind `[L4-DEFINED]` placeholders during L4 Project Instantiation.

---

## Phases

### Phase 1: Gather Context
**Entry Criteria:** A documentation request exists (new feature shipped, ADR needed, README outdated, runbook missing).

1. **Check for an existing WIP contract:** If a `WIP.md` file exists on the current branch, read it first and resume from the last completed step.
2. Identify the **audience** for this document (R-TW-08):
   - Developer (internal, technical depth expected)
   - Operator (deployment/ops focus)
   - End-user (no assumed technical knowledge)
3. Identify the **document type** and select the appropriate template:
   - **README**: Overview, quickstart, badge row, installation, usage, contributing, license.
   - **API Reference**: Endpoint/function signature, parameters, return values, errors, examples.
   - **ADR**: Status, Context, Decision, Consequences (R-TW-04).
   - **Runbook**: Trigger, symptoms, investigation steps, resolution, escalation path.
   - **Changelog**: Per-version entries: Added, Changed, Deprecated, Removed, Fixed, Security.
4. Collect the primary source material (code, PR descriptions, architecture diagrams, previous docs).
5. Mark any facts not directly verifiable from source as `[VERIFY]` (R-TW-05). These must be resolved before publishing.

**Exit Criteria:** Audience is defined, template is selected, source material is gathered, `[VERIFY]` markers are placed.

---

### Phase 2: Draft
**Entry Criteria:** Phase 1 is complete.

1. Write the document using the selected template and audience level.
2. **Every code block** must be a real, runnable example — not pseudocode (R-TW-01).
3. For API docs: document every parameter type, whether it is required/optional, and at least one request + response example (R-TW-03).
4. Apply consistent terminology from the project glossary `[L4-DEFINED: glossary path]` (R-TW-10).
5. If writing an ADR, document the **rejected alternatives** and why they were not chosen (R-TW-06).

**Exit Criteria:** Draft is complete, all code examples are written, `[VERIFY]` markers are in place for uncertain facts.

---

### Phase 3: Verify Examples
**Entry Criteria:** Phase 2 draft is complete.

1. For each code block in the document:
   - Run it using `[L4-DEFINED: doctest command]` (e.g., `python -m doctest`, `node -e`, `pytest --doctest-modules`, or copy-paste and execute in a scratch environment).
   - If the code block fails or produces unexpected output, fix either the code or the surrounding explanation.
2. Resolve all `[VERIFY]` markers: look up the fact in the source code, docs, or specification, replace the marker with the verified information.
3. If a `[VERIFY]` item cannot be resolved, escalate to the human User before publishing (R-TW-05, R-SD-26).

**Exit Criteria:** All code examples execute successfully, zero unresolved `[VERIFY]` markers.

---

### Phase 4: Review
**Entry Criteria:** Phase 3 verification passes.

1. Create a PR/diff with the documentation changes.
2. The review should check:
   - Does the document match the target audience's knowledge level?
   - Is it accurate relative to the current code?
   - Are there any inconsistencies with other documentation?
3. For ADRs: at least one other human or agent familiar with the context must acknowledge the decision (R-TW-06).

**Exit Criteria:** PR is reviewed and approved.

---

### Phase 5: Publish
**Entry Criteria:** Phase 4 review is approved.

1. Merge the documentation to the main branch.
2. If the documentation is generated (e.g., OpenAPI, Sphinx, mdBook), trigger the regeneration pipeline.
3. Update internal links and cross-references to point to the new document.
4. If an outdated document is being replaced, redirect or archive the old version to avoid dead links (R-TW-12).

**Exit Criteria:** Documentation is merged, pipeline is triggered, old links are resolved.

---

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| **Code examples verified** | 100% | R-TW-01: no untested code blocks |
| **`[VERIFY]` markers resolved** | 0 remaining | R-TW-05: no unverified claims |
| **Audience level appropriate** | Pass review | R-TW-08: no jargon for end-users |
| **ADR alternatives documented** | If ADR | R-TW-06: rejected options included |
| **Broken links** | 0 | R-TW-12: no dead internal links |

---

## Mid-Task Interruption Protocol

If the agent must end a session before completing all phases, it MUST commit a `WIP.md` file to the current branch:

```markdown
# Work In Progress
**Last Phase Completed:** [Phase N]
**Last Step Completed:** [exact step description]
**Next Step:** [exact next step to execute]
**Open Decisions:** [any unresolved design choices]
**Blockers:** [any blockers preventing progress — including unresolved [VERIFY] items]
```

A resuming agent MUST read `WIP.md` in Phase 1 Step 1. The file is deleted when the PR is merged.
