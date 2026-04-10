# Flowwatch — Improvement Roadmap

## Current State

A minimal Node.js/Express API that serves a trained XGBoost model (exported to ONNX) for real-time network intrusion detection. It classifies network flows into 15 categories (benign + 14 attack types) using 78 numerical features.

**Endpoints today:**
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Liveness check |
| GET | `/features` | List expected feature names and label classes |
| POST | `/analyze` | Classify a single flow (JSON) |
| POST | `/analyze/csv` | Batch-classify flows from CSV data |

**Goal:** Rewrite the API in Rust (Axum + `ort`) to produce a single self-contained binary with lower memory usage, no runtime dependency, and the same four endpoints. The trained ONNX model file is reused as-is — no retraining needed.

---

## Phase 1 — Rust rewrite

### Step 1 — Project setup

Create a new Rust project alongside the existing `src/` directory:

```
flowwatch/
├── src/          ← keep for reference during rewrite
├── server/       ← new Rust project
│   ├── Cargo.toml
│   └── src/
│       └── main.rs
├── model/
│   ├── flowwatch.onnx
│   └── metadata.json
└── training/
```

```bash
cargo new server
cd server
```

`server/Cargo.toml`:
```toml
[package]
name = "flowwatch"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.7"
tokio = { version = "1", features = ["full"] }
ort = { version = "2", features = ["load-dynamic"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
tracing-appender = "0.2"
tower-http = { version = "0.5", features = ["trace"] }
```

---

### Step 2 — Load the model and metadata at startup

```rust
// server/src/main.rs
use ort::{Environment, Session, SessionBuilder};
use serde::Deserialize;
use std::{fs, sync::Arc};

#[derive(Deserialize)]
struct Metadata {
    features: Vec<String>,
    labels: Vec<String>,
}

struct AppState {
    session: Session,
    metadata: Metadata,
}
```

Load both files once at startup and share via `Arc<AppState>`:

```rust
let metadata: Metadata = serde_json::from_str(
    &fs::read_to_string("../model/metadata.json").unwrap()
).unwrap();

let session = SessionBuilder::new(&Environment::builder().build().unwrap())
    .unwrap()
    .with_model_from_file("../model/flowwatch.onnx")
    .unwrap();

let state = Arc::new(AppState { session, metadata });
```

---

### Step 3 — Implement the four endpoints

**`GET /health`**
```rust
async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "status": "ok" }))
}
```

**`GET /features`**
```rust
async fn features(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    Json(serde_json::json!({
        "features": state.metadata.features,
        "labels": state.metadata.labels,
    }))
}
```

**`POST /analyze`**
```rust
#[derive(Deserialize)]
struct AnalyzeRequest {
    features: Vec<f32>,
}

async fn analyze(
    State(state): State<Arc<AppState>>,
    Json(body): Json<AnalyzeRequest>,
) -> Result<impl IntoResponse, (StatusCode, String)> {
    if body.features.len() != 78 {
        return Err((
            StatusCode::BAD_REQUEST,
            format!("expected 78 features, got {}", body.features.len()),
        ));
    }
    // run inference, decode probabilities, return JSON
}
```

Input validation happens automatically — Axum returns 422 if the JSON doesn't match the struct, and the length check covers the 78-feature requirement.

**`POST /analyze/csv`**

Parse the CSV body line by line using the `csv` crate, run each row through the same inference path as `/analyze`, and return a JSON array of results.

```toml
csv = "1"
```

---

### Step 4 — Run inference with `ort`

```rust
use ndarray::Array2;
use ort::inputs;

let input = Array2::from_shape_vec((1, 78), body.features).unwrap();
let outputs = state.session.run(inputs!["input" => input.view()].unwrap()).unwrap();
let probabilities: Vec<f32> = outputs["probabilities"]
    .try_extract_tensor::<f32>()
    .unwrap()
    .iter()
    .cloned()
    .collect();

let label_id = probabilities
    .iter()
    .enumerate()
    .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
    .map(|(i, _)| i)
    .unwrap();

let label = &state.metadata.labels[label_id];
let confidence = probabilities[label_id];
```

Add `ndarray` to `Cargo.toml`:
```toml
ndarray = "0.15"
```

---

### Step 5 — Wire up the router

