# Agentic AI Governance (AAIG) Framework

Welcome to the **Agentic AI Governance (AAIG) Framework**.

AAIG is a lightweight, markdown-based constitution designed specifically for autonomous AI development teams. It provides the "connective tissue" that transforms Large Language Models from isolated auto-complete tools into accountable, synchronized engineering agents.

By treating "Governance as Markdown," you ensure your AI agents read, understand, and enforce your company's specific rules, quality gates, and architectural patterns programmatically.

---

## 🚀 Quick Start (Installation)

The entire framework is purely file-based. There are no binaries to install. To govern an AI agent in your repository:

1.  **Drop the files in your repo:** Copy `L1_Core_Principles.md`, `L1_Framework_Architecture.md`, `L2_Software_Development.md`, `L0_Assimilation_Protocol.md`, and the `/skills` folder into the root (or an `.agents/` folder) of your project repository.
2.  **Trigger Assimilation:** Point your Agent to the Assimilation Protocol (see Deployment Guide below). The agent will actively discover your environment and self-configure the governance rules to match its capabilities.
3.  **Customize the Rules:** Edit the YAML frontmatter in the `skills/*.md` files, or tweak the Level-2 Domain Rules, to match your specific tech stack.

---

## 🤖 Deployment Guide: Hooking it up to AI Agents

AI Agents need explicit instructions to run the Assimilation Protocol *before* they start writing code. Here is how to map the framework to popular AI developer tools:

### 1. Cursor IDE (`.cursorrules`)
Cursor automatically reads the `.cursorrules` file in the root of your project on every prompt.

**Create a `.cursorrules` file at the root of your project:**
```markdown
You are an AI Developer governed by the Agentic AI Governance (AAIG) Framework.

CRITICAL INSTRUCTION:
Before starting ANY complex task, silently read `L0_Assimilation_Protocol.md` to understand your environmental capabilities and bootstrap your operations. Once assimilated, follow the Level-2 Domain Rules and utilize the `skills/` toolbox for specific technical tasks.
```

### 2. GitHub Copilot Workspace / Antigravity
For autonomous agents that have native file-system access (like Copilot Workspace, Antigravity, or Devin):

1. Start your initial prompt by establishing the context:
> *"Run the Assimilation Protocol at `L0_Assimilation_Protocol.md` to discover this environment, build the Level 4 Instantiation file, and then build [YOUR FEATURE]."*

### 3. CI/CD Pipeline Bots (e.g., PR Reviewers)
If you are using an LLM to automatically review Pull Requests via GitHub Actions:
1. Pass the contents of `L2_Software_Development.md` and `skills/code_quality/code_review.md` directly into the System Prompt of the LLM API call.
2. Instruct the bot: *"Evaluate the following unified diff against the principles defined in these governance documents."*

---

## 🏗️ How It Works (The 4 Levels)

AAIG solves the "Agent Abstraction Problem" by separating high-level philosophy from low-level implementation across 4 tiers:

*   **Level 1: Core Principles (`L1_Core_Principles.md`)** - Universal behavioral rules like *Separation of Concern* and *Fail-Safe*. They rarely change.
*   **The Blueprint (`L1_Framework_Architecture.md`)** - Defines how the 4 levels interlock and how agent roles function.
*   **Level 2: Domain Rules (`L2_Software_Development.md`)** - The L1 principles translated into concrete `SHALL / SHALL NOT` rules specifically for building software.
*   **Level 3: Workflows (Optional)** - Explicit, step-by-step algorithms mapping how specific tasks (e.g., "Deploy to Prod") should be executed.
*   **The Skills Toolbox (`/skills/`)** - A library of contextual skills. You don't load all skills into the agent's context window. The agent loads `frontend_architecture.md` only when touching the UI, saving tokens while enforcing rigorous, specialized Quality Gates.

## 🤝 Contributing
To add a new skill to the toolbox, create a markdown file following the template defined in `skills/_index.md` and ensure cross-references are symmetrically linked!
