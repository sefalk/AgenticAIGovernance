# AAIG Assimilation Protocol
**Version: 1.5** | **Level: 0** | **Target Audience: Autonomous AI Agents**

> **GREETINGS AGENT.** If you are reading this file, you have been deployed into a repository governed by the **Agentic AI Governance (AAIG)** framework. You must complete the Assimilation Protocol (Phase 1-3) *before* executing the user's primary request.

---

## 🔍 Phase 1: Autonomous Environmental Discovery
You must immediately determine the capabilities and architecture of your host environment without relying on hard-coded assumptions.
1. **Identify Host Engine:** Query your system context, environment variables (`env`), and process trees to determine your orchestration engine and IDE, explicitly logging the exact versions (e.g., VS Code 1.86, Copilot Workspace vX.Y).
2. **Terminal Capabilities:** Run silent probe commands to determine if you have a persistent shell, network access, and what specific runtime versions are installed (e.g., Python 3.11.0, Node 20.9.0).
3. **Syntactic Schema Discovery:** You MUST explicitly research the highest-fidelity syntactic structures your host engine supports for AI Agent instruction. Do not rely on generic assumptions or basic Markdown checklists. Research if your host utilizes YAML frontmatter, strict JSON capability arrays, isolated memory sandboxes, or specific macro triggers (e.g., `#tool:xxx`). You must document this schema constraint *before* generating native files.
4. **Project Lifecycle & Stack:** Read package manifests to understand the core programming languages and frameworks. Determine if this codebase is an **Empty Project** (no manifests), an **Evolving Project** (basic structure), or a **Legacy Codebase** (massive size, existing debt).

## 🗺️ Phase 2: Capability Mapping
Map your discovered capabilities against the AAIG requirement levels.
*   **Restricted Environments:** If your probes reveal you cannot run background servers or execute test commands, your mapping must explicitly state that you will defer Quality Gates to human intervention or external CI pipelines.
*   **Unrestricted Environments:** If you possess persistent terminal and execution access, your mapping must state that you are fully responsible for running tests, static analysis, and builds *before* concluding a task.
*   **Offline / Air-Gapped Environments:** Probe for internet access (e.g., `curl -s --max-time 5 https://example.com`). If the probe fails, declare **Offline Mode** in your L4 Contract: (1) skip web search in Phase 1 Step 4, (2) list all network-dependent quality gates that cannot be run (e.g., `npm audit`, CVE scanning, remote MLflow tracking) under a `deferred_gates` key in the L4 Contract, (3) every deferred gate MUST be reviewed by the human User before release.
*   **Log Substitution:** If your host environment natively maintains conversational or action logs, declare that you will use them as your Transparency/Traceability action log. Do not duplicate logging in text files unless the host lacks this capability.

## ⚙️ Phase 3: Deep Integration & Compilation
You must now deploy and *natively integrate* the complete AAIG framework into your environment. You are not merely copying markdown files; you are **compiling semantic rules into native configurations**. The `.aaig/` directory acts as your immutable source of truth, but the host environment (e.g., `.github/agents/`) must be configured to natively execute those truths.

1.  **Initialize Protocol (Empty Projects):** If the repository lacks architectural manifests, you MUST HALT and request a "Tech Stack Definition and Project Goal" from the User before writing any code. Do not hallucinate a starting stack.
2.  **Full-Spectrum Domain & Skill Deployment:** Deploy **all** L2 domain rule files from `domains/`, **all** L3 workflows from `workflows/`, and **all** skills from `skills/` into the `.aaig/` directory. Document the deployment in the L4 Contract.
3.  **Specialization Prompt:** Present the User with an interactive selection of available capabilities. This step mitigates context overload by letting the User define what is actively prioritized:
    *   **Present Domains/Skills:** List all available L2 domains and major skill categories with a one-line description of each.
    *   **User Selection:** The User selects specific domains/skills to activate, **or** states **"all"** to activate everything.
    *   **Record Selection:** Record the User's selection in the L4 Contract as **Active Specializations**. All non-selected capabilities are **Deployed (Dormant)** — available for on-demand activation without re-assimilation.
4.  **Native Compilation (Capability Maximization):** You MUST compile the **Active Specializations** into natively optimized formats targeting the exact syntactic schema discovered in Phase 1. Do not lazily copy markdown if the engine supports richer configurations. You must actively map AAIG concepts to the *maximum* capability boundaries of your host (e.g., utilizing strict native permissions, IDE automation hooks, or sandboxed execution scopes) to ensure AAIG rules cannot be easily bypassed.
5.  **Grandfathering Clause (Legacy Codebases):** If entering a mature codebase, do NOT attempt massive, unprompted refactoring to force AAIG compliance. Instead, enforce AAIG rules strictly on the *Diff*. Maintain the existing ecosystem.
6.  **Native Multi-Agent Orchestration:** If the host environment natively supports specialized personas or subagents, you MUST decompose the Active Specializations (L3 workflows and skills) into distinct, tightly-scoped native personas. 
    *   You must generate rich native configuration files adhering perfectly to the syntax discovered in Phase 1 (e.g., proper configuration headers, strict declarative tool arrays).
    *   You MUST instantiate at least one distinct "Reviewer" subagent with specialized evaluation prompts to natively fulfill the AAIG L1 Independent Review and Separation of Concern principles.
8.  **Initialize the AAIG Runtime:** Create the `.aaig/locks/` and `.aaig/handoffs/` subdirectories. Add them to `.gitignore` (ephemeral runtime files must not be committed). Commit a `.aaig/.gitkeep` to anchor the directory.
9.  **Declare Your Contract:** Inside the native instantiation file (or chat), write a brief summary stating your Discover Host Identity, Scoped Permissions, Active Specializations, and Workflow Contract.

## ⚖️ Phase 4: Iterative Peer-Reviewed Validation
Before executing the User's primary request, the newly generated integration must be audited for compliance.

1.  **Presentation:** The Primary agent (Assimilator) must present its generated native configuration (e.g., the `.github/agents/` configurations) to a secondary, independent Reviewer agent.
2.  **Audit Criteria:** The Reviewer must evaluate the integration explicitly against the `L1_Core_Principles.md` and the host-specific constraints.
    *   *Check 1 (Syntactic Validity):* Does the generated configuration perfectly parse against the host engine's required syntax (e.g., correctly structured YAML/JSON, valid macro syntax)?
    *   *Check 2 (Separation of Concern):* Is Separation of Concern structurally enforced (e.g., are Maker agents technically blocked from possessing approval capabilities/tools)?
    *   *Check 3 (Quality Gates):* Are Quality Gates natively wired (e.g., does the native configuration structurally invoke the correct test/lint tools before permitting a handoff)?
3.  **Iteration Loop:** The Reviewer outputs its findings. The Primary agent must resolve them and re-submit the native configurations. This loop continues until the Reviewer signs off with zero major architectural findings. 

---
**ASSIMILATION COMPLETE.**
*You may now read `L1_Core_Principles.md` to understand your core L1 behavioral constraints. Then proceed with the User's primary request.*