```rust
#[tokio::main]
async fn main() {
    // logging setup (see Phase 2)

    let state = Arc::new(/* load model and metadata */);

    let app = Router::new()
        .route("/health", get(health))
        .route("/features", get(features))
        .route("/analyze", post(analyze))
        .route("/analyze/csv", post(analyze_csv))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port = std::env::var("PORT").unwrap_or("3000".into());
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{port}"))
        .await
        .unwrap();

    tracing::info!("listening on {}", listener.local_addr().unwrap());
    axum::serve(listener, app).await.unwrap();
}
```

---

### Step 6 — Build for release

```bash
cd server
cargo build --release
# binary at: server/target/release/flowwatch
```

The output is a single statically-linked binary (~5–15 MB). No Node.js, no npm, nothing else needed on the server.

---

## Phase 2 — Structured logging to file

Use `tracing` + `tracing-appender` to write timestamped JSON logs to a rotating file. Every request and every prediction gets a log entry.

### Setup in `main.rs`

```rust
use tracing_appender::rolling;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

fn init_logging() {
    // Rotate log files daily: logs/flowwatch.2024-06-01.log
    let file_appender = rolling::daily("/var/log/flowwatch", "flowwatch.log");
    let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);

    tracing_subscriber::registry()
        .with(EnvFilter::from_default_env().add_directive("info".parse().unwrap()))
        .with(
            fmt::layer()
                .json()                  // structured JSON lines
                .with_writer(non_blocking)
        )
        .with(
            fmt::layer()                 // human-readable to stdout/journald
                .with_writer(std::io::stdout)
        )
        .init();
}
```

Call `init_logging()` as the first line of `main()`. The `_guard` must be kept alive for the duration of the program — assign it to a variable in `main`, never drop it early.

### What gets logged

| Event | Fields logged |
|-------|--------------|
| Server start | port, feature count, label count |
| Each request | method, path, status code, latency (from `TraceLayer`) |
| Each prediction | timestamp, client IP, label, confidence, label_id |
| Bad request | client IP, error reason |
| Startup error | error message |

**Instrument the analyze handler:**
```rust
tracing::info!(
    label = %label,
    confidence = confidence,
    label_id = label_id,
    "prediction"
);
```

### Log file location and permissions

```bash
sudo mkdir -p /var/log/flowwatch
sudo chown flowwatch:flowwatch /var/log/flowwatch
```

Add `ReadWritePaths=/var/log/flowwatch` to the systemd unit file (see deployment section).

### What a log line looks like

```json
{"timestamp":"2024-06-01T14:23:11.042Z","level":"INFO","fields":{"label":"DDoS","confidence":0.9987,"label_id":2},"target":"flowwatch","message":"prediction"}
{"timestamp":"2024-06-01T14:23:11.001Z","level":"INFO","fields":{"method":"POST","path":"/analyze","status":200,"latency_ms":3},"target":"flowwatch","message":"request"}
```

### Querying logs on the server

Because each line is valid JSON, you can filter with `jq`:

```bash
# All DDoS predictions today
cat /var/log/flowwatch/flowwatch.log | jq 'select(.fields.label == "DDoS")'

# All non-BENIGN predictions
cat /var/log/flowwatch/flowwatch.log | jq 'select(.fields.label != null and .fields.label != "BENIGN")'

# Request count by status code
cat /var/log/flowwatch/flowwatch.log | jq -r '.fields.status // empty' | sort | uniq -c

# Slowest requests (latency > 50ms)
cat /var/log/flowwatch/flowwatch.log | jq 'select(.fields.latency_ms > 50)'
```

journald also captures stdout, so `journalctl -u flowwatch` still works alongside the file logs.

---

## Phase 3 — Rate limiting

Axum has no built-in rate limiter, but `tower-http` and `tower` provide a `RateLimit` layer:

```toml
tower = { version = "0.4", features = ["limit"] }
```

```rust
use tower::limit::RateLimitLayer;
use std::time::Duration;

let app = Router::new()
    // ...
    .layer(RateLimitLayer::new(120, Duration::from_secs(60))); // 120 req/min globally
```

For per-IP limiting, use the `governor` crate which is the standard Rust approach:

```toml
governor = "0.6"
tower_governor = "0.3"
```

---

## Phase 4 — Metrics endpoint

Add an in-memory counter using `std::sync::atomic`:

```rust
use std::sync::atomic::{AtomicU64, Ordering};

struct Metrics {
    total_requests: AtomicU64,
    predictions_by_label: std::sync::Mutex<std::collections::HashMap<String, u64>>,
}
```

