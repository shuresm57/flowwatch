const ort = require("onnxruntime-node");
const { readFileSync } = require("fs");
const { join } = require("path");

const MODEL_DIR = join(__dirname, "..", "model");

let session;
let metadata;

async function loadModel() {
  metadata = JSON.parse(
    readFileSync(join(MODEL_DIR, "metadata.json"), "utf-8")
  );
  session = await ort.InferenceSession.create(
    join(MODEL_DIR, "flowwatch.onnx")
  );
  console.log(
    `Model loaded: ${metadata.feature_names.length} features, ${Object.keys(metadata.label_names).length} classes`
  );
}

function getFeatureNames() {
  return metadata.feature_names;
}

function getLabelNames() {
  return metadata.label_names;
}

async function predict(features) {
  const input = new ort.Tensor(
    "float32",
    Float32Array.from(features),
    [1, features.length]
  );

  const results = await session.run({ input });

  const label = results["label"].data[0];
  const probs = Array.from(results["probabilities"].data);

  const confidence = probs[label];
  const labelName = metadata.label_names[String(label)] ?? `unknown_${label}`;

  return {
    label: labelName,
    label_id: label,
    confidence: Math.round(confidence * 10000) / 10000,
    probabilities: Object.fromEntries(
      probs.map((p, i) => [
        metadata.label_names[String(i)] ?? `class_${i}`,
        Math.round(p * 10000) / 10000,
      ])
    ),
  };
}

module.exports = { loadModel, predict, getFeatureNames, getLabelNames };
