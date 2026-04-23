# Flowwatch

> **Work in Progress** — This project is under active development and will be updated sporadically.

This is a network intrusion detection API that classifies network traffic flows, via a trained XGBoost model from the CICIDS2017 dataset.

The model is saved as an .onnx file, which is then loaded into the Node.js app which acts looks at the incoming traffic and determines whether it could be labeled as intrusive or not, based on the trained model.

This project is for the Machine Learning elective exam on EK - although it is centered
around Machine Learning, I also take inspiration from my other electives: **Node.js and DevOps.**

## Overview

```bash
├── README.md
├── data
│   ├── Friday-WorkingHours-Afternoon-DDos.pcap_ISCX.csv
│   ├── Friday-WorkingHours-Afternoon-PortScan.pcap_ISCX.csv
│   ├── Friday-WorkingHours-Morning.pcap_ISCX.csv
│   ├── Monday-WorkingHours.pcap_ISCX.csv
│   ├── Thursday-WorkingHours-Afternoon-Infilteration.pcap_ISCX.csv
│   ├── Thursday-WorkingHours-Morning-WebAttacks.pcap_ISCX.csv
│   ├── Tuesday-WorkingHours.pcap_ISCX.csv
│   ├── Wednesday-workingHours.pcap_ISCX.csv
│   └── cleaned.csv
├── src
│   ├── index.js
│   ├── model.js
│   ├── package-lock.json
│   ├── package.json
│   └── parse.js
└── training
    ├── preprocess.ipynb
    └── xgboost_ids.ipynb
```


## Model

The data the model has been trained on was downloaded from [Kaggle.](https://www.kaggle.com/code/ericanacletoribeiro/cicids2017-comprehensive-data-processing-for-ml)

- Algorithm: XGBoost, Optuna-tuned
- Accuracy: 99.79%
- ROC AUC: 0.999
- Classes: BENIGN, Bot, DDoS, DoS GoldenEye, DoS Hulk, DoS Slowhttptest, DoS slowloris, FTP-Patator, Heartbleed, Infiltration, PortScan,
  SSH-Patator, Web Attack (Brute Force, SQL Injection, XSS)

## Endpoints

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

The showcase only takes inputs from the CSV at this point, for testing purposes.

This showcases the model detecting real attacks:
- **Benign traffic** → predicts BENIGN
- **DDoS attacks** → predicts DDoS
- **PortScan attacks** → predicts PortScan
- **Web attacks** → predicts Web Attack
