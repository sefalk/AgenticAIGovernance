**Version: 1.0 | Date: 2026-03-04**
**Level: 3 | Domain: ML Operations**
**Derived from:** [L2_ML_Operations.md](../domains/L2_ML_Operations.md) (Level 2)
**Operationalizes:** R-ML-01, R-ML-02, R-ML-03, R-ML-04, R-ML-05, R-ML-08, R-ML-10, R-ML-11, R-ML-15

---

# L3 Workflow — ML Model Development

## Purpose

This workflow defines the standard procedure for developing, evaluating, and deploying a machine learning model. It differs from the generic Feature Development workflow because ML quality gates are metric-based (F1, RMSE, AUC), not coverage-based, and ML development requires experiment tracking, reproducibility controls, and bias evaluation that have no equivalent in traditional software.

> **Adaptation Note:** Bind `[L4-DEFINED]` placeholders during L4 Project Instantiation.

---

## Phases

### Phase 1: Problem & Data Preparation
**Entry Criteria:** A business requirement exists that requires a predictive model (classification, regression, recommendation, etc.).

1. **Check for an existing WIP contract:** If a `WIP.md` file exists on the current branch, read it first and resume from the last completed step.
2. Define the **prediction target** and **success metrics** (R-ML-02). Document:
   - What is being predicted (target variable).
   - Which metrics will be used (e.g., F1 for classification, RMSE for regression).
   - What is the minimum acceptable performance threshold: `[L4-DEFINED: baseline metric]`.
2. Identify and collect training data. Document the data source, version, and any preprocessing applied.
3. Perform an **exploratory data analysis (EDA)**:
   - Check for class imbalance, missing values, outliers.
   - Document feature distributions and correlations.
4. Split data into **train / validation / test** sets (R-ML-01). The test set must be held out and never used during development.
5. If the model will serve user-facing predictions, identify **protected attributes** for bias evaluation (R-ML-08).

**Exit Criteria:** Data is prepared, splits are created, success metrics are defined.

---

### Phase 2: Baseline Model
**Entry Criteria:** Phase 1 is complete.

1. Train a **simple baseline model** (e.g., majority class, mean prediction, logistic regression) to establish a performance floor.
2. Evaluate baseline on the validation set. Record metrics in the experiment tracker: `[L4-DEFINED: tracking tool]` (e.g., MLflow, W&B) (R-ML-05).
3. This baseline is the comparator — any new model must demonstrably beat it (R-ML-04).

**Exit Criteria:** Baseline model trained, metrics logged, performance floor established.

---

### Phase 3: Development & Experimentation
**Entry Criteria:** Phase 2 baseline exists.

1. Develop the target model(s). For each experiment:
   - Log **all hyperparameters, code commit hash, and data version** (R-ML-05).
   - Set a **fixed random seed** for reproducibility (R-ML-03).
   - Pin all dependency versions in the lockfile.
2. Evaluate on the **validation set** (never the test set).
3. Iterate experiments within `[L4-DEFINED: max experiments, default 10]` (R-SD-25).
4. Separate training code from serving code from feature engineering code (R-ML-15).

**Exit Criteria:** A candidate model outperforms the baseline on validation metrics.

---

### Phase 4: Evaluation & Bias Check
**Entry Criteria:** A candidate model is selected from Phase 3.

1. Evaluate the candidate on the **held-out test set** (R-ML-01). This is the first and only time the test set is used.
2. Compare test metrics against:
   - The baseline model (R-ML-04): candidate must be statistically better.
   - The minimum threshold: `[L4-DEFINED: baseline metric]`.
3. If protected attributes were identified in Phase 1, run **bias/fairness evaluation** (R-ML-08):
   - Calculate performance parity across groups (e.g., equalized odds, demographic parity).
   - If discriminatory performance is detected, document the finding and mitigate before deployment.
4. Document feature importances for explainability.

> **Local Execution Gate:** In environments lacking automated CI pipeline triggers (e.g., local sandboxes or unconfigured repos), the agent itself MUST act as the primary quality gate executor by running local validations (tests, evaluators) and verifying the output before proposing a merge. Assuming models are sound simply because they matched validation metrics is a validation gap.

**Exit Criteria:** Test metrics beat baseline and threshold, bias check passed or mitigated.

---

### Phase 5: Register & Deploy
**Entry Criteria:** Phase 4 evaluation passes.

1. Save the model artifact to the **model registry**: `[L4-DEFINED: registry]` (e.g., MLflow Model Registry, SageMaker) (R-ML-10).
2. Tag the model with: version, training data hash, metrics, commit hash, author.
3. Integrate the model into the serving layer (API endpoint, batch job, embedded).
4. Set up **monitoring** for data drift and model degradation (R-ML-11):
   - Define drift detection thresholds: `[L4-DEFINED: drift threshold]`.
   - Configure alerts for metric degradation.
5. Define the **retraining cadence**: `[L4-DEFINED: retrain schedule]` (R-ML-13).

**Exit Criteria:** Model is registered, deployed, monitored, and retraining is scheduled.

---

### Phase 6: Review & Document
**Entry Criteria:** Phase 5 deployment is complete.

1. Create a PR/review artifact containing:
   - Experiment summary: baseline vs. candidate metrics.
   - Test set evaluation results.
   - Bias/fairness report (if applicable).
   - Model card (model type, intended use, limitations, training data).
2. Review and merge per standard review process.

**Exit Criteria:** PR merged, model card published.

---

## Quality Gates (ML-Specific)

| Gate | Threshold | Notes |
|------|-----------|-------|
| **Test set evaluation** | Mandatory, single use | Test set used exactly once — in Phase 4 |
| **Baseline comparison** | Must beat baseline | R-ML-04: statistically significant improvement |
| **Metric threshold** | `[L4-DEFINED]` | Minimum acceptable performance for production |
| **Bias/Fairness check** | Pass or document mitigation | R-ML-08: required for user-facing models |
| **Reproducibility** | Verified | R-ML-03: re-run with same seed produces same result |
| **Experiment tracking** | All runs logged | R-ML-05: hyperparams + data version + metrics |
| **Model registered** | In registry, not local | R-ML-10: no local-machine deployments |
