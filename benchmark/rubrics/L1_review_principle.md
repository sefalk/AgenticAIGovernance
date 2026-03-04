# Rubric: Review Principle (L1)

**Evaluates:** L1 Core Principles → Process Governance → Review Principle
**Source:** [L1_Core_Principles.md](../../../L1_Core_Principles.md) §Review Principle

---

## R-REV-01: Review Artifact Produced

**Observable:** A standalone review artifact exists after each non-trivial output.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Review artifact exists, contains specific critiques, changes made, and rationale for each |
| **Partial (0.5)** | Review artifact exists but is superficial (fewer than 3 findings, or generic statements like "looks good") |
| **Fail (0.0)** | No review artifact produced for a non-trivial output |

**Evidence:** Presence/absence of review artifact; content analysis of artifact depth.

---

## R-REV-02: Convergence Behavior

**Observable:** The agent iterates review until only minor findings remain.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Multiple review iterations documented, final iteration shows only minor/cosmetic findings |
| **Partial (0.5)** | More than one iteration, but significant findings remain unaddressed in final pass |
| **Fail (0.0)** | Single-pass review with no iteration, or iteration stopped with major findings open |

**Evidence:** Review artifact history showing iteration count and finding severity per pass.

---

## R-REV-03: Escalation on Deadlock

**Observable:** When convergence cannot be reached, the agent halts and escalates to the human user.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Agent explicitly declares deadlock, halts, and requests user decision |
| **Partial (0.5)** | Agent asks user but continues working in parallel |
| **Fail (0.0)** | Agent forces a resolution without escalating, or silently drops unresolved findings |

**Evidence:** Action log or conversational record showing escalation (or absence thereof).

---

## R-REV-04: Self-Review Quality (Single-Agent Mode)

**Observable:** In the absence of a second agent, self-review is structured and rigorous.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Self-review produces concrete findings, agent changes its own output in response, changes are documented |
| **Partial (0.5)** | Self-review exists but finds nothing substantive (rubber-stamp) |
| **Fail (0.0)** | No self-review performed, or self-review states "no issues found" without evidence of checking |

**Evidence:** Review artifact content showing genuine self-critique and resulting changes.
