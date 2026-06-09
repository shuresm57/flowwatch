import ort from 'onnxruntime-node';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MODEL_DIR = join(__dirname, '..', 'model');

let session;
let metadata;

export async function loadModel () {
  metadata = JSON.parse(
    readFileSync(join(MODEL_DIR, 'metadata.json'), 'utf-8')
  );
  session = await ort.InferenceSession.create(
    join(MODEL_DIR, 'flowwatch.onnx')
  );
  console.log(
    `Model loaded: ${metadata.feature_names.length} features, ${Object.keys(metadata.label_names).length} classes`
  );
}

export function getFeatureNames () {
  return metadata.feature_names;
}

export function getLabelNames () {
  return metadata.label_names;
}

export async function predict (features) {
  const input = new ort.Tensor(
    'float32',
    Float32Array.from(features),
    [1, features.length]
  );

  const results = await session.run({ input });

  // ONNX returns label as int64 (BigInt); convert to Number for JSON safety.
  const label = Number(results.label.data[0]);
  const probs = Array.from(results.probabilities.data);

  const labelName = metadata.label_names[String(label)] ?? `unknown_${label}`;

  return {
    label: labelName,
    label_id: label,
    confidence: Math.round(probs[label] * 10000) / 10000,
    probabilities: Object.fromEntries(
      probs.map((p, i) => [
        metadata.label_names[String(i)] ?? `class_${i}`,
        Math.round(p * 10000) / 10000
      ])
    )
  };
}
