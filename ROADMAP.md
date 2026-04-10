# Flowwatch — Improvement Roadmap

## Current State

A minimal Node.js/Express API that serves a trained XGBoost model (exported to ONNX) for real-time network intrusion detection. It classifies network flows into 15 categories (benign + 14 attack types) using 78 numerical features.

**Endpoints:**
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Liveness check |
| GET | `/features` | List expected feature names and label classes |
| POST | `/analyze` | Classify a single flow (JSON) |
| POST | `/analyze/csv` | Batch-classify flows from CSV data |

---

## Phase 1 — Hardening

### 1. Input validation

Add a check before running inference so bad requests get a clear 400 error (`src/index.js`):

```js
function validateFeatures(features) {
  if (!Array.isArray(features)) return 'features must be an array';
  if (features.length !== 78) return `expected 78 features, got ${features.length}`;
  if (features.some(f => typeof f !== 'number' || !isFinite(f)))
    return 'all features must be finite numbers';
  return null;
}
```

### 2. Rate limiting

```bash
npm install express-rate-limit
```

```js
import rateLimit from 'express-rate-limit';
app.use('/analyze', rateLimit({ windowMs: 60_000, max: 120 }));
```

---

## Phase 2 — Logging to file

Write a plain human-readable line to a log file for every request. No extra packages needed — just the built-in `fs` module.

### What a log line looks like

```
2024-06-01 14:23:11 | INFO  | POST /analyze     | 200 | 3ms  | DDoS (99.87%)
2024-06-01 14:23:12 | INFO  | GET  /health      | 200 | 0ms  |
2024-06-01 14:23:15 | WARN  | POST /analyze     | 400 | 1ms  | expected 78 features, got 5
2024-06-01 08:00:00 | INFO  | server started on port 3000
```

### Logger (`src/logger.js`)

```js
import { appendFileSync } from 'node:fs';

const LOG_PATH = process.env.LOG_PATH ?? 'flowwatch.log';

function log(level, message) {
  const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);
  const line = `${ts} | ${level.padEnd(5)} | ${message}\n`;
  process.stdout.write(line);
  appendFileSync(LOG_PATH, line);
}

export const logger = {
  info:  (msg) => log('INFO',  msg),
  warn:  (msg) => log('WARN',  msg),
  error: (msg) => log('ERROR', msg),
};
```

### Using the logger in `index.js`

```js
import { logger } from './logger.js';

// on startup
logger.info(`server started on port ${port}`);

// in /analyze handler
const start = Date.now();
// ... run inference ...
const ms = Date.now() - start;
logger.info(`POST /analyze     | 200 | ${ms}ms | ${label} (${(confidence * 100).toFixed(2)}%)`);

// on bad input
logger.warn(`POST /analyze     | 400 | ${ms}ms | ${reason}`);
```

### Querying logs on the server

```bash
# Watch live
tail -f flowwatch.log

# All attack detections
grep -v BENIGN flowwatch.log

# All warnings and errors
grep -E "WARN|ERROR" flowwatch.log

# Requests from today
grep "$(date '+%Y-%m-%d')" flowwatch.log
```

---

## Linux Deployment — systemctl

### Prerequisites

1. Linux server with Node.js 20+ (`node --version`)
2. Project cloned to `/opt/flowwatch`
3. Model files at `/opt/flowwatch/model/`

### Step 1 — Create a system user

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin flowwatch
sudo chown -R flowwatch:flowwatch /opt/flowwatch
```

### Step 2 — Install dependencies

```bash
cd /opt/flowwatch/src && sudo -u flowwatch npm ci --omit=dev
```

### Step 3 — Environment file

```bash
sudo nano /etc/flowwatch.env
```

```ini
PORT=3000
NODE_ENV=production
LOG_PATH=/var/log/flowwatch/flowwatch.log
```

```bash
sudo chmod 640 /etc/flowwatch.env
sudo chown root:flowwatch /etc/flowwatch.env
sudo mkdir -p /var/log/flowwatch
sudo chown flowwatch:flowwatch /var/log/flowwatch
```

### Step 4 — systemd unit file

```bash
sudo nano /etc/systemd/system/flowwatch.service
```

```ini
[Unit]
Description=Flowwatch network intrusion detection API
After=network.target

