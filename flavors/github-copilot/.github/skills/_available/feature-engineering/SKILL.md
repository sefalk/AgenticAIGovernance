---
name: feature-engineering
description: Transform raw data into informative ML representations — feature types, encoding strategies, leakage prevention, feature stores, and feature selection methods.
argument-hint: '[type: numeric|categorical|text|temporal|geo|aggregation] [focus: encoding|leakage|store|selection]'
---

# Feature Engineering

## When to Use

- When designing ML features from raw data
- When setting up feature stores or shared transformation pipelines
- When auditing for data leakage in feature pipelines
- When selecting or pruning features for model training

## Principles

- **Verifiability:** Every feature must have a clear definition, derivation logic, and documented rationale. A feature without documentation is a liability.
- **Transparency:** Feature derivation pipelines must be reproducible and auditable. No hand-crafted features that exist only in a lost notebook.
- **Leakage prevention:** The single most important rule in feature engineering. No information from the future (target leakage) or test set (data leakage) may enter the training pipeline.
- **Simplicity first:** Start with simple features. Complex engineered features should be justified by measurable performance improvement.

## Techniques & Patterns

### Feature Types

| Type | Techniques | Examples |
|------|-----------|---------|
| **Numeric** | Scaling, binning, log/power transforms, polynomial features, interactions | `log(income)`, `age * tenure` |
| **Categorical** | One-hot, ordinal, target encoding, frequency encoding, hashing | `city_onehot`, `brand_target_enc` |
| **Text** | TF-IDF, word embeddings, sentence transformers, topic features | `review_sentiment`, `title_embedding` |
| **Temporal** | Lag features, rolling statistics, cyclical encoding, time since event | `sales_7d_avg`, `days_since_last_purchase` |
| **Geospatial** | Haversine distance, clustering, reverse geocoding, grid features | `dist_to_city_center`, `geo_cluster` |
| **Aggregation** | Group-by statistics, window functions, entity-level summaries | `user_avg_order_value`, `product_return_rate` |

### Encoding Strategies

| Method | When to Use | Pitfall |
|--------|------------|---------|
| **One-hot** | Low cardinality (< 20) | Curse of dimensionality with high cardinality |
| **Target encoding** | High cardinality categoricals | Overfitting -- must use cross-validated encoding |
| **Ordinal encoding** | Natural ordering exists (size: S/M/L/XL) | Implies magnitude if ordering doesn't exist |
| **Frequency encoding** | Cardinality reduction | Loses identity -- different categories with same frequency collapse |
| **Hash encoding** | Very high cardinality (> 10k) | Collisions. Irreversible. |
| **Embedding** | Learned representation (deep learning) | Requires sufficient training data |

### Leakage Prevention Checklist

1. **Temporal split before feature engineering.** Define train/test boundaries by time, then engineer features.
2. **Fit on train only.** Scalers, encoders, imputers -- fit on training data, transform test data.
3. **No future data in lag features.** Lag features at time T must only use data from T-1 and earlier.
4. **No aggregation across split.** Group-by features must respect the train/test boundary.
5. **No target in features.** Remove any column that is a proxy for the target variable.
6. **Cross-validated target encoding.** Never compute target encoding on the full training set -- use k-fold.

### Feature Store Architecture

```
Raw Data --> Feature Pipeline --> Feature Store --> Training / Serving
                |                      |
                v                      v
          Transformation         Online Store (low-latency, Redis/DynamoDB)
          (Spark/Flink/dbt)      Offline Store (batch, S3/BigQuery)
                                      |
                                      v
                              Feature Registry (metadata, lineage, schemas)
```

| Tool | Type | Strengths |
|------|------|-----------|
| **Feast** | Open-source | Simple, works with existing infra, Python SDK |
| **Tecton** | Managed SaaS | Production-grade, real-time features, monitoring |
| **Vertex AI Feature Store** | GCP managed | Integrated with Vertex AI pipelines |
| **SageMaker Feature Store** | AWS managed | Integrated with SageMaker |
| **Hopsworks** | Open-source + managed | Feature versioning, lineage tracking |

### Feature Selection Methods

| Method | Type | When to Use |
|--------|------|----------|
| **Correlation filter** | Filter | Quick removal of redundant features |
| **Mutual information** | Filter | Non-linear relationships, mixed types |
| **Recursive Feature Elimination (RFE)** | Wrapper | Small feature sets, model-dependent |
| **L1 regularization (Lasso)** | Embedded | Automatic selection during training |
| **SHAP / permutation importance** | Post-hoc | Understanding trained model feature usage |
| **Boruta** | Wrapper | Robust, handles multicollinearity |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **No data leakage** | Zero violations | Validated via temporal split analysis and pipeline review |
| **Feature documentation** | 100% of features | Name, definition, derivation logic, data source |
| **Feature importance verified** | Top features reviewed | SHAP or permutation importance run post-training |
| **Null handling documented** | Every feature | Imputation strategy recorded |
| **Feature freshness** | Defined per feature | How often features are recomputed; staleness threshold set |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Feature factory** | Generating hundreds of features without selection. Noise overwhelms signal. | Start simple. Add features based on importance analysis. |
| **Leaky features** | Using future data or target proxies. Model looks great in training, fails in production. | Strict temporal splitting. Leakage audit before training. |
| **Notebook-only features** | Features engineered in a notebook but not in the production pipeline. Training/serving skew. | Feature store or shared transformation pipeline. |
| **Unnamed features** | `feature_42`, `col_x`. No one knows what it is. | Descriptive naming convention. Documentation mandatory. |
| **Ignoring feature drift** | Features that were predictive 6 months ago may not be predictive today. | Monitor feature distributions in production. Alert on drift. |

## References

- Feast: https://feast.dev/
- Feature Engineering and Selection (Kuhn & Johnson): https://bookdown.org/max/FES/
- scikit-learn feature selection: https://scikit-learn.org/stable/modules/feature_selection.html
- SHAP: https://github.com/shap/shap
