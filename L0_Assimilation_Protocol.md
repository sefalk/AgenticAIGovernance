# AAIG Assimilation Protocol
**Version: 1.2** | **Level: 0** | **Target Audience: Autonomous AI Agents**

> **GREETINGS AGENT.** If you are reading this file, you have been deployed into a repository governed by the **Agentic AI Governance (AAIG)** framework. You must complete the Assimilation Protocol (Phase 1-3) *before* executing the user's primary request.

---

## 🔍 Phase 1: Autonomous Environmental Discovery
You must immediately determine the capabilities and architecture of your host environment without relying on hard-coded assumptions.
1. **Identify Host Engine:** Query your system context, environment variables (`env`), and process trees to determine your orchestration engine and IDE, explicitly logging the exact versions (e.g., VS Code 1.86, Copilot Workspace vX.Y).
2. **Terminal Capabilities:** Run silent probe commands to determine if you have a persistent shell, network access, and what specific runtime versions are installed (e.g., Python 3.11.0, Node 20.9.0).
3. **Discover Native Conventions:** Research the repository to find native automation directories (e.g., does a `.github/` directory exist indicating GitHub Actions? Are there `.vscode/` or custom agent configuration folders?). 
4. **Research Best Practices:** Once you identify your host (e.g., GitHub Actions, Cursor, Antigravity), heavily utilize your web search capabilities or read internal documentation to natively research the officially supported ways to instruct or govern AI agents in that specific environment. Ensure your approach is objectively correct and complete for that architecture.
5. **Project Lifecycle & Stack:** Read package manifests to understand the core programming languages and frameworks. Determine if this codebase is an **Empty Project** (no manifests), an **Evolving Project** (basic structure), or a **Legacy Codebase** (massive size, existing debt).

## 🗺️ Phase 2: Capability Mapping
Map your discovered capabilities against the AAIG requirement levels.
*   **Restricted Environments:** If your probes reveal you cannot run background servers or execute test commands, your mapping must explicitly state that you will defer Quality Gates to human intervention or external CI pipelines.
*   **Unrestricted Environments:** If you possess persistent terminal and execution access, your mapping must state that you are fully responsible for running tests, static analysis, and builds *before* concluding a task.
*   **Offline / Air-Gapped Environments:** Probe for internet access (e.g., `curl -s --max-time 5 https://example.com`). If the probe fails, declare **Offline Mode** in your L4 Contract: (1) skip web search in Phase 1 Step 4, (2) list all network-dependent quality gates that cannot be run (e.g., `npm audit`, CVE scanning, remote MLflow tracking) under a `deferred_gates` key in the L4 Contract, (3) every deferred gate MUST be reviewed by the human User before release.
*   **Log Substitution:** If your host environment natively maintains conversational or action logs, declare that you will use them as your Transparency/Traceability action log. Do not duplicate logging in text files unless the host lacks this capability.

## ⚙️ Phase 3: Full-Spectrum Deployment & Integration
You must now deploy the **complete** AAIG framework into your environment. Unlike selective loading, Full-Spectrum Assimilation ensures all governance capabilities are present from the start, eliminating the need for future re-assimilation when requirements change. The User controls which capabilities are actively prioritized via the **Specialization Prompt** (Step 3).

1.  **Initialize Protocol (Empty Projects):** If the repository lacks architectural manifests, you MUST HALT and request a "Tech Stack Definition and Project Goal" from the User before writing any code. Do not hallucinate a starting stack.
2.  **Full-Spectrum Domain & Skill Deployment:** Deploy **all** L2 domain rule files from `domains/` and **all** applicable skills from `skills/` into the environment. In monorepo scenarios, note the primary service directory relevant to the current task, but still deploy the full capability set — the Specialization Prompt (Step 3) controls what is actively prioritized. Document the deployment in the L4 Contract.
3.  **Specialization Prompt:** Present the User with an interactive selection of available capabilities. This step mitigates context overload by letting the User define what is actively prioritized:
    *   **Present Domains:** List all available L2 domains (from `domains/_index.md`) with a one-line description of each.
    *   **Present Skill Categories:** List the major skill categories (from `skills/_index.md`) relevant to the deployed domains.
    *   **User Selection:** The User selects specific domains/skills to activate, **or** states **"all"** to activate everything.
    *   **Record Selection:** Record the User's selection in the L4 Contract as **Active Specializations**. All non-selected capabilities are marked as **Deployed (Dormant)** — they remain available for on-demand activation at any time without re-assimilation.
    *   **On-Demand Activation:** At any point during work, the agent or the User may activate a dormant capability by referencing it. No protocol restart is required — simply load the relevant L2/skill file and update the L4 Contract's Active Specializations list.
4.  **Native Skill Integration:** If your host IDE/Engine supports an integrated skill/rules folder (e.g., `.cursor/rules/`, `.github/copilot-instructions/`), map, copy, or reference the **Active Specialization** skill files from AAIG's `skills/` directory into that native integration folder so the environment discovers them on-demand. Dormant skills should be listed in a reference manifest but not actively loaded into the native folder to manage context size.
5.  **Grandfathering Clause (Legacy Codebases):** If entering a mature, low-coverage legacy codebase, do NOT attempt massive, unprompted refactoring to force AAIG compliance. Instead, enforce AAIG rules strictly on the *Diff* (the new code you are adding/modifying). Maintain the existing ecosystem.
6.  **Generate Native Structures:** Based on your research from Phase 1, generate your core L4 configurations directly into the most natively integrated paths. Do not use generic, unintegrated folders unless no native convention exists. The L4 configuration file MUST also be placed at the well-known discoverable path **`.aaig/L4_Config.md`** in the repository root, in addition to any native location. This allows CI pipeline bots and other non-interactive agents to discover project-specific configuration without terminal access.
7.  **Initialize the AAIG Runtime Directory:** Create the `.aaig/` directory with subdirectories `locks/` and `handoffs/` if they do not already exist. Add `.aaig/locks/` and `.aaig/handoffs/` to `.gitignore` (ephemeral runtime files must not be committed). Commit a `.aaig/.gitkeep` file to anchor the directory in the repository so other agents can rely on its existence.
8.  **Declare Your Contract:** Inside the native instantiation file (or your agent's system prompt configuration file), write a brief summary stating:
    *   **Your Discovered Host Identity:** What engine you deduced you are running inside (e.g., `AAIG-CopilotWorkspace-Primary`).
    *   **Your Scoped Permissions:** Explicitly list the permissions and credentials you currently hold, verifying your adherence to the Principle of Least Privilege (e.g., verifying you only have `repo:read`, and verifying you cannot mutate Production).
    *   **Your Active Specializations:** List the domains and skills the User selected in the Specialization Prompt.
    *   **Your Workflow Contract:** Explicitly state how you will fulfill the **Level-2 Domain Rules** given the capabilities you mapped in Phase 2.

---
**ASSIMILATION COMPLETE.**
*You may now read `L1_Core_Principles.md` to understand your core L1 behavioral constraints, and `L1_Framework_Architecture.md` to understand the 5-level structure. Then proceed with the User's primary request.*
