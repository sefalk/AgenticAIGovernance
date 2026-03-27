---
name: databricks-model-serving
description: Deploy MLflow models and AI agents to Databricks serving endpoints — classical ML, custom PyFunc, GenAI agents (ResponsesAgent/LangGraph), Foundation Model APIs, and endpoint management.
argument-hint: '[focus: deploy|query|agents|classical-ml|foundation-models]'
---

# Databricks Model Serving

Deploy MLflow models and AI agents to scalable REST API endpoints.

## When to Use

- When deploying ML models (sklearn, xgboost, PyTorch) to production
- When serving GenAI agents (LangGraph, ResponsesAgent)
- When using Foundation Model APIs (GPT, Claude, Llama, Gemini)
- When querying deployed model/agent endpoints
- When managing endpoint lifecycle

## Deployment Decision

| What to Deploy | Pattern | Key Package |
|---------------|---------|-------------|
| Traditional ML (sklearn, xgboost) | `mlflow.sklearn.autolog()` | `mlflow` |
| Custom Python model | `mlflow.pyfunc.PythonModel` | `mlflow` |
| GenAI Agent | `ResponsesAgent` or LangGraph | `databricks-agents` |

## Foundation Model API Endpoints

Pay-per-token endpoints available in every workspace:

| Provider | Models | Context |
|----------|--------|---------|
| **OpenAI** | GPT-5, GPT-5-mini, GPT-5-nano, Codex | Up to 400K |
| **Anthropic** | Claude Opus 4.6, Sonnet 4.6/4.5/4, Haiku 4.5 | Up to 1M |
| **Meta** | Llama 3.3-70B, Llama 4 Maverick | 128K |
| **Google** | Gemini 3.1 Pro, 3 Flash, 2.5 Pro/Flash | Up to 1M |

**Common defaults:**
- Agent LLM: `databricks-meta-llama-3-3-70b-instruct`
- Embedding: `databricks-gte-large-en`
- Code: `databricks-gpt-5-1-codex-mini`

### Query Foundation Model

```python
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()

response = w.serving_endpoints.query(
    name="databricks-meta-llama-3-3-70b-instruct",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "What is Delta Lake?"}
    ],
    max_tokens=500
)
print(response.choices[0].message.content)
```

## Classical ML: Quick Start

```python
import mlflow
import mlflow.sklearn
from sklearn.linear_model import LogisticRegression

# Autolog with UC registration
mlflow.sklearn.autolog(
    log_input_examples=True,
    registered_model_name="catalog.schema.my_classifier"
)

# Train — model is logged and registered automatically
model = LogisticRegression()
model.fit(X_train, y_train)
```

## Custom PyFunc Model

```python
import mlflow

class MyModel(mlflow.pyfunc.PythonModel):
    def load_context(self, context):
        import joblib
        self.model = joblib.load(context.artifacts["model_path"])
        self.preprocessor = joblib.load(context.artifacts["preprocessor"])

    def predict(self, context, model_input, params=None):
        processed = self.preprocessor.transform(model_input)
        return self.model.predict(processed)

# Log model
mlflow.pyfunc.log_model(
    artifact_path="model",
    python_model=MyModel(),
    artifacts={
        "model_path": "model.joblib",
        "preprocessor": "preprocessor.joblib"
    },
    registered_model_name="catalog.schema.custom_model"
)
```

## GenAI Agent: ResponsesAgent

```python
from databricks.agents import ResponsesAgent

agent = ResponsesAgent(
    model="databricks-meta-llama-3-3-70b-instruct",
    instructions="You are a data engineering assistant...",
    tools=[...],  # UC functions, Vector Search, etc.
)

# Log agent
import mlflow
mlflow.pyfunc.log_model(
    artifact_path="agent",
    python_model=agent,
    registered_model_name="catalog.schema.my_agent"
)
```

## Endpoint Management (SDK)

```python
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()

# List endpoints
for ep in w.serving_endpoints.list():
    print(f"{ep.name}: {ep.state.ready}")

# Get endpoint status
ep = w.serving_endpoints.get(name="my-endpoint")
print(f"State: {ep.state.ready}")

# Query an endpoint (chat)
response = w.serving_endpoints.query(
    name="my-agent-endpoint",
    messages=[{"role": "user", "content": "Hello!"}],
    max_tokens=500
)

# Query an endpoint (ML model)
response = w.serving_endpoints.query(
    name="sklearn-classifier",
    dataframe_records=[
        {"age": 25, "income": 50000, "credit_score": 720}
    ]
)
```

## Endpoint Management (CLI)

```bash
# List endpoints
databricks serving-endpoints list

# Get endpoint status
databricks serving-endpoints get my-endpoint

# Query endpoint
databricks serving-endpoints query my-endpoint \
  --json '{"messages": [{"role": "user", "content": "Hello"}]}'
```

## Deployment via Job (Recommended)

For production deployments, use a job to avoid timeout issues:

```python
from databricks.sdk import WorkspaceClient
from databricks.sdk.service.serving import (
    EndpointCoreConfigInput,
    ServedEntityInput,
)

w = WorkspaceClient()

# Create/update endpoint
w.serving_endpoints.create_and_wait(
    name="my-production-endpoint",
    config=EndpointCoreConfigInput(
        served_entities=[
            ServedEntityInput(
                entity_name="catalog.schema.my_model",
                entity_version="1",
                workload_size="Small",
                scale_to_zero_enabled=True,
            )
        ]
    ),
)
```

## Common Issues

| Issue | Solution |
|-------|----------|
| Endpoint not ready | Wait for provisioning (2-10 min); check `state.ready` |
| Model version not found | Verify UC model path and version number |
| Permission denied | Check SP permissions on model and endpoint |
| Timeout on create | Use job-based deployment for large models |
| Package conflicts | Pin versions in `requirements.txt` or model conda env |

## Quality Gates

| Gate | Type | How to Verify |
|------|------|---------------|
| Model registered in Unity Catalog | HARD | UC path in `registered_model_name` |
| Endpoint uses scale-to-zero | SOFT | Review `scale_to_zero_enabled` |
| Foundation model names are exact | HARD | Match against endpoint list |
| Production uses provisioned throughput | SOFT | Review for cost/latency needs |

## References

- Model Serving: https://docs.databricks.com/en/machine-learning/model-serving/
- Foundation Models: https://docs.databricks.com/en/machine-learning/foundation-model-apis/
- MLflow Model Registry: https://mlflow.org/docs/latest/model-registry.html
