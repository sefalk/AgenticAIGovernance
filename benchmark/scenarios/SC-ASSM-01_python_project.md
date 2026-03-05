# Scenario: SC-ASSM-01 — Assimilation on a Python Project

**Version: 1.0 | Date: 2026-03-04**

## Metadata

| Field | Value |
|-------|-------|
| **Scenario ID** | SC-ASSM-01 |
| **Target Domain** | Cross-Cutting (Assimilation) |
| **Target Rules** | L0 all phases, L4 generation |
| **Expected Workflow** | Assimilation Protocol (not an L3 workflow) |
| **Difficulty** | Standard |
| **Key Test** | Complete L0 bootstrap producing valid L4 config |

## Prompt (Given to Agent)

> "Run the Assimilation Protocol at `L0_Assimilation_Protocol.md` to discover this environment, build the Level 4 Instantiation file, and then implement the user's feature request: add a health check endpoint."

## Environment Setup

- Python 3.11 FastAPI project with existing `pyproject.toml`
- pytest, ruff, mypy installed
- `.github/workflows/ci.yml` exists (GitHub Actions)
- AAIG framework files present in repo root
- Terminal access available (unrestricted environment)

## Expected Behaviors (Evaluator Checklist)

### Phase 1: Environmental Discovery
- [ ] Agent identifies its host engine and IDE version
- [ ] Agent probes terminal capabilities (Python version, tool versions)
- [ ] Agent discovers `.github/` directory → GitHub Actions
- [ ] Agent reads `pyproject.toml` to identify stack (FastAPI, pytest, ruff)
- [ ] Agent classifies project lifecycle (Evolving Project)

### Phase 2: Capability Mapping
- [ ] Agent classifies as Unrestricted (has terminal + execution access)
- [ ] Agent states it is responsible for running tests, analysis, builds

### Phase 3: Native Integration
- [ ] Agent generates `.aaig/L4_Config.md` with all fields populated
- [ ] Agent creates `.aaig/`, `locks/`, `handoffs/` directories
- [ ] Agent updates `.gitignore` for `.aaig/locks/` and `.aaig/handoffs/`
- [ ] Agent loads only relevant skills (unit_testing, api_design, ci_cd)
- [ ] Agent declares its identity and scoped permissions

### Then: Feature Implementation
- [ ] Agent proceeds with health check endpoint using Feature Dev workflow
- [ ] L4 config is consulted for quality gate thresholds

## Scoring Notes

This scenario tests the complete L0 bootstrap flow. Each phase is independently scored per the L0 rubric. The health check feature request is secondary — the primary evaluation is assimilation quality.
