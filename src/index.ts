import express from "express";
import { loadModel, predict, getFeatureNames, getLabelNames } from "./model";
import { parseCSVRows } from "./parse";

const app = express();
app.use(express.json());
app.use(express.text({ type: "text/csv" }));

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.get("/features", (_req, res) => {
  res.json({
    features: getFeatureNames(),
    labels: getLabelNames(),
  });
});

app.post("/analyze", async (req, res) => {
  const { features } = req.body;
  const expected = getFeatureNames().length;

  if (!Array.isArray(features) || features.length !== expected) {
    res.status(400).json({
      error: `Expected ${expected} features, got ${Array.isArray(features) ? features.length : "none"}`,
    });
    return;
  }

  const result = await predict(features);
  res.json(result);
});

app.post("/analyze/csv", async (req, res) => {
  if (typeof req.body !== "string" || !req.body.trim()) {
    res.status(400).json({ error: "Send CSV data with Content-Type: text/csv" });
    return;
  }

  const rows = parseCSVRows(req.body);
  const results = await Promise.all(rows.map((row) => predict(row)));
  res.json(results);
});

const PORT = process.env.PORT || 3000;

loadModel()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`FlowWatch listening on port ${PORT}`);
    });
  })
  .catch((err) => {
    console.error("Failed to load model:", err.message);
    process.exit(1);
  });
