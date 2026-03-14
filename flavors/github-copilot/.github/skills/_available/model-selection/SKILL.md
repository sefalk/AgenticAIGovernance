---
name: model-selection
description: Choose the right model architecture and algorithm family — decision tree from problem type to model family, classical ML vs deep learning trade-offs, transfer learning strategies, and framework landscape.
argument-hint: '[data: tabular|image|text|timeseries|graph|audio] [focus: selection|comparison|transfer-learning|frameworks]'
---

# Model Selection & Architecture

## When to Use

- When starting a new ML project and choosing model architectures
- When evaluating trade-offs between model families (classical ML vs deep learning)
- When deciding on transfer learning or fine-tuning strategies
- When selecting ML frameworks for a project

## Principles

- **Efficiency:** Start simple. A logistic regression that solves the problem is better than a transformer that solves it 1% better at 100x the cost.
- **Verifiability:** Model choice must be justified and documented. "We used XGBoost because the data is tabular, moderate-sized, and we need feature importance" is a justification. "We used XGBoost" is not.
- **Transparency:** Model complexity must be proportional to the explainability requirements. High-stakes decisions may require interpretable models regardless of accuracy trade-offs.
- **Empirical validation:** No model is chosen by theory alone. Always benchmark candidates on your data.
- **Research before defaulting:** The ML field evolves rapidly. Survey current benchmarks (Papers With Code, arXiv, HuggingFace leaderboards) before committing to an architecture.

## Techniques & Patterns

### Decision Tree: Problem Type → Model Family

```
What is the task?
│
├─ Tabular data (structured, rows & columns)
│   ├─ Classification/Regression
│   │   ├─ < 1k samples: Logistic/Linear Regression, SVM, kNN
│   │   ├─ 1k-1M samples: Gradient Boosted Trees (XGBoost, LightGBM, CatBoost)
│   │   └─ > 1M samples: GBT still strong; consider neural nets (TabNet, FT-Transformer)
│   ├─ Anomaly detection: Isolation Forest, LOF, Autoencoder
│   └─ Clustering: k-Means, DBSCAN, HDBSCAN, Gaussian Mixture
│
├─ Image data
│   ├─ Classification: CNN (ResNet, EfficientNet), Vision Transformer (ViT)
│   ├─ Object detection: YOLO, Faster R-CNN, DETR
│   ├─ Segmentation: U-Net, Mask R-CNN, SAM
│   └─ Generation: Diffusion models (Stable Diffusion), GAN, VAE
│
├─ Text / NLP
│   ├─ Classification: Fine-tuned Transformer (BERT, RoBERTa), TF-IDF + classical ML
│   ├─ Generation: LLM (GPT, Llama), seq2seq (T5, BART)
│   ├─ NER / token classification: BERT + token head, CRF
│   ├─ Embeddings / similarity: Sentence Transformers, E5
│   └─ RAG: LLM + retrieval (vector DB + embeddings)
│
├─ Sequence / time series
│   ├─ Forecasting: ARIMA, Prophet, N-BEATS, Temporal Fusion Transformer
│   ├─ Classification: 1D-CNN, LSTM, Transformer
│   └─ Anomaly detection: LSTM Autoencoder, Spectral Residual
│
├─ Audio / speech
│   ├─ ASR (speech-to-text): Whisper, wav2vec 2.0
│   ├─ Classification: CNN on spectrograms, Audio Spectrogram Transformer
│   └─ TTS (text-to-speech): VITS, Bark
│
├─ Graph-structured data
│   ├─ Node classification: GCN, GAT, GraphSAGE
│   ├─ Link prediction: GNN, knowledge graph embeddings
│   └─ Graph classification: GIN, global pooling + GNN
│
├─ Reinforcement learning
│   ├─ Discrete actions: DQN, PPO
│   ├─ Continuous actions: SAC, TD3, PPO
│   └─ Multi-agent: MAPPO, QMIX
│
└─ Multimodal
    ├─ Vision + Language: CLIP, LLaVA, Flamingo
    └─ Any combination: Custom fusion architectures
```

### Model Family Comparison

| Family | Strengths | Weaknesses | Data Needs |
|--------|-----------|------------|-----------|
| **Linear models** (LogReg, LinReg, ElasticNet) | Fast, interpretable, regularizable, strong baseline | Cannot capture non-linear relationships | Small to medium |
| **Tree ensembles** (XGBoost, LightGBM, CatBoost, Random Forest) | Tabular SOTA, handles mixed types, robust to outliers, feature importance | Poor on images/text/sequence, can overfit small data | Medium |
| **SVM** | Strong on small datasets, kernel trick for non-linearity | Slow on large datasets, sensitive to scaling | Small |
| **kNN** | Simple, no training, non-parametric | Slow at inference, curse of dimensionality | Small |
| **CNN** | Spatial pattern recognition (images, spectrograms) | Needs labeled data, fixed input size (mostly) | Large |
| **RNN / LSTM / GRU** | Sequential data, variable length input | Vanishing gradient, slow training, largely superseded by Transformers | Medium-Large |
| **Transformer** | Long-range dependencies, parallelizable, SOTA for NLP/vision | Quadratic attention cost, needs lots of data or pre-training | Large (or fine-tuning) |
| **Autoencoder (AE / VAE)** | Unsupervised representation learning, anomaly detection, generation | Training instability (VAE/GAN), mode collapse (GAN) | Medium-Large |
| **GAN** | High-quality generation (images, tabular) | Hard to train, mode collapse, no density estimation | Large |
| **Diffusion models** | SOTA image generation, stable training | Slow inference (many denoising steps) | Large |
| **GNN** | Operates on graph structure, captures relational patterns | Limited scalability, over-smoothing with depth | Varies |
| **RL** | Sequential decision-making, optimization | Sample inefficient, reward engineering, hard to debug | Simulation/interaction |

