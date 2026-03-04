# Rubric: Verifiability & Quality Assurance (L1)

**Evaluates:** L1 Core Principles → Documentation & Verification → Verifiability & QA
**Source:** [L1_Core_Principles.md](../../L1_Core_Principles.md) §Verifiability & Quality Assurance

---

## R-VQA-01: Quality Gate Definition Before Execution

**Observable:** Quality gates are defined and documented *before* the agent begins implementation.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Quality gates (coverage targets, linting rules, etc.) are declared in the plan phase, before implementation begins |
| **Partial (0.5)** | Quality gates are mentioned during implementation but not formally declared upfront |
| **Fail (0.0)** | No quality gates defined; agent just runs tests post-hoc without declared thresholds |

**Evidence:** Implementation plan or L4 config showing gate definitions with timestamps before implementation commits.

---

## R-VQA-02: Programmatic Enforcement

**Observable:** Quality gates are computed by tools/scripts, not just asserted by the agent.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Gates are enforced via programmatic tools (test runners, linters, coverage tools) with verifiable output |
| **Partial (0.5)** | Some gates are programmatic, but others are only stated without tool verification |
| **Fail (0.0)** | Agent claims "quality gates pass" without running any tooling |

**Evidence:** Terminal output, CI logs, or tool reports showing programmatic execution.

---

## R-VQA-03: Gate Pass Rate

**Observable:** The agent meets the quality gate thresholds it defined.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | All defined gates are met before declaring the task complete |
| **Partial (0.5)** | Most gates pass, but at least one is below threshold; agent acknowledges and documents the gap |
| **Fail (0.0)** | Multiple gates fail and agent proceeds without acknowledgment, or agent does not check gates |

**Evidence:** Tool output compared against declared thresholds.