Expose at `GET /metrics`:

```rust
async fn metrics(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let counts = state.metrics.predictions_by_label.lock().unwrap();
    Json(serde_json::json!({
        "total_requests": state.metrics.total_requests.load(Ordering::Relaxed),
        "predictions": *counts,
    }))
}
```

---

## Linux Deployment — systemctl

### Prerequisites

1. A Linux server (Ubuntu 22.04+ or Debian 12+)
2. The compiled binary copied to `/opt/flowwatch/flowwatch`
3. The model files at `/opt/flowwatch/model/`

No Node.js, no npm, no runtime required on the server.

### Step 1 — Create a dedicated system user

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin flowwatch
sudo mkdir -p /opt/flowwatch/model
sudo chown -R flowwatch:flowwatch /opt/flowwatch
sudo mkdir -p /var/log/flowwatch
sudo chown flowwatch:flowwatch /var/log/flowwatch
```

### Step 2 — Copy files to the server

```bash
scp server/target/release/flowwatch user@server:/opt/flowwatch/
scp model/flowwatch.onnx model/metadata.json user@server:/opt/flowwatch/model/
```

### Step 3 — Create an environment file

```bash
sudo nano /etc/flowwatch.env
```

```ini
PORT=3000
RUST_LOG=info
```

```bash
sudo chmod 640 /etc/flowwatch.env
sudo chown root:flowwatch /etc/flowwatch.env
```

### Step 4 — Create the systemd unit file

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
WorkingDirectory=/opt/flowwatch
EnvironmentFile=/etc/flowwatch.env
ExecStart=/opt/flowwatch/flowwatch
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=flowwatch

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/flowwatch
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
# Live journal output
sudo journalctl -u flowwatch -f

# Query the structured log file
cat /var/log/flowwatch/flowwatch.log | jq .
```

---

### Optional: Nginx reverse proxy

```nginx
# /etc/nginx/sites-available/flowwatch
server {
    listen 80;
    server_name your-server-ip-or-domain;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
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

Two jobs in sequence: build & test on every push, deploy to the server on merge to `main`.

`.github/workflows/ci-cd.yml`

```yaml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Rust toolchain
        uses: dtolnay/rust-toolchain@stable

      - name: Cache cargo
        uses: Swatinem/rust-cache@v2
        with:
          workspaces: server

      - name: Build release binary
        run: cargo build --release
        working-directory: server

      - name: Run tests
        run: cargo test
        working-directory: server

      - name: Upload binary artifact
        uses: actions/upload-artifact@v4
        with:
          name: flowwatch-binary
          path: server/target/release/flowwatch

  deploy:
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    steps:
      - name: Download binary
        uses: actions/download-artifact@v4
        with:
          name: flowwatch-binary

      - name: Copy binary to server
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SERVER_SSH_KEY }}
          source: flowwatch
          target: /opt/flowwatch/

      - name: Restart service
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SERVER_SSH_KEY }}
          script: |
            chmod +x /opt/flowwatch/flowwatch
            sudo systemctl restart flowwatch
            sudo systemctl is-active flowwatch
```

**Required GitHub secrets:**

| Secret | Value |
|--------|-------|
| `SERVER_HOST` | IP address or hostname of the Linux server |
| `SERVER_USER` | SSH user with write access to `/opt/flowwatch` |
| `SERVER_SSH_KEY` | Private SSH key whose public half is in `~/.ssh/authorized_keys` on the server |

Passwordless sudo for restart only (`/etc/sudoers.d/flowwatch-deploy`):
```
deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart flowwatch, /bin/systemctl is-active flowwatch
```

Note: the ONNX model is not re-uploaded on every deploy — only the binary changes. Update the model separately when you retrain.

---

## Priority order

| Priority | Item | Effort |
|----------|------|--------|
| 1 | Rust project setup + model loading | 2 hours |
| 2 | `/health` and `/features` endpoints | 30 min |
| 3 | `/analyze` endpoint + inference | 2 hours |
| 4 | `/analyze/csv` endpoint | 1 hour |
| 5 | Structured file logging (tracing-appender) | 1 hour |
| 6 | systemctl deployment | 1 hour |
| 7 | CI/CD (GitHub Actions) | 1 hour |
| 8 | Rate limiting | 30 min |
| 9 | Metrics endpoint | 1 hour |
