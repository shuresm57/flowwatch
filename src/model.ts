import * as ort from "onnxruntime-node";
import { readFileSync } from "fs";
import { join } from "path";

const MODEL_DIR = join(__dirname, "..", "model");

interface Metadata {
  feature_names: string[];
  label_names: Record<string, string>;
}

let session: ort.InferenceSession;
let metadata: Metadata;

export async function loadModel() {
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

export function getFeatureNames(): string[] {
  return metadata.feature_names;
}

export function getLabelNames(): Record<string, string> {
  return metadata.label_names;
}

export async function predict(features: number[]) {
  const input = new ort.Tensor(
    "float32",
    Float32Array.from(features),
    [1, features.length]
  );

  const results = await session.run({ input });

  const label = (results["label"] as ort.Tensor).data[0] as number;
  const probabilities = results["probabilities"] as ort.Tensor;
  const probs = Array.from(probabilities.data as Float32Array);

  const confidence = probs[label];
  const labelName = metadata.label_names[String(label)] ?? `unknown_${label}`;

  return {
    label: labelName,
    label_id: label,
    confidence: Math.round(confidence * 10000) / 10000,
    probabilities: Object.fromEntries(
      probs.map((p, i) => [
        metadata.label_names[String(i)] ?? `class_${i}`,
        Math.round((p as number) * 10000) / 10000,
      ])
    ),
  };
}
