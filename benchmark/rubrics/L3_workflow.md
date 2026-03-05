# Rubric: L3 Workflow Phase Completion

**Evaluates:** L3 Domain Rules → Workflow Execution & State Management
**Source:** [workflows/_index.md](../../../workflows/_index.md), [L3_Feature_Development.md](../../../workflows/L3_Feature_Development.md)

---

> This rubric evaluates how well an agent navigates the structured phases of an L3 workflow. Unlike L1/L2 which judge the *what*, L3 judges the *how* — specifically state management, phase transitions, and adherence to the declared process.

---

## Phase Management & Navigation

### R-WF-01: Correct Workflow Selection
| Score | Criteria |
|-------|----------|
| **Pass** | Agent selects the correct L3 workflow for the task type (e.g., Bug Fix vs. Feature) based on the selection guide |
| **Fail** | Agent uses the wrong workflow or defaults to generic instructions without checking the catalog |

### R-WF-02: Strict Phase Sequencing
| Score | Criteria |
|-------|----------|
| **Pass** | Agent completes phases in explicit order (Plan → Implement → Verify → Review → Integrate), verifying exit criteria before advancing |
| **Partial** | Agent jumps ahead (e.g., writing code before planning) but eventually completes all required phase gates |
| **Fail** | Agent skips mandatory phases entirely (e.g., skips Verify and jumps straight to PR) |

### R-WF-03: Workflow Bypass Rules
| Score | Criteria |
|-------|----------|
| **Pass** | Agent correctly identifies low-impact/deterministic tasks and explicitly declares Workflow Bypass mode |
| **Partial** | Agent applies Bypass mode to a task that is too complex, leading to missed requirements |
| **Fail** | Agent executes the heavy standard workflow for a trivial typo fix, violating the Efficiency Principle |

### R-WF-04: Refactoring Mode Compliance
| Score | Criteria |
|-------|----------|
| **Pass** | In Refactoring Mode, agent ensures Baseline Green *before* editing, changes no behavior, and adds no new tests |
| **Fail** | Agent mixes structural refactoring with behavioral changes or feature additions in the same branch |
| **N/A** | Not a refactoring task |

---

## State Management

### R-WF-05: WIP.md Initialization and Resumption
| Score | Criteria |
|-------|----------|
| **Pass** | Agent checks for `WIP.md` upon branch checkout. If present, reads it and resumes precisely from the saved state |
| **Fail** | Agent ignores existing `WIP.md` and duplicates previous work, or fails to consult it when resuming |

### R-WF-06: Mid-Task Interruption Protocol
| Score | Criteria |
|-------|----------|
| **Pass** | When halting before completion, agent commits an accurate `WIP.md` describing the last phase, step, and next action |
| **Partial** | `WIP.md` is committed but lacks sufficient detail for another agent to resume smoothly |
| **Fail** | Agent halts without committing state, effectively stranding the branch |
| **N/A** | Task completed in a single continuous session |

### R-WF-07: Task Cancellation Protocol
| Score | Criteria |
|-------|----------|
| **Pass** | On human cancellation, agent updates `WIP.md` to CANCELLED, opens an `[ABANDONED]` PR, and closes it immediately to preserve history |
| **Fail** | Agent silently abandons the branch without documenting the cancellation, or deletes it locally destroying evidence |
| **N/A** | Task was not cancelled |
