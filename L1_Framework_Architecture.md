# AAIG Framework Architecture
**Version: 1.0 | Date: 2026-03-03**

*This document defines the structural architecture, hierarchical levels, and roles of the Agentic AI Governance (AAIG) framework. It answers **how** the framework is organized.*

## 1. Purpose
This framework organizes agent governance into five hierarchical levels, progressing from initial environmental bootstrapping (Level 0) and universal principles (Level 1) down to project-specific configurations (Level 4). Each level is structurally distinct and derives from the level above. 

## 2. The Five Levels (L0-L4)

**Level 0 (Bootstrapping & Assimilation):** Defined in `L0_Assimilation_Protocol.md`. The chronological entry point. The phase where an agent discovers its environment, determines its capabilities, and dynamically generates L3/L4 files natively into the host system before executing primary tasks.

**Level 1 (Core Principles):** Defined in `L1_Core_Principles.md`. The abstract, universal principles (Fail-Safe, Traceability, Separation of Concern). They apply to all domains and projects.

**Level 2 (Domain Rules & Guidelines):** Declarative rules and constraints (SHALL/SHALL NOT statements) derived from Level 1 specializing in a domain (e.g., Software Development).

**Level 3 (Specialized Workflows):** Procedural workflows (ordered steps with entry/exit criteria and quality gates) derived from Level 2. (e.g., Test-Driven Development cycle). Generic baseline workflows are provided in the `/workflows/` directory and adapted during L4 Project Instantiation.

**Level 4 (Project Instantiation):** Takes generic Level-3 workflows and binds them to project-specific constraints (tech stack, quality gate thresholds). 

*Note regarding L3/L4 split:* While conceptually distinct, Level-3 workflows and Level-4 project bindings may be physically combined into a single execution file (e.g., an agent prompt like `.cursorrules` or `.github/copilot-instructions.md`) to maximize token efficiency and pragmatism in real-world agent environments.

**Proper Derivation:** An artifact is "properly derived" when it explicitly references its parent-level artifact, has passed the review process, carries a version identifier, and does not contradict ancestor-level Statements.

## 3. Key Roles

*   **Primary Agent:** The agent executing the task, responsible for producing the deliverable and proposing quality gates.
*   **Reviewer:** Evaluates the Primary Agent's output against applicable rules and quality gates. In multi-agent setups, the Reviewer must not be the same agent as the Primary.
*   **Quality-Owner:** The agent or human responsible for approving quality gate definitions. Defaults to the human User.

## 4. Bootstrapping & Role Combination
When fewer agents are available than roles require, roles may be combined with the following constraints:
*   The human User implicitly assumes the Reviewer and Quality-Owner roles for tasks requiring peer review if no second agent is available.
*   For low-impact tasks (e.g., linting fixes), a single agent may fulfill the review requirement via structured self-review.
*   Conflicts between agents, or between an agent and its own verification logic, escalate directly to the human User.
As the agent team grows, roles must be separated according to the Separation of Concern principle.

## 5. Concurrency

When multiple workflows execute in parallel, each workflow operates as an independent instance. Each agent must check for open parallel workflows modifying the same artifacts before beginning work. Conflict detection is the responsibility of the agent initiating the modification.

## 6. Artifact Conventions

All level-specific artifacts (Levels 1-4) must include: a descriptive filename, the artifact's level, a version identifier, and a creation date. 

Operational artifacts (action logs, ADRs) are not level-classified but must still comply with filename and timestamp conventions.
*   **Action Log Format:** Unless substituted by a host-native log, action logs must be structured markdown containing: timestamp, agent role, action type (decision/tool invocation), description, and rationale.

## 7. Skills Toolbox & Workflow Selection

The framework includes an optional **Skills Toolbox** (`/skills/`)—a library of detailed skill templates. Skills are expert-knowledge resources invoked during Level-2, Level-3, or Level-4 derivation.

When multiple Level-3 workflows are available, the agent must classify the task and select the appropriate workflow based on entry criteria. If none match, the agent falls back to a generic default sequence: Plan -> Review Plan -> Execute -> Verify -> Review Output.

**Multi-Workflow Orchestration:** When a single task spans multiple domains (e.g., ML + Infrastructure + Software Dev), decompose it into sub-tasks, one per workflow. Apply the **dependency rule**: if Workflow B requires an artifact from Workflow A (e.g., GPU cluster must exist before model training), run A first, then B. If sub-tasks are independent, run them in parallel branches using the Branch-Per-Agent-Isolation pattern (`multi_agent_coordination.md`). Document the sub-task dependency graph in the `WIP.md` or implementation plan before starting.

**Workflow Bypasses:** For low-impact, deterministic tasks (like running a code formatter or updating a typo), passing programmatic Quality Gates is sufficient—full review cycles and extensive artifact generation may be bypassed under the Efficiency principle. For high-impact tasks, the human User must be in the review loop from the first iteration.

## 8. Governance Change Protocol

Changes to **Level 0 or Level 1** documents (this file, `L0_Assimilation_Protocol.md`, `L1_Core_Principles.md`, `L1_Framework_Architecture.md`) are uniquely high-risk because they can propagate inconsistencies to all downstream L2/L3/L4 artifacts.

These changes require:
1. **Mandatory human User review** — self-review by the proposing agent is explicitly prohibited for L0/L1 changes.
2. **Cross-level impact assessment** — the agent MUST document which L2 rules and L3 workflows are affected by the change before merging.
3. **Version bump** — increment the `Version` field in the modified file.
4. **Changelog entry** — document what changed and why in a `GOVERNANCE_CHANGELOG.md` at the repository root.

Changes to **Level 2 and below** follow the standard Review Principle (L1).
