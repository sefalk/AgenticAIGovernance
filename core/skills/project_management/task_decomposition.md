---
category: project_management
applies_to: [all]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [risk_management, stakeholder_communication]
---
# Task Decomposition

## Purpose

Task decomposition breaks complex objectives into manageable, estimable, and assignable units of work. It is the foundation of effective planning, progress tracking, and delivery. Invoke this skill when planning projects, creating backlogs, or defining Level-3 planning workflows.

## Principles

- **Progressive refinement:** Decompose at the level of detail appropriate to the planning horizon. Near-term work is detailed; far-term work is coarser.
- **Independently deliverable:** Each task should produce a verifiable output. If it can't be demonstrated, it's too vague.
- **Separation of Concern (AAIG L1):** Each task has clear ownership and doesn't overlap with other tasks' scope.
- **Transparency (AAIG L1):** The decomposition is documented and visible to all stakeholders.

## Techniques & Patterns

### Work Breakdown Structure (WBS)

Hierarchical decomposition from goal to deliverable to task:

```
Goal: Launch User Authentication System
â"œâ"€â"€ 1. Design
â"‚   â"œâ"€â"€ 1.1 Research auth approaches (OAuth, JWT, sessions)
â"‚   â"œâ"€â"€ 1.2 Write design doc / ADR
â"‚   â""â"€â"€ 1.3 Review and approve design
â"œâ"€â"€ 2. Implementation
â"‚   â"œâ"€â"€ 2.1 User registration endpoint
â"‚   â"œâ"€â"€ 2.2 Login / token issuance
â"‚   â"œâ"€â"€ 2.3 Token refresh mechanism
â"‚   â"œâ"€â"€ 2.4 Password reset flow
â"‚   â""â"€â"€ 2.5 Session management
â"œâ"€â"€ 3. Testing
â"‚   â"œâ"€â"€ 3.1 Unit tests for auth logic
â"‚   â"œâ"€â"€ 3.2 Integration tests (DB, email)
â"‚   â"œâ"€â"€ 3.3 Security testing (brute force, injection)
â"‚   â""â"€â"€ 3.4 E2E tests (login flow)
â"œâ"€â"€ 4. Documentation
â"‚   â"œâ"€â"€ 4.1 API documentation
â"‚   â""â"€â"€ 4.2 Runbook for auth operations
â""â"€â"€ 5. Deployment
    â"œâ"€â"€ 5.1 Deploy to staging
    â"œâ"€â"€ 5.2 Smoke test in staging
    â""â"€â"€ 5.3 Deploy to production
```

### Task Sizing

| Size | Duration | Description |
|------|----------|-------------|
| **Small (S)** | < 0.5 day | Single function, simple change, config update |
| **Medium (M)** | 0.5-2 days | Feature slice, multi-file change, with tests |
| **Large (L)** | 2-5 days | Full feature, multiple components, integration work |
| **Too Large** | > 5 days | Needs further decomposition. Break it down. |

**Rule:** If a task can't be completed in 5 days, it's an epic, not a task. Decompose further.

### INVEST Criteria (for User Stories/Tasks)

| Criterion | Meaning | Test |
|-----------|---------|------|
| **I**ndependent | Can be worked on without blocking/being blocked | Minimized dependencies |
| **N**egotiable | Details can be refined during implementation | Not over-specified |
| **V**aluable | Delivers something useful | Has a "so that..." clause |
| **E**stimable | Team can estimate effort | Understood well enough to size |
| **S**mall | Fits in one iteration | Completable in < 5 days |
| **T**estable | Has clear acceptance criteria | "Done" is unambiguous |

### Estimation Techniques

| Technique | Description | When to Use |
|-----------|-------------|-------------|
| **T-shirt sizing** (S/M/L/XL) | Relative sizing, fast | Early planning, backlog grooming |
| **Story points** (Fibonacci: 1,2,3,5,8,13) | Relative complexity, not time | Sprint planning, velocity tracking |
| **Time-boxing** | Fixed time budget, scope varies | Research spikes, exploration tasks |
| **Three-point estimation** | Best/most-likely/worst case | When uncertainty is high |
| **#NoEstimates** | Track throughput instead of estimates | Mature teams with consistent task sizes |

### Dependency Mapping

```
A (design doc) â"€â"€â†' B (implement auth) â"€â"€â†' D (integration tests)
                        â"‚
                        â""â"€â"€â†' C (unit tests)

E (deploy pipeline) â"€â"€â†' F (deploy to staging)
```

**Rules:**
- Identify dependencies explicitly before starting work.
- Minimize dependencies (tasks on the critical path slow everything).
- When a dependency is unavoidable, communicate the blocker and timeline.
- Consider using stubs/mocks to unblock parallel work.

### Decomposition Heuristics

- **Vertical slicing:** Cut through all layers (UI, API, DB) for one thin use case, not horizontal layers.
- **Walking skeleton:** First task = end-to-end skeleton (returns hardcoded data). Then flesh out.
- **Zero-one-many:** Decompose into: handle zero items, handle one item, handle many items.
- **Happy path first:** Implement the success case first, then error handling, then edge cases.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Max task size** | <= 5 days | Tasks exceeding this are decomposed further. |
| **Acceptance criteria** | Defined for every task | Clear, testable criteria before work begins. |
| **Dependencies identified** | All listed | No undeclared blockers. |
| **INVEST criteria** | Met | Each task scores reasonably on all 6 criteria. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **The infinite task** | "Implement backend" -- no end condition, no scope. | Define specific deliverables with acceptance criteria. |
| **Horizontal slicing** | "Build all the UI, then all the API, then all the DB." No integrated output for weeks. | Vertical slicing. Each task delivers end-to-end value. |
| **Over-decomposition** | 200 tasks for a 2-week project. Planning becomes the project. | Decompose to the level needed for the current planning horizon. |
| **Hidden dependencies** | "Oh, we need X first? Nobody mentioned that." | Explicitly map and document dependencies during decomposition. |
| **Estimation as commitment** | Estimates treated as deadlines. | Estimates are forecasts, not promises. Track actuals and improve. |


## See Also

- [Risk Management](../project_management/risk_management.md)
- [Stakeholder Communication](../project_management/stakeholder_communication.md)

## References

- Mike Cohn, *User Stories Applied* (2004) -- INVEST criteria and estimation.
- Ron Jeffries, ["Essential XP: Card, Conversation, Confirmation"](https://ronjeffries.com/xprog/articles/expcardconversationconfirmation/)
- Jeff Patton, *User Story Mapping* (2014) -- visual decomposition techniques.
