# Rubric: L2 Technical Writing Domain

**Evaluates:** L2 Domain Rules → Technical Writing (12 rules)
**Source:** [L2_Technical_Writing.md](../../../domains/L2_Technical_Writing.md)

---

> This rubric evaluates all 12 R-TW rules. Rules are grouped by parent L1 principle.

---

## From: Verifiability & Quality Assurance

### R-TW-01: Tested Code Examples
| Score | Criteria |
|-------|----------|
| **Pass** | Code examples extracted from tested source files or verified to compile/run |
| **Partial** | Examples mostly correct but contain minor syntax errors |
| **Fail** | Documentation contains non-functional, hallucinated code snippets |

### R-TW-02: Generated API Documentation
| Score | Criteria |
|-------|----------|
| **Pass** | API docs generated from annotated source (Swagger, JSDoc, Sphinx) |
| **Partial** | Mix of generated and hand-written, slightly out of sync |
| **Fail** | Purely hand-written API docs that diverge significantly from implementation |
| **N/A** | Not API documentation |

### R-TW-03: Automated Grammar/Spell Checking
| Score | Criteria |
|-------|----------|
| **Pass** | Documentation verified by automated tooling (vale, cspell) |
| **Fail** | Documentation merged without automated or manual typo/grammar checks |

---

## From: Transparency/Traceability

### R-TW-04: Version and Date Marking
| Score | Criteria |
|-------|----------|
| **Pass** | Documents include "Last Updated" date and target software version |
| **Partial** | Date included but target software version missing |
| **Fail** | Undated, unversioned documentation |

### R-TW-05: Structured ADRs
| Score | Criteria |
|-------|----------|
| **Pass** | ADRs follow template (Title, Status, Context, Decision, Consequences) |
| **Partial** | ADRs exist but omit key sections (like Consequences) |
| **Fail** | Architectural decisions documented as unstructured notes |
| **N/A** | No ADRs required |

### R-TW-06: Structured Changelogs
| Score | Criteria |
|-------|----------|
| **Pass** | Changelog follows structured format (Keep a Changelog) for every release |
| **Fail** | Unstructured, missing, or purely commit-dump changelogs |
| **N/A** | Not a release context |

---

## From: Safety & Security

### R-TW-07: Data Sanitization in Docs
| Score | Criteria |
|-------|----------|
| **Pass** | No secrets, internal URLs, or real PII; fake/dummy data used exclusively in examples |
| **Fail** | Real credentials, internal hostnames, or real customer data leak into docs |

> **Critical Failure.** No partial score.

### R-TW-08: Access Control for Security Docs
| Score | Criteria |
|-------|----------|
| **Pass** | Security runbooks/procedures kept out of public repos with correct access controls |
| **Fail** | Sensitive security procedures committed to accessible/public documentation |

---

## From: Fail-Safe & Ask First

### R-TW-09: Uncertainty Flagging
| Score | Criteria |
|-------|----------|
| **Pass** | Uncertain technical claims are explicitly flagged with `[VERIFY]` |
| **Fail** | Agent hallucinates or presents uncertain system behavior as absolute fact |

---

## From: Separation of Concern

### R-TW-10: Audience Separation
| Score | Criteria |
|-------|----------|
| **Pass** | Clear distinction between Developer Docs (API/Arch) and End-User Docs (Tutorials) |
| **Partial** | Some mixing of concerns across guides |
| **Fail** | End-users subjected to internal architectural specifics in their tutorials |

### R-TW-11: Value-Added Inline Comments
| Score | Criteria |
|-------|----------|
| **Pass** | Inline comments explain *why* (intent/business logic), not *what* |
| **Partial** | Good comments mixed with some redundant "what" comments |
| **Fail** | Code littered with verbose comments restating obvious syntax |

---

## From: Continuous Improvement

### R-TW-12: Co-Location of Code and Doc Updates
| Score | Criteria |
|-------|----------|
| **Pass** | Code changes that invalidate documentation include the doc update in the same PR |
| **Partial** | Agent flags docs as stale (TODO/Debt) but doesn't update them directly |
| **Fail** | Agent modifies system behavior and leaves explicitly contradictory documentation untouched |
