**Version: 1.0 | Date: 2026-03-04**
**Level: 2 | Domain: ML Operations**
**Derived from:** [L1_Core_Principles.md](L1_Core_Principles.md) (Level 1, v3.8)

---

# Level 2 — ML Operations Domain Rules

## Purpose

This artifact derives domain-specific rules for Machine Learning model development, training, evaluation, and deployment from the Level-1 Core Principles. These rules apply to all ML/AI projects regardless of framework (PyTorch, TensorFlow, scikit-learn, XGBoost). They are declarative constraints (SHALL/SHALL NOT) that Level-3 workflows must operationalize.

> **Note:** Rule IDs are grouped by their parent L1 principle, not assigned sequentially.

---

## Derived Rules

### From: Verifiability & Quality Assurance (L1)

**R-ML-01:** All models SHALL be evaluated against a held-out test set that was never used during training or hyperparameter tuning. Overfitting to validation data SHALL be treated as a defect.

**R-ML-02:** Model performance metrics SHALL be defined before training begins and documented in the experiment log. Metrics must be appropriate to the problem type (e.g., F1 for classification, RMSE for regression, BLEU for NLP).

**R-ML-03:** All training runs SHALL be reproducible. This requires: fixed random seeds, pinned dependency versions, versioned training data, and logged hyperparameters.

**R-ML-04:** Models deployed to production SHALL have a baseline comparison. A new model SHALL NOT replace an existing model unless it demonstrates statistically significant improvement on the defined metrics.

### From: Transparency/Traceability (L1)

**R-ML-05:** Every experiment SHALL be tracked in an experiment tracking system (e.g., MLflow, Weights & Biases). Tracked artifacts must include: hyperparameters, metrics, model artifacts, training data version, and code commit hash.

**R-ML-06:** Feature engineering pipelines SHALL document the transformation applied to each feature, including encoding schemes, normalization parameters, and imputation strategies.

**R-ML-07:** Model predictions in production SHALL be logged with sufficient context (input features, prediction, confidence score, model version) to enable post-hoc auditing.

### From: Safety & Security (L1)

**R-ML-08:** All models serving user-facing predictions SHALL undergo bias and fairness evaluation across protected attributes (e.g., gender, ethnicity, age) before deployment. Models exhibiting discriminatory performance SHALL NOT be deployed without documented mitigation.

**R-ML-09:** Training data SHALL be scanned for data poisoning risks. Anomalous training examples that could skew model behavior SHALL be flagged and reviewed.

**R-ML-10:** Model artifacts (weights, checkpoints) SHALL be stored in a secure, versioned model registry. Direct deployment from a developer's local machine SHALL NOT be permitted.

### From: Fail-Safe & Ask First (L1)

**R-ML-11:** Production models SHALL have monitoring for data drift and model degradation. When input distributions shift beyond a defined threshold, an alert SHALL be triggered and the model SHALL be flagged for retraining.

**R-ML-12:** All model inference endpoints SHALL have fallback behavior defined (e.g., returning a default prediction, routing to a simpler model, or gracefully declining to predict).

### From: Continuous Improvement (L1)

**R-ML-13:** Models SHALL be retrained on a defined cadence (time-based or drift-triggered). Models without a retraining schedule SHALL be flagged as stale.

**R-ML-14:** Post-deployment, a retrospective SHALL compare predicted performance (offline metrics) against actual production performance. Significant gaps SHALL trigger investigation.

### From: Separation of Concern (L1)

**R-ML-15:** Training code, serving code, and feature engineering code SHALL be separated into distinct modules. Monolithic notebooks combining all three SHALL NOT be deployed to production.

---

## Applicability

These rules apply to all ML/AI projects governed by the AAIG framework, including supervised learning, unsupervised learning, deep learning, NLP, and computer vision. They are refined at Level 3 (workflows) and Level 4 (project bindings).

## Relationship to Skills Toolbox

- R-ML-01, R-ML-02, R-ML-04 → `model_evaluation.md`
- R-ML-03, R-ML-05 → `experiment_tracking.md`
- R-ML-06 → `feature_engineering.md`
- R-ML-08 → `model_evaluation.md` (bias/fairness section)
- R-ML-10, R-ML-11, R-ML-13 → `ml_pipeline_design.md`
- R-ML-07, R-ML-11 → `monitoring_observability.md`
