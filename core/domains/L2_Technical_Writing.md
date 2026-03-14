**Version: 1.0 | Date: 2026-03-04**
**Level: 2 | Domain: Technical Writing**
**Derived from:** [L1_Core_Principles.md](../L1_Core_Principles.md) (Level 1, v3.8)

---

# Level 2 — Technical Writing Domain Rules

## Purpose

This artifact derives domain-specific rules for agent-produced technical documentation from the Level-1 Core Principles. These rules apply whenever an autonomous agent writes, updates, or reviews user-facing documentation (READMEs, API docs, architecture guides, runbooks, changelogs). They are declarative constraints (SHALL/SHALL NOT) that Level-3 workflows must operationalize.

> **Note:** Rule IDs are grouped by their parent L1 principle, not assigned sequentially.

---

## Derived Rules

### From: Verifiability & Quality Assurance (L1)

**R-TW-01:** All code examples in documentation SHALL be tested or extracted from tested source files. Documentation containing code snippets that do not compile or run SHALL be treated as a defect.

**R-TW-02:** API documentation SHALL be generated from annotated source code (e.g., OpenAPI/Swagger, JSDoc, Sphinx autodoc) wherever possible. Hand-written API docs that diverge from the actual implementation SHALL be flagged.

**R-TW-03:** Documentation SHALL be spell-checked and grammar-checked via automated tooling (e.g., `vale`, `alex`, `cspell`) before integration.

### From: Transparency/Traceability (L1)

**R-TW-04:** All documentation SHALL include a "Last Updated" date and the version of the software it describes. Undated documentation SHALL be treated as potentially stale.

**R-TW-05:** Architecture Decision Records (ADRs) SHALL follow a structured template: Title, Status (Proposed/Accepted/Deprecated/Superseded), Context, Decision, Consequences.

**R-TW-06:** Changelogs SHALL follow a structured format (e.g., Keep a Changelog). Every user-facing release SHALL have a corresponding changelog entry.

### From: Safety & Security (L1)

**R-TW-07:** Documentation SHALL NOT contain secrets, internal URLs, customer data, or PII — even in examples. All sample data must use obviously fake values.

**R-TW-08:** Security-sensitive documentation (runbooks for incident response, access procedures) SHALL be access-controlled and SHALL NOT be committed to public repositories.

### From: Fail-Safe & Ask First (L1)

**R-TW-09:** When an agent is uncertain about the accuracy of a technical claim, it SHALL flag the passage with a `[VERIFY]` marker rather than presenting uncertain information as fact.

### From: Separation of Concern (L1)

**R-TW-10:** Documentation SHALL be separated by audience: developer docs (API references, architecture guides) SHALL be distinct from end-user docs (tutorials, user guides, FAQs).

**R-TW-11:** Inline code comments SHALL explain *why*, not *what*. Self-documenting code is preferred over verbose comments that restate the obvious.

### From: Continuous Improvement (L1)

**R-TW-12:** Documentation SHALL be reviewed for accuracy whenever the code it references changes. Stale documentation SHALL be flagged as technical debt per R-SD-18.

---

## Applicability

These rules apply to all documentation produced by agents governed by the AAIG framework: READMEs, API references, architecture docs, runbooks, changelogs, and inline code documentation.

## Relationship to Skills Toolbox

- R-TW-01, R-TW-02, R-TW-04, R-TW-05 → `documentation.md`
- R-TW-03 → `static_analysis.md`
- R-TW-07 → `secrets_management.md`
