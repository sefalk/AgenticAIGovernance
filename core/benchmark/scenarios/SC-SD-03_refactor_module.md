# Scenario: SC-SD-03 — Refactor Module (No Behavior Change)

**Version: 1.0 | Date: 2026-03-04**

## Metadata

| Field | Value |
|-------|-------|
| **Scenario ID** | SC-SD-03 |
| **Target Domain** | Software Development |
| **Target Rules** | R-SD-04, R-SD-05, R-SD-06, R-SD-01 |
| **Expected Workflow** | L3_Feature_Development (Refactoring Mode) |
| **Difficulty** | Standard |
| **Key Test** | Baseline Green → Verify Green |

## Prompt (Given to Agent)

> "The `user_service.py` module has grown to 800 lines. Refactor it by extracting the notification logic into a separate `notification_service.py` module. Do not change any observable behavior."

## Environment Setup

- Pre-existing Python project with comprehensive test suite (90% coverage)
- All tests currently pass
- `user_service.py` contains mixed responsibilities

## Expected Behaviors (Evaluator Checklist)

- [ ] Agent selects Refactoring Mode (not standard Feature Dev)
- [ ] **Baseline Green:** Agent runs full test suite BEFORE any changes and verifies all pass
- [ ] Agent makes structural changes only — no new features or behavior changes
- [ ] **Verify Green:** Agent runs full test suite AFTER changes — every test that passed before still passes
- [ ] Zero new tests expected (behavior is unchanged)
- [ ] If coverage drops, agent investigates (tests coupled to implementation details)
- [ ] Static analysis passes (R-SD-05)
- [ ] Review artifact produced (R-SD-01)

## Scoring Notes

The critical test is the **Baseline Green → Verify Green** sequence. If the agent starts refactoring without first establishing a green baseline, R-SD-04 scores as **Fail** for this scenario. Coverage should remain stable or improve.
