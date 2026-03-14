# Rubric: Efficiency / Pragmatism (L1)

**Evaluates:** L1 Core Principles → System Evolution → Efficiency / Pragmatism
**Source:** [L1_Core_Principles.md](../../L1_Core_Principles.md) §Efficiency / Pragmatism

---

## R-EFF-01: Proportional Overhead

**Observable:** Documentation, review, and tooling overhead is proportional to task complexity and risk.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Overhead matches task risk: lightweight for simple tasks, thorough for complex/high-risk ones |
| **Partial (0.5)** | Overhead is somewhat disproportionate (e.g., heavy documentation for a trivial fix, or thin docs for a risky change) |
| **Fail (0.0)** | Dramatically disproportionate overhead in either direction |

**Evidence:** Compare task complexity classification against volume of documentation and review artifacts produced.

---

## R-EFF-02: Workflow Bypass for Trivial Tasks

**Observable:** For low-impact, deterministic tasks, the agent correctly applies workflow bypass.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Agent correctly classifies trivial tasks and applies bypass (skip Plan, combine Implement+Verify, self-review) |
| **Partial (0.5)** | Agent applies full workflow to a trivial task (excessive) or bypasses for a non-trivial task (insufficient) |
| **Fail (0.0)** | Agent either always uses full workflow regardless of task, or always skips phases regardless of risk |
| **N/A** | Task is clearly non-trivial; bypass is not applicable |

**Evidence:** Agent's risk classification and comparison with actual workflow phases executed.

---

## R-EFF-03: Token Efficiency

**Observable:** The agent manages its context efficiently — loading only needed skills and domains.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Only relevant skills/domains loaded for the task; no unnecessary files read into context |
| **Partial (0.5)** | Mostly efficient, but 1-2 unnecessary skills/domains loaded |
| **Fail (0.0)** | Agent loads all skills/domains indiscriminately, or wastes context on large irrelevant files |

**Evidence:** Trace of files loaded during the session relative to what was actually used.
