---
category: data_science
applies_to: [ml]
complexity: intermediate
maturity: reviewed
version: "1.0"
last_reviewed: 2026-02-26
related: [experiment_tracking, feature_engineering, exploratory_data_analysis, ml_pipeline_design, model_selection]
---
# Model Evaluation & Validation

## Purpose

Model evaluation systematically measures how well a model performs, how fairly it behaves, and whether it generalizes to unseen data. This skill covers metric selection, validation strategies, bias/fairness auditing, and statistical rigor. Invoke this skill when defining evaluation frameworks, comparing models, or setting up Level-3 model validation workflows.

## Principles

- **Verifiability (AAIG L1):** Model performance claims must be backed by reproducible metrics on held-out data. No "the model works well" without numbers.
- **Transparency (AAIG L1):** Evaluation methodology, including metric choices and dataset splits, must be documented and justified.
- **Fairness:** Models must be evaluated for disparate impact across protected groups. Performance on the majority class is not sufficient.
- **Statistical rigor:** Single-number metrics hide variance. Use confidence intervals, cross-validation, and statistical tests.

## Techniques & Patterns

### Metric Selection by Task

| Task | Primary Metrics | When to Prefer |
|------|----------------|----------------|
| **Binary classification** | AUC-ROC, F1, Precision, Recall | AUC for ranking; F1 for balanced classes; Precision if false positives are costly; Recall if false negatives are costly |
| **Multi-class classification** | Macro-F1, Weighted-F1, Confusion matrix | Macro for equal class importance; Weighted for imbalanced classes |
| **Regression** | RMSE, MAE, MAPE, R-squared | RMSE penalizes large errors; MAE for outlier-robust; MAPE for relative error |
| **Ranking** | NDCG, MAP, MRR | NDCG for graded relevance; MAP for binary relevance |
| **Clustering** | Silhouette, Calinski-Harabasz, ARI | Silhouette for cluster quality; ARI when ground truth is available |
| **Time series** | MASE, SMAPE, CRPS | MASE is scale-independent; CRPS for probabilistic forecasts |
| **NLP / generation** | BLEU, ROUGE, BERTScore, human eval | Automated metrics for development; human eval for final assessment |

### Validation Strategies

| Strategy | When to Use | Pitfall |
|----------|------------|---------|
| **Holdout** (train/val/test) | Large datasets (> 100k) | Variance in small datasets |
| **K-fold cross-validation** | Medium datasets | Expensive; data leakage if preprocessing not inside fold |
| **Stratified K-fold** | Imbalanced classes | Default for classification tasks |
| **Time-series split** | Temporal data | Must not shuffle; expanding or sliding window |
| **Group K-fold** | Grouped data (e.g., same patient) | Prevents same group in train and test |
| **Nested cross-validation** | Hyperparameter tuning + evaluation | Outer loop for evaluation, inner for tuning |
| **Bootstrap** | Confidence intervals | Computationally expensive; good for small datasets |

### Confidence Intervals and Statistical Tests

```python
# Bootstrap confidence interval for AUC
from sklearn.utils import resample
aucs = []
for _ in range(1000):
    idx = resample(range(len(y_test)), n_samples=len(y_test))
    aucs.append(roc_auc_score(y_test[idx], y_pred[idx]))
lower, upper = np.percentile(aucs, [2.5, 97.5])
print(f"AUC: {np.mean(aucs):.3f} (95% CI: {lower:.3f}-{upper:.3f})")
```

**When comparing two models:**
- **McNemar's test:** For paired binary classification predictions
- **Paired t-test on CV folds:** For k-fold cross-validation results
- **DeLong's test:** For comparing AUC-ROC curves
- **Corrected resampled t-test:** For repeated cross-validation (Nadeau & Bengio correction)

### Bias & Fairness Auditing

| Fairness Metric | Definition | When to Use |
|----------------|------------|-------------|
| **Demographic parity** | P(positive prediction) equal across groups | When equal selection rates matter |
| **Equalized odds** | TPR and FPR equal across groups | When error rates must be equal |
| **Predictive parity** | Precision equal across groups | When prediction confidence must be equal |
| **Calibration** | Predicted probabilities match actual frequencies | When probabilities are used for decisions |

**Tools:**
- `fairlearn`: Microsoft's fairness toolkit. Metrics + mitigation algorithms.
- `aequitas`: Bias audit toolkit. Group fairness metrics.
- `AI Fairness 360`: IBM's toolkit. Broad metric coverage.

### Model Explainability (Post-hoc)

| Method | Scope | Use Case |
|--------|-------|----------|
| **SHAP** | Global + local | Default choice. Theoretically grounded. |
| **LIME** | Local | Single-prediction explanations |
| **Permutation importance** | Global | Model-agnostic feature importance |
| **Partial dependence plots** | Global | Feature effect visualization |
| **Counterfactual explanations** | Local | "What would need to change for a different outcome?" |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Baseline established** | Before any model training | Naive baseline (majority class, mean, last value) documented |
| **Metrics on held-out test** | Reported for final model | Never choose model based on test set. Report once. |
| **Confidence intervals** | Reported for primary metric | Bootstrap or cross-validation based |
| **Fairness audit** | For user-facing models | At minimum: demographic parity and equalized odds across protected groups |
| **Calibration check** | For probability-based decisions | Reliability diagram + Brier score |
| **Cross-validation variance** | CV std < 0.05 for primary metric | High variance signals overfitting or data quality issues |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Accuracy obsession** | Using accuracy for imbalanced classes. 95% accuracy with 95% majority class is useless. | Use class-balanced metrics: F1, AUC, MCC. |
| **Train/test contamination** | Preprocessing (scaling, encoding) fitted on full dataset before split. Inflated metrics. | All preprocessing inside cross-validation folds. |
| **Single metric reporting** | Reporting only AUC without precision/recall trade-off. Hides operational reality. | Report multiple metrics. Show precision-recall curve at various thresholds. |
| **Ignoring fairness** | Model deployed without bias audit. Legal and ethical risk. | Fairness metrics as mandatory quality gates for user-facing models. |
| **Overfitting to validation** | Running hundreds of experiments, picking the best validation score. Implicit data leakage. | Use a true held-out test set. Report test metrics ONCE, at the end. |
| **Threshold default** | Using 0.5 as classification threshold without analysis. | Optimize threshold on validation set based on business requirements. |

## See Also

- [Experiment Tracking](../data_science/experiment_tracking.md)
- [Feature Engineering](../data_science/feature_engineering.md)
- [Exploratory Data Analysis](../data_science/exploratory_data_analysis.md)

## References

- scikit-learn model evaluation: https://scikit-learn.org/stable/modules/model_evaluation.html
- fairlearn: https://fairlearn.org/
- SHAP: https://github.com/shap/shap
- Nadeau & Bengio (2003). Inference for the Generalization Error. Machine Learning, 52(3).
