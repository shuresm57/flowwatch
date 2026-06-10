by Valdemar Støvring Storgaard & Malthe Yde Tiufkær

# Flowwatch

Network intrusion detection API powered by XGBoost. Classifies network traffic flows as benign or malicious using a trained model from the CICIDS2017 dataset. The model is exported to ONNX and integrated into a Node.js API for real-time predictions.

**Exam project for ML elective** — covers the full MLOps lifecycle: data ingestion, preprocessing, model training with hyperparameter optimisation, versioned artifact storage on HuggingFace Hub, and a production-ready inference API.

## MLOps Pipeline

```
Raw CICIDS2017 CSVs
       │
       ▼
preprocess.ipynb   ─── cleans & merges 8 source files → cleaned.csv
       │                uploaded to HuggingFace dataset repo (valthe/flowwatch)
       ▼
xgboost_ids.ipynb  ─── Optuna HPO → trains XGBoost → exports flowwatch.onnx + metadata.json
       │                uploaded to HuggingFace model repo  (valthe/flowwatch)
       ▼
fetch-model.js     ─── pulls artifacts on first API start (cached locally in model/)
       │
       ▼
Node.js API        ─── serves real-time inference via /analyze and /analyze/csv
       │
       ▼
demo.sh            ─── pulls cleaned.csv, samples random flows, validates predictions
```

**Artifact versioning** is handled by HuggingFace Hub (git-LFS backed). The API and demo are pointed at specific repos and revisions via environment variables, so rolling back to a previous model is a one-line env-var change.

## Quick Start

Copy `.env.example` to `.env` and fill in your HuggingFace token, then:

```bash
cd src && npm install && npm start
```

On first start the API automatically downloads the trained model
(`flowwatch.onnx` + `metadata.json`) from the HuggingFace model repo into `model/`
— no manual copying needed. Subsequent starts reuse the cached files.

Server runs on `http://localhost:3000`. Run the demo (from repo root):
```bash
./demo.sh
```

### Configuration

Set these in `.env` (gitignored) or export them in your shell:

| Variable | Used by | Default | Purpose |
|----------|---------|-----------------------|---------|
| `HF_TOKEN` | both | _(required for private repos)_ | HuggingFace read token |
| `HF_MODEL_REPO` | API | `valthe/flowwatch` | HuggingFace **model** repo (`flowwatch.onnx` + `metadata.json`) |
| `HF_MODEL_REVISION` | API | `main` | Model repo branch/tag |
| `HF_DATASET_REPO` | `demo.sh` | `valthe/flowwatch` | HuggingFace **dataset** repo (`cleaned.csv`) |
| `HF_REVISION` | `demo.sh` | `main` | Dataset repo branch/tag |

Fetch the model without starting the server:
```bash
cd src && npm run fetch-model
```

## Project Structure

```
├── .env                 # Local secrets (gitignored — copy from .env.example)
├── demo.sh              # End-to-end validation script
├── data/                # Downloaded cleaned.csv (gitignored)
├── model/               # Model artifacts fetched from HuggingFace (gitignored)
├── src/                 # Node.js/Express API
│   ├── index.js         # API server & routes
│   ├── model.js         # ONNX inference engine
│   ├── fetch-model.js   # HuggingFace model downloader
│   └── parse.js         # CSV parser
└── training/            # Jupyter notebooks
    ├── preprocess.ipynb      # Data cleaning (8 CSVs → cleaned.csv)
    ├── xgboost_ids.ipynb     # Model training + Optuna HPO + ONNX export
    └── dnn_comparison.ipynb  # DNN vs XGBoost comparison
```

## Model

Trained on [CICIDS2017](https://www.kaggle.com/code/ericanacletoribeiro/cicids2017-comprehensive-data-processing-for-ml) (~2.5 M labelled network flows, 78 features).

| Metric | Value |
|--------|-------|
| Algorithm | XGBoost (Optuna-tuned) |
| Accuracy | 99.79% |
| ROC AUC | 0.999 |
| Macro F1 | 0.8591 |
| Classes | 15 (BENIGN + 14 attack types) |
| Input features | 78 numerical flow features |
| Export format | ONNX (no Python at inference time) |

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness check |
| `GET` | `/features` | Expected feature names and label map |
| `POST` | `/analyze` | Classify a single flow (JSON `{ "features": [...] }`) |
| `POST` | `/analyze/csv` | Classify many flows (`Content-Type: text/csv`) |

## Demo

**Terminal 1:** Start the API
```bash
cd src && npm install && npm start
```

**Terminal 2:** Run the demo (from repo root)
```bash
./demo.sh [SAMPLES]   # default: 30
```

The demo downloads `cleaned.csv` from the HuggingFace dataset repo (cached in
`data/`), samples random flows, posts them to `/analyze/csv`, and compares each
predicted `label_id` against the ground-truth integer `Label` column — printing
PASS/FAIL per flow and an overall accuracy summary.
