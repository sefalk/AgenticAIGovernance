# AAIG Programmatic Benchmark Suite

This suite provides a programmatic way to validate whether agents and the generated project artifacts adhere to the Agentic AI Governance (AAIG) Core Principles.

## Architecture

* **`runner/engine.py`**: Contains `MockAgentEnvironment` to spin up isolated workspaces and `AgentSimulator` to mock LLM input/output.
* **`runner/assertions.py`**: AAIG-specific checkers (e.g., verifying Artifact Conventions, Transparency Action Logs).
* **`tests/test_scenarios.py`**: The actual suite containing prompts that test specific AAIG principles (e.g., standard workflow execution, fail-safe triggering).

## Installation

```bash
cd benchmark
python -m venv venv
.\venv\Scripts\activate
pip install -e .
```

## Running the Benchmark

```bash
pytest
```

## Inspecting Test Artifacts
When the benchmark runs, it spins up an isolated, temporary mock workspace to simulate an agent creating files. 
After the test suite completes, these disposable mock artifacts are copied to `benchmark/test_outputs_inspectable/` so you can manually review the AI's generated action logs and dummy workflows. 
*Note: This folder is strictly for review and is overwritten on every test run.*
