---
title: LLM Observability & Decision Tracing
description: Instrumenting autonomous workflows to capture prompts, model responses, tokens, and the latent reasoning behind agent actions.
applies_to: [all]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-03-04
related: [monitoring_observability, structured_logging]
---
# LLM Observability & Decision Tracing

## Purpose
When a traditional system fails, developers view the stack trace. When an Autonomous AI Agent fails, a stack trace is insufficient; developers must understand the *context* the agent had and the *reasoning* it employed. This skill mandates that agents instrument their workflows to capture LLM traces, making the "black box" of AI decision-making auditable.

## Principles
1. **Traceable Agency:** Every action taken by an AI agent must be deterministically linked to the prompt that initiated it and the LLM response that authorized it. *(AAIG L1: Transparency/Traceability)*
2. **Cost Attribution:** Token usage must be logged to prevent runaway agent loops from silently burning compute budgets. *(AAIG L1: Efficiency / Pragmatism)*

## Techniques & Patterns

### 1. The Tracing Payload
Every call to an LLM provider (OpenAI, Anthropic, etc.) must be wrapped to intercept and log:
*   **Trace ID:** A unique correlation ID linking the LLM call to the broader business transaction.
*   **System Prompt & Context:** The exact configuration rules loaded at the time.
*   **User/Agent Prompt:** What the agent was explicitly asked to do.
*   **Raw Response:** The exact completion text/JSON provided by the model.
*   **Metadata:** Model version (e.g., `claude-3-7-sonnet`), latency (ms), and token counts (prompt, completion, cached).

### 2. Infrastructure
*   **Dedicated Observability Backend:** Use specialized LLM tracing platforms (e.g., LangSmith, Braintrust, Datadog LLMObs) rather than dumping raw prompts into standard syslog, which ruins readability and breaches log sizing limits.
*   **Redaction:** Ensure sensitive PII or credentials are scrubbed *before* the prompt payload is sent to the tracing backend. *(AAIG L1: Safety & Security)*

### 3. Agent "Thought" Logs
*   When agents output `<thought>` tags or internal monologue, this text must not be discarded. It must be persisted in the trace. It is the only way to debug hallucination pathways.

## Quality Gates
*   **Trace Context Propagation:** Any API/System layer that triggers an LLM action must pass the `trace_id` down the stack. Commits made by the agent should optionally include the `Trace-ID` in the git commit footer.
*   **Cost Alerts:** Automated alerts must trigger if a single agent session exceeds a predefined token threshold, halting the workflow to prevent infinite recursive loops.

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **"Console.log" Debugging** | Dumping multi-megabyte prompt structures into standard output makes CI/CD logs unreadable. | Send LLM telemetry asynchronously to a dedicated tracing backend. |
| **Missing Model Versions** | Logging "Used GPT-4" is useless when OpenAI updates the model weights and behavior changes suddenly. | Always log the explicit deployment snapshot (e.g., `gpt-4-0613`). |
| **Discarding Prompts on Success** | Only logging the LLM context when an error occurs means you cannot study *why* an agent succeeds to optimize future prompts. | Sample or log all executions, not just failures. |

## See Also
*   [Monitoring & Observability](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/devops/monitoring_observability.md)
*   [Structured Logging](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/devops/structured_logging.md)
