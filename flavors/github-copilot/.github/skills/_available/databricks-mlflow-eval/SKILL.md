---
name: databricks-mlflow-eval
description: MLflow 3 GenAI evaluation — scorers, evaluation datasets, trace analysis, judge alignment, prompt optimisation, and production monitoring patterns.
argument-hint: '[focus: evaluate|scorers|datasets|traces|alignment|optimization]'
---

# MLflow GenAI Evaluation

Evaluate GenAI agents and LLM applications using MLflow 3's evaluation
framework — scorers, datasets, traces, and automated prompt optimisation.

## When to Use

- When evaluating LLM/agent quality (correctness, safety, groundedness)
- When building evaluation datasets from production traces
- When creating custom scorers for domain-specific quality metrics
- When aligning LLM judges to match domain expert preferences
- When automating prompt improvement with GEPA
- When monitoring production agent quality

## Critical API Facts

| Fact | Detail |
|------|--------|
| **Correct import** | `mlflow.genai.evaluate()` (NOT `mlflow.evaluate()`) |
| **Data format** | `{"inputs": {"query": "..."}}` — nested structure required |
| **predict_fn** | Receives `**unpacked kwargs` (not a dict) |
| **MemAlign** | Scorer-agnostic; set `embedding_model` explicitly |
| **optimize_prompts** | Requires MLflow >= 3.5.0 |

## Evaluation Quick Start

```python
import mlflow
from mlflow.genai.scorers import Guidelines, Correctness, Safety

# Define evaluation dataset
eval_data = [
    {"inputs": {"query": "What is Unity Catalog?"}, 
     "expectations": {"expected_response": "Unity Catalog is..."}},
    {"inputs": {"query": "How to create a table?"},
     "expectations": {"expected_response": "Use CREATE TABLE..."}},
]

# Define the agent function
def predict_fn(query: str) -> str:
    # Call your agent/model here
    return agent.invoke(query)

# Run evaluation
results = mlflow.genai.evaluate(
    data=eval_data,
    predict_fn=predict_fn,
    scorers=[
        Correctness(),
        Safety(),
        Guidelines(name="conciseness", 
                   guidelines="Response should be under 200 words"),
    ],
)

print(results.metrics)
```

## Built-in Scorers

| Scorer | What It Measures |
|--------|-----------------|
| `Correctness()` | Response matches expected answer |
| `Safety()` | No harmful/toxic content |
| `RetrievalGroundedness()` | Response is grounded in retrieved context |
| `RetrievalRelevance()` | Retrieved docs are relevant to query |
| `Guidelines(name, guidelines)` | Custom criteria defined in natural language |

## Custom Scorers

```python
from mlflow.genai.scorers import scorer

@scorer
def response_length(inputs, outputs):
    """Check if response is within length bounds."""
    length = len(outputs.get("response", ""))
    return {
        "score": 1.0 if 50 <= length <= 500 else 0.0,
        "justification": f"Response length: {length} chars"
    }

@scorer
def has_sources(inputs, outputs):
    """Check if response cites sources."""
    response = outputs.get("response", "")
    has_citation = "[Source:" in response or "Reference:" in response
    return {
        "score": 1.0 if has_citation else 0.0,
        "justification": "Sources cited" if has_citation else "No sources"
    }
```

## Datasets from Traces

```python
import mlflow

# Search production traces
traces = mlflow.search_traces(
    experiment_ids=["123"],
    filter_string="status = 'OK' AND timestamp > '2026-03-01'",
    max_results=100,
)

# Build evaluation dataset from traces
eval_data = []
for trace in traces:
    eval_data.append({
        "inputs": {"query": trace.data.request},
        "expectations": {"expected_response": trace.data.response},
    })
```

## Judge Alignment (MemAlign)

Align an LLM judge to match domain expert preferences:

```python
from mlflow.genai import make_judge, align

# 1. Create base judge
judge = make_judge(
    name="domain_quality",
    guidelines="Evaluate response quality for medical domain...",
    feedback_value_type="float",  # or "bool", categorical
)

# 2. Run evaluation, tag good traces for labeling
results = mlflow.genai.evaluate(data=eval_data, scorers=[judge])

# 3. Create labeling session for SME review (via UI)
# 4. After SME labels are collected:
aligned_judge = align(
    judge=judge,
    labeling_session_name="domain_review_v1",
    embedding_model="databricks-gte-large-en",
)

# 5. Re-evaluate with aligned judge
results = mlflow.genai.evaluate(data=eval_data, scorers=[aligned_judge])
```

## Prompt Optimisation (GEPA)

```python
from mlflow.genai import optimize_prompts

# Dataset needs both inputs AND expectations
opt_data = [
    {"inputs": {"query": "..."}, "expectations": {"expected_response": "..."}},
]

# Run optimisation
result = optimize_prompts(
    data=opt_data,
    scorer=aligned_judge,  # or any scorer
    prompt_template="You are a helpful assistant. {query}",
    max_iterations=10,
)

print(result.best_prompt)
print(result.best_score)
```

## Production Monitoring

```python
# Link UC schema to experiment for trace storage
mlflow.set_experiment("/Users/user@company.com/prod-agent")

# Set trace destination to Unity Catalog
mlflow.set_trace_destination(
    catalog="my_catalog",
    schema="monitoring"
)

# Query stored traces via SQL
# SELECT * FROM my_catalog.monitoring.traces
# WHERE timestamp > current_date() - 7
```

## Workflows

| Goal | Steps |
|------|-------|
| **First-time setup** | Build dataset → Choose scorers → Run evaluate |
| **Production analysis** | Search traces → Filter quality → Build dataset → Evaluate |
| **Performance debug** | Profile latency → Analyse tokens → Optimise context |
| **Regression detect** | Establish baseline → Run new version → Compare metrics |
| **Judge alignment** | Create judge → Evaluate → SME labeling → Align → Re-evaluate |
| **Prompt optimisation** | Build opt dataset → `optimize_prompts()` → Register best |

## Quality Gates

| Gate | Type | How to Verify |
|------|------|---------------|
| Uses `mlflow.genai.evaluate()` not `mlflow.evaluate()` | HARD | Code review |
| Data format uses nested `inputs` dict | HARD | Schema check |
| Custom scorers return `score` + `justification` | HARD | Test scorer output |
| Aligned judges tested against baseline | SOFT | Compare metrics |
| Optimised prompts validated on held-out set | SOFT | Cross-validation |

## References

- MLflow GenAI Evaluation: https://mlflow.org/docs/latest/llms/genai/
- MLflow Scorers: https://mlflow.org/docs/latest/llms/genai/scorers.html
- MLflow Tracing: https://mlflow.org/docs/latest/llms/tracing/
