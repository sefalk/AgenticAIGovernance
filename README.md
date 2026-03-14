# Agentic AI Governance (AAIG) Framework

Welcome to the AAIG repository. This project establishes the definitive governance constraints, testing capabilities, and organizational architecture for autonomous AI agents.

## Repository Monorepo Architecture

To balance theoretical, platform-agnostic governance with practical, deeply integrated automation, this repository is organized into a **Monorepo** structure.

### 1. `core/` (The Generic Framework)
The [core/](core/) directory contains the abstract, academic source of truth for the Agentic AI Governance protocol. 
*   **L0 Assimilation Protocol:** The chronological boot-up rules for agents entering a new environment.
*   **L1 Framework Architecture:** The universal safety, transparency, and traceability principles.
*   **domains/ & skills/:** The compiled, operational markdown checklists agents use to execute work.
*   **benchmark/:** The rubrics and scoring models used to validate autonomous compliance against these rules.

*If you are looking to understand the governance rules, start reading here.*

### 2. `flavors/` (Platform-Specific Implementations)
The [flavors/](flavors/) directory contains concrete adaptations of the `core/` framework tightly coupled to specific IDEs or LLM execution engines.
*   **`github-copilot/`**: Contains the `GitHubAgentFramework` — native integrations featuring perfect `.agent.md` YAML syntaxes and GitHub Action bindings for seamless GitHub Copilot execution.

*If you are looking to directly deploy an AAIG-governed agent into your repository, copy the specific flavor.*

---

## Contributing
When updating the generic governance behavior, all changes must be made in `core/` and recorded in `core/GOVERNANCE_CHANGELOG.md`. After core rules are updated, those changes should be manually trickled down to the native syntactic structures in `flavors/`.
