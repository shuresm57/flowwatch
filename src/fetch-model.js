import { existsSync, mkdirSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const envFile = join(dirname(fileURLToPath(import.meta.url)), '..', '.env');
if (existsSync(envFile)) process.loadEnvFile(envFile);

const __dirname = dirname(fileURLToPath(import.meta.url));
const MODEL_DIR = join(__dirname, '..', 'model');

// Repo and revision are configurable via env so the same code can point at a
// private/staging repo without edits. Defaults are placeholders — replace them
// (or set the env vars) with the real HuggingFace model repo.
const HF_MODEL_REPO = process.env.HF_MODEL_REPO;
const HF_MODEL_REVISION = process.env.HF_MODEL_REVISION;
const HF_TOKEN = process.env.HF_TOKEN; // optional; only needed for private repos

// Files the API needs at runtime (see model.js): the ONNX graph and the
// feature/label metadata that maps tensor outputs back to human-readable names.
const MODEL_FILES = ['flowwatch.onnx', 'metadata.json'];

async function downloadOne (path) {
  let res;
  try {
    res = await downloadFile({
      repo: { type: 'model', name: HF_MODEL_REPO },
      path,
      revision: HF_MODEL_REVISION,
      accessToken: HF_TOKEN
    });
  } catch (err) {
    throw new Error(
      `Failed to download "${path}" from ${HF_MODEL_REPO}@${HF_MODEL_REVISION}: ${err.message}. ` +
      'Set HF_MODEL_REPO (and HF_TOKEN for a private repo).'
    );
  }

  if (!res) {
    throw new Error(
      `"${path}" not found in ${HF_MODEL_REPO}@${HF_MODEL_REVISION}. ` +
      'Check HF_MODEL_REPO / HF_MODEL_REVISION (and HF_TOKEN for a private repo).'
    );
  }

  const buffer = Buffer.from(await res.arrayBuffer());
  writeFileSync(join(MODEL_DIR, path), buffer);
  console.log(`Downloaded ${path} (${buffer.length} bytes)`);
}

// Ensure flowwatch.onnx and metadata.json exist locally, downloading any that
// are missing from the HuggingFace model repo. Already-present files are kept
// (cache), so this is cheap to call on every startup.

import { downloadFile } from '@huggingface/hub';

export async function ensureModel () {
  const missing = MODEL_FILES.filter(
    (f) => !existsSync(join(MODEL_DIR, f))
  );

  if (missing.length === 0) return;

  mkdirSync(MODEL_DIR, { recursive: true });
  console.log(
    `Fetching model from ${HF_MODEL_REPO}@${HF_MODEL_REVISION}: ${missing.join(', ')}`
  );

  for (const path of missing) {
    await downloadOne(path);
  }
}

// Allow running as a standalone step: `npm run fetch-model`.
// Compare resolved paths (not URL strings) so paths with spaces still match.
if (fileURLToPath(import.meta.url) === process.argv[1]) {
  ensureModel()
    .then(() => console.log('Model ready.'))
    .catch((err) => {
      console.error(err.message);
      process.exit(1);
    });
}
