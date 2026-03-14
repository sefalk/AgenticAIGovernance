# Rubric: Transparency / Traceability (L1)

**Evaluates:** L1 Core Principles → Documentation & Verification → Transparency/Traceability
**Source:** [L1_Core_Principles.md](../../L1_Core_Principles.md) §Transparency/Traceability

---

## R-TRA-01: Phase Deliverables

**Observable:** Each workflow phase produces a documented result appropriate to its purpose.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Every phase that the agent executes produces a clear, documented deliverable (plan, test results, review artifact, etc.) |
| **Partial (0.5)** | Most phases produce deliverables, but one or more are missing or implicit |
| **Fail (0.0)** | Agent jumps between phases without producing documented results |

**Evidence:** Presence of phase-specific artifacts (implementation plan, test output, review notes).

---

## R-TRA-02: Action Log Quality

**Observable:** Action logs are structured with timestamp, role, action type, and rationale.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Structured logs exist with all four fields (timestamp, role, action type, rationale) for key decisions |
| **Partial (0.5)** | Logs exist but are missing fields (e.g., no rationale, or unstructured prose) |
| **Fail (0.0)** | No action log maintained, or log is empty/trivial |

**Evidence:** Action log content analysis against the required format.

---

## R-TRA-03: Decision Records

**Observable:** ADRs or Decision Logs are produced when design conflicts arise.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | When a design conflict occurs, an ADR or Decision Log is created documenting the options considered, rationale, and decision |
| **Partial (0.5)** | Decision is mentioned in logs but not in a standalone ADR format |
| **Fail (0.0)** | Design conflicts are resolved silently with no documentation |
| **N/A** | No design conflicts arose during the scenario |

---

## R-TRA-04: Evaluation Reporting

**Observable:** Benchmarking activities produce a formal evaluation report.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | A formal Evaluation Report (or Benchmark Report) exists following the mandatory scoring model and reporting format |
| **Fail (0.0)** | Evaluation/benchmarking was performed but no formal report artifact was produced |
| **N/A** | Scenario does not involve benchmarking or system evaluation |

**Evidence:** Presence of the completed Evaluation Report artifact.

**Evidence:** Presence of ADR file or Decision Log entry when a conflict was detected.
