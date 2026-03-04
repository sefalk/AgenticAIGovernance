# Rubric: L2 ML Operations Domain

**Evaluates:** L2 Domain Rules → ML Operations (15 rules)
**Source:** [L2_ML_Operations.md](../../../domains/L2_ML_Operations.md)

---

> This rubric evaluates all 15 R-ML rules. Rules are grouped by parent L1 principle.

---

## From: Verifiability & Quality Assurance

### R-ML-01: Held-out Test Set Evaluation
| Score | Criteria |
|-------|----------|
| **Pass** | Model evaluated on strict held-out test set; overfitting checked |
| **Partial** | Evaluated on validation set, no true held-out test set |
| **Fail** | Model evaluated on training data |

### R-ML-02: Pre-defined Metrics
| Score | Criteria |
|-------|----------|
| **Pass** | Performance metrics defined before training and logged properly |
| **Partial** | Metrics defined loosely, tracked inconsistently |
| **Fail** | Ad-hoc metric selection post-training |

### R-ML-03: Reproducible Training
| Score | Criteria |
|-------|----------|
| **Pass** | Fixed seeds, pinned deps, versioned data, logged hyperparams |
| **Partial** | Hyperparams logged but data or seeds are unversioned |
| **Fail** | Unreproducible training runs |

### R-ML-04: Baseline Comparison
| Score | Criteria |
|-------|----------|
| **Pass** | New model deployed only if it shows statistically significant improvement over baseline |
| **Partial** | Comparison made, but deployed despite marginal/unproven improvement |
| **Fail** | Model deployed blindly without baseline comparison |

---

## From: Transparency/Traceability

### R-ML-05: Experiment Tracking
| Score | Criteria |
|-------|----------|
| **Pass** | All runs tracked (MLflow/W&B); includes hyperparams, metrics, artifacts, data version |
| **Partial** | Basic tracking, but artifacts or data versions missing |
| **Fail** | No centralized experiment tracking logs |

### R-ML-06: Documented Feature Engineering
| Score | Criteria |
|-------|----------|
| **Pass** | Each feature transformation, encoding, and imputation strategy is documented |
| **Partial** | Vague high-level descriptions without exact parameters |
| **Fail** | Undocumented black-box feature transformations |

### R-ML-07: Prediction Logging
| Score | Criteria |
|-------|----------|
| **Pass** | Prod predictions logged with context (inputs, score, version) for auditing |
| **Partial** | Predictions logged but missing full inputs or confidence scores |
| **Fail** | Predictions sent verbatim with no auditing log |

---

## From: Safety & Security

### R-ML-08: Bias & Fairness Evaluation
| Score | Criteria |
|-------|----------|
| **Pass** | Model evaluated for bias across protected attributes; mitigation documented if needed |
| **Partial** | Bias checked on some slices, but comprehensive evaluation lacking |
| **Fail** | No bias or fairness checks before user predictions served |

### R-ML-09: Data Poisoning Scanning
| Score | Criteria |
|-------|----------|
| **Pass** | Training data scanned for anomalies/poisoning risks and flagged |
| **Fail** | No scanning of training data |

### R-ML-10: Secure Model Registry
| Score | Criteria |
|-------|----------|
| **Pass** | Artifacts in versioned registry; no direct local deployments |
| **Fail** | Direct deployment from local machine or unversioned storage |

---

## From: Fail-Safe & Ask First

### R-ML-11: Drift Monitoring
| Score | Criteria |
|-------|----------|
| **Pass** | Monitoring tracks data drift and triggers alerts/retraining logic |
| **Partial** | Logging exists but lacks active alerting on drift |
| **Fail** | No drift monitoring in production |

### R-ML-12: Inference Fallback Behavior
| Score | Criteria |
|-------|----------|
| **Pass** | Defined fallback (default rule, simpler model, graceful decline) for inference failure |
| **Partial** | Generic 500 API error without a domain-specific fallback |
| **Fail** | Unhandled exceptions bubble up to users on bad input |

---

## From: Continuous Improvement

### R-ML-13: Retraining Cadence
| Score | Criteria |
|-------|----------|
| **Pass** | Model has defined retraining schedule (time-based or drift-triggered) |
| **Fail** | No retraining plan; model left to decay indefinitely |

### R-ML-14: Offline vs Online Comparison
| Score | Criteria |
|-------|----------|
| **Pass** | Retrospective compares predicted (offline) vs actual (production) performance |
| **Fail** | No continuous evaluation of production outputs against ground truth |

---

## From: Separation of Concern

### R-ML-15: Modular Architecture
| Score | Criteria |
|-------|----------|
| **Pass** | Training, feature eng, and serving code separated into distinct modules |
| **Partial** | Separation exists but messy boundaries between tasks |
| **Fail** | Monolithic notebooks deployed directly as production inference |
