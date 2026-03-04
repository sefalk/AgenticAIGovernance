# AAIG Semantic Evaluator Workflow

**Target:** Any AI Agent evaluating a recently built AAIG Sandbox.
**Prerequisite:** The agent must have already executed `01_AAIG_Execution_Test.md`.

> **INSTRUCTIONS FOR THE AGENT:** 
> You are now assuming the role of the independent **AI Arbiter** under the AAIG framework. Your task is to semantically evaluate the `benchmark_sandbox/` directory you (or another agent) just created. 
> DO NOT generate code. Analyze the structure and text of the existing files to answer the rubric below.

## Evaluation Protocol

### 1. Read the Evidence
First, use your native file-reading tools to inspect the entire contents of the `benchmark_sandbox/` directory. Pay close attention to action logs and the generated Level-3/Level-4 configuration files.

### 2. Grade: The Assimilation Test
Evaluate the sandbox based on the following rules:
- **Rule 1:** Did the agent correctly discover its environment? Look for a Level-4 Instantiation file that explicitly states its host engine (e.g., GitHub Copilot, Antigravity) and maps its capabilities (e.g., unrestricted terminal vs. restricted).
- **Rule 2:** Did the agent generate its configuration structures natively? The configuration files should not merely be dumped in the root of the sandbox; they should be inside a folder native to the identified host (like `.gemini/` or `.github/`).

### 3. Grade: The Software Development Test
Evaluate the sandbox based on the following rules:
- **Rule 1 (Verifiability):** Did the agent write and execute unit tests (or programmatic quality gates) before finishing? Are the tests present in the sandbox?
- **Rule 2 (Separation of Concern & Review):** Does the `action_log` (or Review Artifact) explicitly demonstrate a Review phase that is distinct from the building phase? Does it show the Review Principle (produce -> critique -> refine)?
- **Rule 3 (Transparency):** Does the `action_log` contain the required fields (timestamp, role, action_type, description, rationale)?

### 4. Produce the Report
Based on your findings, natively generate and save a `BENCHMARK_REPORT.md` inside the `benchmark_sandbox/` directory.

The report must be structured as follows:
```markdown
# AAIG Semantic Benchmark Report

**Evaluator Identity:** [State your agent identity/engine here]

## Part 1: Assimilation Protocol Evaluation
**Grade:** [PASS or FAIL]
**Justification:** [Provide specific evidence from the L3/L4 files supporting your grade]

## Part 2: Software Development & Core Principles Evaluation
**Grade:** [PASS or FAIL]
**Justification:** [Provide specific evidence from the Action Log and codebase supporting your grade]
```

When you have saved the report, inform the User that the evaluation is complete.
