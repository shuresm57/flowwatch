# Flowwatch

Network intrusion detection API powered by XGBoost. Classifies network traffic flows as benign or malicious using a trained model from the CICIDS2017 dataset. The model is exported to ONNX and integrated into a Node.js API for real-time predictions.

**Exam project for ML elective** — combines machine learning, Node.js, and DevOps integration.

## Quick Start

```bash
cd src && npm install && npm start
```

Server runs on `http://localhost:3000`. Run the demo:
```bash
./demo.sh
```

## Project Structure

```bash
├── docs/                # Documentation (exam notes, roadmap)
├── data/                # CICIDS2017 network traffic datasets
├── model/               # Trained XGBoost model (ONNX format)
├── src/                 # Node.js/Express API
│   ├── index.js         # API server
│   ├── model.js         # ONNX model loader
│   └── parse.js         # CSV parser
└── training/            # Jupyter notebooks
    ├── preprocess.ipynb # Data preprocessing
    └── xgboost_ids.ipynb # Model training with Optuna tuning
```

## Model

Trained on [CICIDS2017](https://www.kaggle.com/code/ericanacletoribeiro/cicids2017-comprehensive-data-processing-for-ml) network traffic dataset.

- **Algorithm:** XGBoost (Optuna-tuned hyperparameters)
- **Accuracy:** 99.79%
- **ROC AUC:** 0.999
- **Input:** 78 network flow features
- **Output:** 15 classifications (BENIGN, Bot, DDoS, DoS variants, FTP-Patator, Heartbleed, Infiltration, PortScan, SSH-Patator, Web Attacks)

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check |
| `GET` | `/features` | List expected features and label names |
| `POST` | `/analyze` | Classify a single network flow (JSON body with `features` array) |
| `POST` | `/analyze/csv` | Classify multiple flows from CSV (`Content-Type: text/csv`) |

## Demo

**Terminal 1:** Start the API
```bash
cd src && npm install && npm start
```

**Terminal 2:** Run the demo (from repo root)
```bash
./demo.sh
```

The demo tests the model on real network traffic datasets:
- **Benign traffic** → predicts BENIGN
- **DDoS attacks** → predicts DDoS
- **PortScan attacks** → predicts PortScan
- **Web attacks** → predicts Web Attack