[Service]
Type=simple
User=flowwatch
WorkingDirectory=/opt/flowwatch/src
EnvironmentFile=/etc/flowwatch.env
ExecStart=/usr/bin/node index.js
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=flowwatch

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/flowwatch/src
ReadWritePaths=/var/log/flowwatch

[Install]
WantedBy=multi-user.target
```

### Step 5 — Enable and start

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now flowwatch
sudo systemctl status flowwatch
```

### Step 6 — View logs

```bash
sudo journalctl -u flowwatch -f        # live journal output
tail -f /var/log/flowwatch/flowwatch.log   # plain log file
```

### Optional: Nginx reverse proxy

```nginx
server {
    listen 80;
    server_name your-server-ip-or-domain;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/flowwatch /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

---

## CI/CD — GitHub Actions

`.github/workflows/ci-cd.yml`

```yaml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: src/package-lock.json
      - run: npm ci
        working-directory: src
      - run: node --test test.js
        working-directory: src

  deploy:
    runs-on: ubuntu-latest
    needs: test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    steps:
      - name: Deploy to server
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SERVER_SSH_KEY }}
          script: |
            cd /opt/flowwatch
            git pull origin main
            cd src && npm ci --omit=dev
            sudo systemctl restart flowwatch
```

**Required GitHub secrets:**

| Secret | Value |
|--------|-------|
| `SERVER_HOST` | Server IP or hostname |
| `SERVER_USER` | SSH username |
| `SERVER_SSH_KEY` | Private SSH key |

Passwordless sudo for restart (`/etc/sudoers.d/flowwatch-deploy`):
```
deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart flowwatch
```

---

## DNN comparison (training)

Train a simple Keras DNN on the same cleaned dataset and compare it against XGBoost. Even if XGBoost wins, this demonstrates you understand both approaches and can answer exam questions about neural networks directly from your own project.

Add a new notebook: `training/dnn_comparison.ipynb`

### Model

```python
from tensorflow import keras

model = keras.Sequential([
    keras.layers.Dense(128, activation='relu', input_shape=(78,)),
    keras.layers.Dense(64, activation='relu'),
    keras.layers.Dense(n_classes, activation='softmax')
])

model.compile(
    optimizer=keras.optimizers.Adam(learning_rate=0.001),
    loss='sparse_categorical_crossentropy',
    metrics=['accuracy']
)

history = model.fit(
    X_train, y_train,
    epochs=20,
    batch_size=1024,
    validation_split=0.1,
    class_weight=class_weights  # same weights used for XGBoost
)
```

### What to record and compare

| Metric | XGBoost | DNN |
|--------|---------|-----|
| Accuracy | 99.79% | ? |
| Macro F1 | 0.8591 | ? |
| ROC AUC | 0.999 | ? |
| Training time | ? min | ? min |
| Inference time | ? ms/req | ? ms/req |

### Why XGBoost wins on tabular data (the answer you need ready)

- Features are already engineered — no raw signal for convolutions or embeddings to extract
- XGBoost handles class imbalance better via sample weights per tree split
- Fewer hyperparameters to tune, faster training on CPU
- DNNs need more data and careful regularization to match gradient boosting on structured tabular tasks

---

## Priority order

| Priority | Item | Effort |
|----------|------|--------|
| 1 | Input validation | 30 min |
| 2 | Logging to file | 30 min |
| 3 | DNN comparison notebook | 2 hours |
| 4 | systemctl deployment | 1 hour |
| 5 | Rate limiting | 15 min |
| 6 | CI/CD (GitHub Actions) | 1 hour |