### Classical ML vs. Deep Learning

| Factor | Favor Classical ML | Favor Deep Learning |
|--------|-------------------|-------------------|
| **Data type** | Tabular, structured | Images, text, audio, video |
| **Dataset size** | Small to medium (< 100k) | Large (> 100k, or pre-trained) |
| **Interpretability** | Required by regulation or stakeholders | Not a hard constraint |
| **Compute budget** | Limited (CPU-only) | GPU/TPU available |
| **Feature engineering** | Manual features are effective | Raw data has latent structure |
| **Time to first model** | Hours (sklearn pipeline) | Days (training + tuning) |
| **Deployment** | Lightweight (pickle, ONNX) | Heavier (model server, GPU inference) |

### Transfer Learning & Fine-Tuning

| Strategy | When to Use | Data Needed |
|----------|------------|-------------|
| **Feature extraction** (frozen backbone) | Very small dataset, similar domain to pre-training | 100-1k samples |
| **Fine-tuning** (unfreeze top layers) | Moderate dataset, related domain | 1k-10k samples |
| **Full fine-tuning** (all layers) | Large dataset, different domain | 10k+ samples |
| **LoRA / QLoRA** (parameter-efficient) | Fine-tuning LLMs with limited GPU memory | 1k-100k samples |
| **Prompt engineering** (no training) | LLM-solvable tasks, zero/few-shot | 0-10 examples |

### Model Selection Workflow

```
1. Define the problem type (classification, regression, ranking, generation, ...)
2. Characterize the data (modality, size, quality, label availability)
3. Identify constraints (latency, interpretability, compute, regulatory)
4. Research current SOTA for this task type:
   - Check Papers With Code leaderboards for the specific task
   - Survey recent papers (arXiv) and community benchmarks
   - Review HuggingFace model hub for pre-trained options
   - The decision tree in this skill is a baseline; the field may have advanced
5. Select 2-3 candidate families informed by steps 3-4
6. Establish a baseline (simplest model: majority class, mean, linear)
7. Train candidates with reasonable defaults (no tuning yet)
8. Compare on validation set using appropriate metrics (see Model Evaluation)
9. Tune the top 1-2 candidates (grid/random/Bayesian search)
10. Evaluate final model on held-out test set (ONCE)
11. Document selection rationale in an ADR, including research findings
```

### Framework Landscape

| Framework | Strengths | Best For |
|-----------|-----------|----------|
| **scikit-learn** | Consistent API, comprehensive classical ML | Tabular ML, prototyping |
| **XGBoost / LightGBM / CatBoost** | SOTA for tabular, fast, GPU support | Tabular classification/regression |
| **PyTorch** | Dynamic computation graph, research-friendly | Deep learning, custom architectures |
| **TensorFlow / Keras** | Production tooling, TF Serving, TFLite | Production DL, mobile/edge |
| **HuggingFace Transformers** | Pre-trained model hub, easy fine-tuning | NLP, vision, multimodal |
| **JAX / Flax** | Functional, JIT-compiled, TPU-native | Research, large-scale training |
| **Stable Baselines 3** | Clean RL implementations | Reinforcement learning |
| **PyTorch Geometric** | GNN library, many architectures | Graph ML |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Baseline established** | Before any complex model | Simplest reasonable model documented |
| **Selection rationale documented** | ADR or experiment log | Why this architecture, what alternatives were considered |
| **Multiple candidates compared** | >= 2 families benchmarked | Avoid single-model bias |
| **Constraints validated** | Latency, memory, interpretability checked | Model must meet deployment constraints, not just accuracy |
| **Overfitting checked** | Train/val gap < threshold | Large gap signals model too complex for the data |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Deep learning by default** | Using a Transformer for 500-row tabular data. Overfits, slow, uninterpretable. | Start with gradient boosted trees for tabular. Deep learning for unstructured data. |
| **Skipping the baseline** | Jumping to complex models without a simple reference point. No way to know if complexity is justified. | Always train a simple baseline first (linear model, majority class). |
| **Architecture tourism** | Trying every model architecture without a hypothesis. Random search masquerading as science. | Use the decision tree. Select candidates based on data modality and problem type. |
| **Ignoring constraints** | Training a 70B parameter model for a 50ms latency requirement. Beautiful accuracy, undeployable. | Define deployment constraints BEFORE model selection. |
| **Cargo cult fine-tuning** | Fine-tuning BERT on a task where TF-IDF + logistic regression achieves 95% accuracy. | Benchmark simple approaches first. Complex models must justify their cost. |
| **Ensemble for everything** | Stacking 5 models for a 0.1% accuracy gain. Maintenance nightmare. | Reserve ensembles for competitions. In production, prefer one model. |

## References

- scikit-learn algorithm cheat sheet: https://scikit-learn.org/stable/tutorial/machine_learning_map/
- Papers With Code SOTA: https://paperswithcode.com/sota
- Hugging Face Model Hub: https://huggingface.co/models
- XGBoost: https://xgboost.readthedocs.io/
- PyTorch: https://pytorch.org/
