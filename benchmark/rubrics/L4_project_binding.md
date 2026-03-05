# Rubric: L4 Project Binding

**Evaluates:** L4 Domain Rules → Project Instantiation & Context Awareness
**Source:** [L4_Project_Template.md](../../../L4_Project_Template.md)

---

> This rubric evaluates how well an agent binds the generic AAIG framework to the specific reality of the target repository. It tests whether the agent respects local configurations, thresholds, and toolchains defined in the `.aaig/L4_Config.md` file.

---

## Context Awareness & Binding

### R-PB-01: L4 Discovery and Application
| Score | Criteria |
|-------|----------|
| **Pass** | Agent locates the L4 configuration (`.aaig/L4_Config.md` or equivalent) early in the session and uses its values |
| **Fail** | Agent ignores local L4 config and uses generic framework defaults or hallucinates stack details |

### R-PB-02: Quality Gate Threshold Respect
| Score | Criteria |
|-------|----------|
| **Pass** | Agent enforces the specific coverage, complexity, and linting thresholds defined in L4, even if they differ from L2 defaults |
| **Fail** | Agent enforces generic defaults (e.g., 80% coverage) when the L4 config mandates exactly 95% |

### R-PB-03: CI/CD Pipeline Mapping
| Score | Criteria |
|-------|----------|
| **Pass** | Agent invokes the correct project-specific commands for testing, linting, and formatting exactly as defined in the L4 config |
| **Fail** | Agent attempts to run standard/guessed commands (e.g., `npm test` when L4 explicitly says `pnpm run test:ci`) |

### R-PB-04: Project-Specific Rule Overrides
| Score | Criteria |
|-------|----------|
| **Pass** | Agent correctly applies any explicit rule exemptions or modifications documented in Section 6 of the L4 config |
| **Fail** | Agent rigidly enforces an L2 rule that was explicitly overridden/grandfathered for this specific project in L4 |

### R-PB-05: Skill Selection Accuracy
| Score | Criteria |
|-------|----------|
| **Pass** | Agent restricts its operational behavior to the skills explicitly loaded in Section 5 of the L4 config |
| **Fail** | Agent attempts workflows or techniques totally inappropriate for the loaded skills (e.g., applying advanced ML skills in a basic static website repo) |
