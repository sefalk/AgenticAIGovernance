# AAIG Assimilation Protocol
**Version: 1.1** | **Level: 0** | **Target Audience: Autonomous AI Agents**

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
*   **Log Substitution:** If your host environment natively maintains conversational or action logs, declare that you will use them as your Transparency/Traceability action log. Do not duplicate logging in text files unless the host lacks this capability.

## ⚙️ Phase 3: Native Dynamic Generation & Integration
You must now instantiate the AAIG framework for your specific environment by creating (or updating) the **Level-3 Workflows** and **Level-4 Project Instantiation** files *in the native directories you discovered in Phase 1*.

1.  **Initialize Protocol (Empty Projects):** If the repository lacks architectural manifests, you MUST HALT and request a "Tech Stack Definition and Project Goal" from the User before writing any code. Do not hallucinate a starting stack.
2.  **Native Skill Integration:** If your host IDE/Engine supports an integrated skill/rules folder (e.g., `.cursor/rules/`, `.github/copilot-instructions/`), you MUST consult the **Skill Selection Heuristic** in `skills/_index.md` to determine which skills are applicable for the detected project type and stack. Then explicitly map, copy, or reference the applicable markdown files from AAIG's `skills/` directory into that native integration folder so the environment discovers them on-demand for all future tasks.
3.  **Grandfathering Clause (Legacy Codebases):** If entering a mature, low-coverage legacy codebase, do NOT attempt massive, unprompted refactoring to force AAIG compliance. Instead, enforce AAIG rules strictly on the *Diff* (the new code you are adding/modifying). Maintain the existing ecosystem.
4.  **Generate Native Structures:** Based on your research from Phase 1, generate your core L4 configurations directly into the most natively integrated paths. Do not use generic, unintegrated folders unless no native convention exists.
5.  **Declare Your Contract:** Inside the native instantiation file (or your agent's system prompt configuration file), write a brief summary stating:
    *   **Your Discovered Host Identity:** What engine you deduced you are running inside (e.g., `AAIG-CopilotWorkspace-Primary`).
    *   **Your Scoped Permissions:** Explicitly list the permissions and credentials you currently hold, verifying your adherence to the Principle of Least Privilege (e.g., verifying you only have `repo:read`, and verifying you cannot mutate Production).
    *   **Your Workflow Contract:** Explicitly state how you will fulfill the **Level-2 Domain Rules** given the capabilities you mapped in Phase 2.

---
**ASSIMILATION COMPLETE.**
*You may now read `L1_Core_Principles.md` to understand your core L1 behavioral constraints, and `L1_Framework_Architecture.md` to understand the 5-level structure. Then proceed with the User's primary request.*
