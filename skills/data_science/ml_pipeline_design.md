---
category: data_science
applies_to: [ml, cloud]
complexity: advanced
maturity: reviewed
version: "1.0"
last_reviewed: 2026-02-26
related: [experiment_tracking, model_evaluation, feature_engineering, ci_cd, containerization, monitoring_observability]
---
# ML Pipeline Design

## Purpose

ML pipeline design covers the end-to-end orchestration of machine learning workflows: from data ingestion through feature engineering, training, evaluation, deployment, and monitoring. This skill bridges data science and MLOps, ensuring models are not just trained in notebooks but shipped, served, and maintained in production. Invoke this skill when designing training pipelines, model serving infrastructure, or Level-3 MLOps workflows.

## Principles

- **Verifiability (AAIG L1):** Every pipeline step must have defined inputs, outputs, and quality gates. A pipeline that "just runs" without validation is a risk.
- **Transparency (AAIG L1):** Pipeline lineage must be fully traceable: from raw data to deployed model, every transformation, parameter, and version is recorded.
- **Continuous Improvement (AAIG L1):** Models degrade over time (data drift, concept drift). Pipelines must include monitoring and automated retraining triggers.
- **Idempotency:** Running the same pipeline with the same inputs must produce the same outputs. This enables safe retries and debugging.
- **Separation of concern:** Data preprocessing, feature engineering, training, evaluation, and serving are distinct stages with clear interfaces.

## Techniques & Patterns

### Pipeline Architecture

```
Data Ingestion --> Validation --> Feature      --> Training  --> Evaluation
                   (schema,       Engineering      (model,       (metrics,
                    stats)        (transforms)      params)       fairness)
                                                      |
                                                      v
                                            Model Registry
                                        (versioned, staged)
                                                      |
                                          +-----------+-----------+
                                          |                       |
                                    Batch Serving           Online Serving
                                    (Spark, Airflow)        (REST/gRPC, <10ms)
                                          |                       |
                                          +-----------+-----------+
                                                      |
                                                      v
                                                 Monitoring
                                     (data drift, model perf, latency)
                                                      |
                                                      v
                                              Retrain Trigger
```

### Orchestration Tools

| Tool | Type | Strengths | Best For |
|------|------|-----------|----------|
| **Kubeflow Pipelines** | Kubernetes-native | Scalable, component-based, caching | Large teams, complex pipelines |
| **Vertex AI Pipelines** | GCP managed | Integrated with GCP ML stack | GCP-native projects |
| **SageMaker Pipelines** | AWS managed | Integrated with SageMaker | AWS-native projects |
| **MLflow Pipelines** | Framework-agnostic | Simple, local-first | Small teams, rapid prototyping |
| **Airflow** | General orchestration | Mature, flexible, DAG-based | When ML is part of larger data workflows |
| **Dagster** | Modern orchestration | Strong typing, asset-based | Data-aware ML pipelines |
| **Prefect** | Modern orchestration | Python-native, dynamic workflows | Flexible pipeline definitions |
| **ZenML** | MLOps framework | Tool-agnostic, stack abstraction | Teams wanting tool flexibility |

### Model Serving Patterns

| Pattern | Latency | Use Case | Tools |
|---------|---------|----------|-------|
| **REST API** | 10-100ms | Real-time predictions, web apps | FastAPI, Flask, TF Serving, Triton |
| **gRPC** | 1-10ms | Low-latency, inter-service | TF Serving, Triton, gRPC |
| **Batch prediction** | Minutes-hours | Scoring large datasets, ETL | Spark, Airflow, SageMaker Batch |
| **Streaming** | Sub-second | Event-driven predictions | Kafka + model, Flink, Spark Streaming |
| **Edge / embedded** | Microseconds | On-device inference | ONNX Runtime, TFLite, CoreML |

### Model Registry Workflow

```
1. Train model --> Log to experiment tracker
2. Evaluate     --> Pass quality gates (metrics, fairness, latency)
3. Register     --> Push to model registry (version, stage: "staging")
4. Validate     --> Integration tests, shadow scoring, A/B setup
5. Promote      --> Move to "production" stage
6. Monitor      --> Alerting on drift, performance degradation
7. Deprecate    --> Archive when replaced. Keep artifacts for audit.
```

### Deployment Strategies

| Strategy | Risk | Use Case |
|----------|------|----------|
| **Shadow mode** | Zero | New model scores alongside production. Outputs compared, not served. |
| **Canary** | Low | Route small % of traffic to new model. Monitor metrics. Gradually increase. |
| **A/B testing** | Low | Statistical comparison of two models on live traffic. Requires traffic splitting. |
| **Blue/green** | Medium | Instant cutover. Rollback by switching back. No traffic splitting needed. |
| **Direct replacement** | High | Replace model in-place. Only for low-risk models with strong offline evaluation. |

### Data & Model Monitoring

| Monitor | What | Alert When |
|---------|------|------------|
| **Data drift** | Feature distribution shift (PSI, KS test) | PSI > 0.2 or KS p-value < 0.05 |
| **Concept drift** | Model output distribution shift | Prediction distribution changes significantly |
| **Performance degradation** | Live metrics vs baseline | AUC drops > 5% from baseline |
| **Latency** | Inference time p50, p95, p99 | p99 > SLA threshold |
| **Feature freshness** | Feature store staleness | Feature > N hours stale |

**Tools:** Evidently AI, NannyML, Arize, WhyLabs, custom Prometheus + Grafana.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Offline evaluation passes** | Exceeds baseline + minimum threshold | Per model evaluation quality gates |
| **Data validation passes** | Schema + statistics check | Great Expectations, TFX Data Validation |
| **Model registry versioned** | Every deployed model | Model artifact, parameters, metrics, data version recorded |
| **Integration tests pass** | Before promotion to production | Input/output contract, latency, error handling |
| **Monitoring configured** | Before production deployment | Data drift, performance, latency alerts active |
| **Rollback plan documented** | Before production deployment | How to revert to previous model version |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Notebook-to-production** | Copying notebook code into a Flask app. No pipeline, no tests, no monitoring. | Build a proper pipeline from the start. Notebooks for EDA only. |
| **Train once, serve forever** | Model deployed and never retrained. Performance degrades silently. | Monitoring + automated retraining triggers. |
| **No shadow testing** | Deploying directly to production without comparison. Risky. | Shadow mode or canary deployment as mandatory first step. |
| **Monolithic pipeline** | One giant script that does everything. Can't rerun a single step. | Separate stages with defined interfaces. Cache intermediate results. |
| **Missing rollback** | No way to revert to the previous model version. One bad deployment = outage. | Model registry with versioning. One-click rollback. |
| **GPU hoarding** | Training jobs hold GPU instances 24/7. Expensive. | Spot instances, auto-scaling, preemptible VMs. Release GPUs when idle. |

## See Also

- [Experiment Tracking](../data_science/experiment_tracking.md)
- [Model Evaluation](../data_science/model_evaluation.md)
- [Feature Engineering](../data_science/feature_engineering.md)
- [CI/CD](../devops/ci_cd.md)
- [Containerization](../devops/containerization.md)
- [Monitoring & Observability](../devops/monitoring_observability.md)

## References

- MLflow: https://mlflow.org/
- Kubeflow: https://www.kubeflow.org/
- Evidently AI: https://evidentlyai.com/
- NannyML: https://nannyml.com/
- Google MLOps maturity model: https://cloud.google.com/architecture/mlops-continuous-delivery-and-automation-pipelines-in-machine-learning
