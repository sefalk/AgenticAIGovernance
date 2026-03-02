---
category: data_science
applies_to: [ml]
complexity: intermediate
maturity: reviewed
version: "1.0"
last_reviewed: 2026-02-26
related: [model_evaluation, ml_pipeline_design, exploratory_data_analysis, model_selection]
---
# Experiment Tracking & Reproducibility

## Purpose

Experiment tracking systematically records every model training run -- parameters, metrics, code versions, data versions, and artifacts -- so experiments are reproducible, comparable, and auditable. Invoke this skill when setting up an ML project, defining Level-3 ML workflows, or establishing Level-4 experiment tracking standards.

## Principles

- **Transparency (AAIG L1):** Every experiment must be fully traceable. Given an experiment ID, anyone must be able to reconstruct the exact code, data, parameters, and environment that produced the result.
- **Verifiability (AAIG L1):** Results must be reproducible. Same code + same data + same parameters = same metrics (within stochastic tolerance).
- **Continuous Improvement (AAIG L1):** Experiment history is the institutional memory of the project. It enables informed iteration and prevents re-running failed approaches.
- **Immutability:** Logged experiments must not be modified after completion. Corrections are logged as new experiments with references to the original.

## Techniques & Patterns

### What to Track

```
Per experiment:
  - Unique run ID (auto-generated)
  - Timestamp (start, end, duration)
  - Git commit hash + dirty flag
  - Branch name
  - Data version (hash, DVC pointer, or dataset registry ID)
  - Full hyperparameter dictionary
  - All evaluation metrics (train, validation, test)
  - Model artifacts (serialized model, ONNX export)
  - Environment (Python version, requirements hash, CUDA version)
  - Hardware (GPU model, RAM, CPU count)
  - Random seeds (all of them: Python, NumPy, PyTorch/TF, CUDA)
  - Tags and notes (human-readable context)
```

### Tool Landscape

| Tool | Type | Strengths | When to Use |
|------|------|-----------|-------------|
| **MLflow** | Open-source, self-hosted | Flexible, model registry, REST API, broad framework support | Default choice for most teams |
| **Weights & Biases** | SaaS | Beautiful dashboards, team collaboration, sweeps | Teams needing collaboration + visualization |
| **DVC** | Data versioning | Git-like data versioning, pipeline DAGs | Data-heavy projects, large file versioning |
| **Neptune** | SaaS | Metadata store, flexible structure | Research teams needing custom metadata |
| **ClearML** | Open-source + SaaS | Auto-logging, pipeline orchestration | Teams wanting experiment + pipeline in one |

### Data Versioning Strategies

| Strategy | Tool | Use Case |
|----------|------|----------|
| **Hash-based pointers** | DVC | Large datasets stored in S3/GCS, versioned via git |
| **Dataset registry** | MLflow Datasets, HuggingFace | Shared, named dataset versions |
| **Snapshot + metadata** | Custom | Small datasets stored directly with experiment |
| **Feature store** | Feast, Tecton | Features computed once, reused across experiments |

### Reproducibility Checklist

1. **Pin all seeds:** `random.seed(42)`, `np.random.seed(42)`, `torch.manual_seed(42)`, `torch.cuda.manual_seed_all(42)`.
2. **Pin dependencies:** `pip freeze > requirements.txt` or lock with Poetry/uv.
3. **Pin data:** Record exact data version (hash, DVC ref, or snapshot).
4. **Pin code:** Log git commit. Fail if working directory is dirty (uncommitted changes).
5. **Deterministic operations:** Set `torch.use_deterministic_algorithms(True)`, `CUBLAS_WORKSPACE_CONFIG=:4096:8`.
6. **Environment capture:** Log Python version, OS, GPU driver, CUDA version.

### Experiment Naming Convention

```
{project}/{model_type}/{date}-{short_description}

Examples:
  churn/xgboost/2026-02-26-baseline
  churn/xgboost/2026-02-26-add-recency-features
  churn/transformer/2026-02-26-attention-only
```

### MLflow Quickstart Pattern

```python
import mlflow

mlflow.set_experiment("churn-prediction")

with mlflow.start_run(run_name="xgboost-baseline"):
    mlflow.log_params({"max_depth": 6, "lr": 0.1, "n_estimators": 500})
    mlflow.set_tag("data_version", "v2.3")
    mlflow.set_tag("git_commit", get_git_hash())

    model = train(params)

    mlflow.log_metrics({"auc": 0.87, "f1": 0.72, "precision": 0.80})
    mlflow.sklearn.log_model(model, "model")
    mlflow.log_artifact("confusion_matrix.png")
```

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Every run tracked** | 100% | No untracked training runs. Enforce via CI/pre-commit. |
| **Data version recorded** | Every run | Hash or DVC pointer logged. |
| **Code version recorded** | Every run | Git commit hash. Dirty flag must be false for production runs. |
| **Seeds logged** | Every run | All random seeds explicitly set and recorded. |
| **Reproducibility verified** | Quarterly | Re-run a random past experiment. Metrics must match within tolerance. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Notebook-only experiments** | Results exist only in a Jupyter notebook with no tracking. Lost when kernel restarts. | Integrate MLflow/W&B into every training script. |
| **Manual spreadsheet tracking** | Google Sheet of results. No code linkage, no artifact storage. | Migrate to a proper experiment tracker. |
| **Overwriting runs** | Re-using the same run ID or experiment name for different configs. History lost. | Every run gets a unique auto-generated ID. Never overwrite. |
| **Sacred seed neglect** | "I forgot to set the seed." Non-reproducible results. | Seed-setting as the first line of training scripts. CI check. |
| **Data drift ignored** | Training on v1 data, evaluating claims against v2. Invalid comparison. | Log data version. Compare only experiments on the same data version. |
| **Metric cherry-picking** | Reporting only the best metric across runs. Publication bias. | Log ALL metrics for ALL runs. Compare distributions, not maximums. |

## See Also

- [Model Evaluation](../data_science/model_evaluation.md)
- [ML Pipeline Design](../data_science/ml_pipeline_design.md)
- [Exploratory Data Analysis](../data_science/exploratory_data_analysis.md)

## References

- MLflow: https://mlflow.org/
- Weights & Biases: https://wandb.ai/
- DVC: https://dvc.org/
- Feast: https://feast.dev/
- Neptune: https://neptune.ai/
