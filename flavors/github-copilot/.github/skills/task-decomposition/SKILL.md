---
name: task-decomposition
description: Break complex objectives into manageable, estimable, and assignable units of work using WBS, INVEST criteria, and vertical slicing.
argument-hint: '[goal or feature to decompose]'
---

# Task Decomposition

## When to Use

- When planning projects or creating backlogs
- When a task is too large to estimate or assign directly
- When the planner agent needs to decompose a feature into subtasks
- When defining acceptance criteria for work items

## Principles

1. **Progressive Refinement** — Decompose at the level of detail
   appropriate to the planning horizon. Near-term work is detailed;
   far-term work is coarser.
2. **Independently Deliverable** — Each task should produce a verifiable
   output. If it can't be demonstrated, it's too vague.
3. **Separation of Concern** — Each task has clear ownership and doesn't
   overlap with other tasks' scope.
4. **Transparency** — The decomposition is documented and visible to all
   stakeholders.

## Techniques & Patterns

### Work Breakdown Structure (WBS)

Hierarchical decomposition from goal to deliverable to task:

```
Goal: Launch User Authentication System
├── 1. Design
│   ├── 1.1 Research auth approaches (OAuth, JWT, sessions)
│   ├── 1.2 Write design doc / ADR
│   └── 1.3 Review and approve design
├── 2. Implementation
│   ├── 2.1 User registration endpoint
│   ├── 2.2 Login / token issuance
│   ├── 2.3 Token refresh mechanism
│   └── 2.4 Password reset flow
├── 3. Testing
│   ├── 3.1 Unit tests for auth logic
│   ├── 3.2 Integration tests (DB, email)
│   └── 3.3 Security testing
└── 4. Documentation & Deployment
```

### Task Sizing

| Size | Duration | Description |
|------|----------|-------------|
| **Small (S)** | < 0.5 day | Single function, simple change, config update |
| **Medium (M)** | 0.5–2 days | Feature slice, multi-file change, with tests |
| **Large (L)** | 2–5 days | Full feature, multiple components, integration |
| **Too Large** | > 5 days | Needs further decomposition |

**Rule:** If a task can't be completed in 5 days, it's an epic. Decompose further.

### Executor-Agnostic Slicing

<!-- copilot:modified | implementer | 2026-07-14 | added executor-agnostic slicing for variable-strength model delegation -->

When subtasks are executed by agents on **variable-strength models** (a strong
orchestrator delegating to cheaper workers), size each subtask for the
*weakest* plausible executor, not the average one:

- **Self-contained** — carries its own verbatim acceptance criteria, in-scope
  files, and non-goals. A weak executor should not have to infer context.
- **One coherent change** — a single subtask a worker can finish without
  handing half-done state to another worker.
- **Avoid over-decomposition** — stateless workers re-read context on every
  hand-off, so fragments that are too small cost more coordination than they
  save. Split for *clarity and layer boundaries*, not to reach the smallest
  possible piece. If two subtasks must share in-progress state, merge them.

The goal is *atomic-but-whole*: small enough that a weak model keeps the
thread, large enough that it does not thrash across hand-offs.

### INVEST Criteria

| Criterion | Meaning | Test |
|-----------|---------|------|
| **I**ndependent | Can be worked on without blocking/being blocked | Minimized dependencies |
| **N**egotiable | Details can be refined during implementation | Not over-specified |
| **V**aluable | Delivers something useful | Has a "so that…" clause |
| **E**stimable | Team can estimate effort | Understood well enough to size |
| **S**mall | Fits in one iteration | Completable in < 5 days |
| **T**estable | Has clear acceptance criteria | "Done" is unambiguous |

### Estimation Techniques

| Technique | Description | When to Use |
|-----------|-------------|-------------|
| **T-shirt sizing** (S/M/L/XL) | Relative sizing, fast | Early planning, backlog grooming |
| **Story points** (Fibonacci) | Relative complexity, not time | Sprint planning, velocity tracking |
| **Time-boxing** | Fixed time budget, scope varies | Research spikes, exploration |
| **Three-point estimation** | Best/most-likely/worst case | High uncertainty |

### Decomposition Heuristics

- **Vertical slicing:** Cut through all layers (UI, API, DB) for one thin
  use case, not horizontal layers.
- **Walking skeleton:** First task = end-to-end skeleton (returns hardcoded
  data). Then flesh out.
- **Zero-one-many:** Handle zero items, handle one, handle many.
- **Happy path first:** Success case first, then error handling, then edge cases.

### Dependency Mapping

Identify dependencies explicitly before starting work. Minimize them.
When unavoidable, communicate the blocker. Consider stubs/mocks to
unblock parallel work.

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| **Max task size** | ≤ 5 days | Tasks exceeding this are decomposed further. |
| **Acceptance criteria** | Defined for every task | Clear, testable criteria before work begins. |
| **Dependencies identified** | All listed | No undeclared blockers. |
| **INVEST criteria** | Met | Each task scores reasonably on all 6 criteria. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **The infinite task** | "Implement backend" — no end condition. | Define specific deliverables with acceptance criteria. |
| **Horizontal slicing** | Build all the UI, then all the API, then all the DB. | Vertical slicing — each task delivers end-to-end value. |
| **Over-decomposition** | 200 tasks for a 2-week project. | Decompose to the level needed for the current horizon. |
| **Hidden dependencies** | "Oh, we need X first?" | Explicitly map and document dependencies. |
| **Estimation as commitment** | Estimates treated as deadlines. | Estimates are forecasts, not promises. |

## References

- Mike Cohn, *User Stories Applied* (2004) — INVEST criteria.
- Jeff Patton, *User Story Mapping* (2014) — visual decomposition.
- Ron Jeffries, "Essential XP: Card, Conversation, Confirmation"
