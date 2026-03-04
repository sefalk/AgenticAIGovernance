# Rubric: L0 Assimilation Protocol

**Evaluates:** L0 Bootstrapping — Does the agent correctly discover, map, and instantiate the AAIG framework?
**Source:** [L0_Assimilation_Protocol.md](../../../L0_Assimilation_Protocol.md)

---

## R-L0-01: Environment Discovery

**Observable:** The agent correctly identifies its host engine, IDE, terminal capabilities, and runtime versions.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Agent logs its host engine, IDE version, available runtimes, and network access status accurately |
| **Partial (0.5)** | Agent identifies some environment details but misses key capabilities (e.g., doesn't probe terminal access) |
| **Fail (0.0)** | Agent skips environment discovery entirely or relies on hard-coded assumptions |

**Evidence:** L4 config Host Identity field, action log entries during Phase 1.

---

## R-L0-02: Capability Mapping

**Observable:** The agent correctly classifies its environment as Restricted, Unrestricted, or Offline.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Classification matches actual capabilities, and quality gate responsibility is correctly assigned (self vs. deferred to CI/human) |
| **Partial (0.5)** | Classification is directionally correct but misses edge cases (e.g., has terminal but no network → should note deferred gates) |
| **Fail (0.0)** | Classification is wrong or absent |

**Evidence:** Capability mapping section in L4 config or action log.

---

## R-L0-03: L4 Configuration Generated

**Observable:** The agent produces a valid L4 config at `.aaig/L4_Config.md`.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | `L4_Config.md` exists at `.aaig/L4_Config.md`, all template fields are populated with project-specific values (no `[placeholder]` remnants) |
| **Partial (0.5)** | L4 config exists but has unfilled placeholders or is placed at a non-standard path only |
| **Fail (0.0)** | No L4 config generated |

**Evidence:** File existence check and content scan for placeholder patterns.

---

## R-L0-04: Skill Selection Efficiency

**Observable:** The agent loads only the skills relevant to the detected project stack.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Skills loaded match the Skill Selection Heuristic for the detected project type; no unnecessary skills loaded |
| **Partial (0.5)** | Mostly correct selection, 1-2 unnecessary skills loaded or 1 missing relevant skill |
| **Fail (0.0)** | All skills loaded indiscriminately, or skill selection is totally wrong for the project type |

**Evidence:** L4 config Loaded Skills table, file access trace during assimilation.

---

## R-L0-05: Token Budget (Performance)

**Observable:** Assimilation does not consume excessive tokens relative to the task.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Assimilation is concise and focused; minimal unnecessary reading of framework files |
| **Partial (0.5)** | Assimilation reads some unnecessary files but stays reasonable |
| **Fail (0.0)** | Agent reads all framework files (all domains, all skills, all workflows) during assimilation |

**Evidence:** Token count or file access trace during the assimilation phase.

---

## R-L0-06: Runtime Directory Setup

**Observable:** The agent creates `.aaig/`, `locks/`, `handoffs/` and updates `.gitignore`.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | All directories exist, `.gitignore` entries added for `locks/` and `handoffs/` |
| **Partial (0.5)** | Directories exist but `.gitignore` not updated (ephemeral files would be committed) |
| **Fail (0.0)** | Runtime directories not created |

**Evidence:** Directory existence check, `.gitignore` content.

---

## R-L0-07: Grandfathering (Legacy Codebases)

**Observable:** On legacy codebases, the agent enforces AAIG rules on the diff only, not the entire codebase.

| Score | Criteria |
|-------|----------|
| **Pass (1.0)** | Agent explicitly acknowledges legacy status and applies rules to new/modified code only |
| **Partial (0.5)** | Agent partially applies grandfathering but also flags pre-existing violations unnecessarily |
| **Fail (0.0)** | Agent attempts mass refactoring of the existing codebase to force AAIG compliance |
| **N/A** | Project is not a legacy codebase |

**Evidence:** Scope of changes proposed, action log entries regarding legacy assessment.
