---
name: exploratory-data-analysis
description: Systematically investigate datasets to discover patterns, spot anomalies, test hypotheses, and check assumptions — structured EDA workflow, profiling tools, visualization best practices, and statistical tests.
argument-hint: '[phase: profiling|univariate|bivariate|temporal|quality] [tool: ydata-profiling|sweetviz|dtale]'
---

# Exploratory Data Analysis

## When to Use

- When starting a new data science project or onboarding a new dataset
- When validating data assumptions before model development
- When investigating data quality issues, anomalies, or distribution shifts
- When choosing appropriate feature engineering or modeling strategies

## Principles

- **Verifiability:** Every claim about the data must be backed by evidence -- a statistic, a visualization, or a test. No "I think the data looks normal" without a Shapiro-Wilk test or Q-Q plot.
- **Transparency:** EDA findings must be documented in a reproducible artifact (notebook, report) so others can verify the conclusions.
- **Hypothesis-first:** Start with questions, not with code. Define what you want to learn before writing the first cell.
- **Skepticism:** Treat every finding as suspicious until confirmed. Correlation is not causation. Outliers may be data errors or genuine signals.

## Techniques & Patterns

### Structured EDA Workflow

```
1. Data Profiling    --> shape, dtypes, nulls, cardinality, memory
2. Univariate        --> distributions, central tendency, spread, outliers
3. Bivariate         --> correlations, cross-tabs, scatter matrices
4. Multivariate      --> PCA, clustering, interaction effects
5. Temporal          --> trends, seasonality, stationarity (if time-series)
6. Data Quality      --> duplicates, inconsistencies, impossible values
7. Hypothesis Tests  --> statistical tests for key assumptions
8. Summary Report    --> key findings, data issues, modeling implications
```

### Statistical Profiling Tools

| Tool | Use Case | Notes |
|------|----------|-------|
| `ydata-profiling` (pandas-profiling) | Automated profiling report | One-line HTML report; good for initial scan |
| `sweetviz` | Comparison reports | Compare train/test, before/after |
| `D-Tale` | Interactive exploration | Web-based, good for non-technical stakeholders |
| `lux` | Smart visualization | Auto-suggests relevant charts |

### Visualization Best Practices

- **Distribution:** Histogram + KDE for continuous, bar chart for categorical. Always show sample size.
- **Correlation:** Heatmap for overview, scatter for drill-down. Use Spearman for non-linear relationships.
- **Outliers:** Box plots, IQR method, z-scores. Always investigate before removing.
- **Missing data:** Heatmap of missingness patterns (missingno library). Distinguish MCAR/MAR/MNAR before imputation.
- **Time series:** Line plot with rolling statistics. Decompose into trend/seasonal/residual.

### Notebook Discipline

- **One question per section.** Each notebook section should answer exactly one question.
- **Markdown-first.** Write the question and expected answer before writing code.
- **Parameterize.** Use variables for thresholds (e.g., `OUTLIER_ZSCORE = 3`), not magic numbers.
- **Clean outputs.** Run "Restart & Run All" before committing. Every cell must execute cleanly.
- **Pin environment.** Include a `requirements.txt` or `environment.yml` in the same directory.
- **Version control.** Use `nbstripout` or `jupytext` to keep diffs clean. Never commit raw notebook outputs to git.

### Common Statistical Tests

| Question | Test | Assumptions |
|----------|------|-------------|
| Is this normally distributed? | Shapiro-Wilk, Anderson-Darling | n < 5000 for Shapiro |
| Are these two groups different? | t-test (parametric), Mann-Whitney U (non-parametric) | Independence, equal variance (t-test) |
| Are proportions different? | Chi-squared, Fisher's exact | Expected counts >= 5 (chi-squared) |
| Are these correlated? | Pearson (linear), Spearman (monotonic), Kendall (ordinal) | Linearity (Pearson) |
| Is this time series stationary? | ADF test, KPSS test | Sufficient sample size |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Data profiling report exists** | Yes, for every new dataset | Automated via ydata-profiling or equivalent |
| **Missing data documented** | 100% of columns assessed | Missingness mechanism (MCAR/MAR/MNAR) identified for columns > 5% missing |
| **Outlier analysis complete** | All numeric columns | Method and threshold documented |
| **Target variable analyzed** | Distribution, class balance | Imbalance ratio documented if classification |
| **Key findings documented** | Markdown summary | Actionable findings with evidence |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Plot-and-pray** | Generating dozens of plots without hypotheses. No insight, just noise. | Write your question first, then choose the visualization that answers it. |
| **Premature modeling** | Jumping to model training without understanding the data. Garbage in, garbage out. | Complete EDA checklist before any `model.fit()`. |
| **Ignoring missingness** | Dropping NaN rows without analyzing the pattern. May introduce bias. | Profile missingness mechanism. Use appropriate imputation. |
| **Outlier deletion by reflex** | Removing outliers without investigating. May discard genuine signals. | Investigate each outlier. Document decision. Keep a "with/without outliers" comparison. |
| **Snooping on test data** | Including test set in EDA statistics. Leaks information. | Split train/test BEFORE EDA. Run EDA only on training set. |
| **Chart defaults** | Using default matplotlib colors, no labels, no titles. Unreadable. | Set a style (seaborn, plotly), add titles, axis labels, legends, and annotations. |

## References

- Tukey, J. W. (1977). Exploratory Data Analysis.
- ydata-profiling: https://github.com/ydataai/ydata-profiling
- missingno: https://github.com/ResidentMario/missingno
- nbstripout: https://github.com/kynan/nbstripout
- jupytext: https://github.com/mwouts/jupytext
