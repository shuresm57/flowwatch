import { existsSync, mkdirSync, writeFileSync, readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { downloadFile, fileDownloadInfo } from '@huggingface/hub';

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

// We treat the ONNX file's ETag (its content hash on the Hub) as the model's
// "version". It's stored next to the cached model; when the remote ETag differs
// we know a new model was pushed and re-download - so a plain restart picks up a
// new model without clearing the volume. Works whether you push to `main` or use
// an explicit tag/commit.
const SIGNATURE_FILE = 'flowwatch.onnx';
const MARKER = join(MODEL_DIR, '.model-etag');

async function remoteEtag () {
  const info = await fileDownloadInfo({
    repo: { type: 'model', name: HF_MODEL_REPO },
    path: SIGNATURE_FILE,
    revision: HF_MODEL_REVISION,
    accessToken: HF_TOKEN
  });
  return info?.etag ?? null;
}

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

// Ensure the local model is present AND up to date. Downloads only when the
// files are missing or the remote ONNX ETag has changed since we last fetched,
// so this is cheap to call on every startup and auto-picks up a retrained model.
export async function ensureModel () {
  const filesPresent = MODEL_FILES.every((f) => existsSync(join(MODEL_DIR, f)));
  const cachedEtag = existsSync(MARKER) ? readFileSync(MARKER, 'utf8').trim() : null;

  let latestEtag;
  try {
    latestEtag = await remoteEtag();
  } catch (err) {
    // Can't reach the Hub: keep serving the cached model rather than failing.
    if (filesPresent) {
      console.warn(`Could not check for a new model (${err.message}); using cached model.`);
      return;
    }
    throw new Error(`No local model and could not reach HuggingFace: ${err.message}`);
  }

  if (filesPresent && cachedEtag && latestEtag && cachedEtag === latestEtag) {
    return; // up to date
  }

  mkdirSync(MODEL_DIR, { recursive: true });
  console.log(
    `Fetching model from ${HF_MODEL_REPO}@${HF_MODEL_REVISION} ` +
    `(cached=${cachedEtag ?? 'none'}, latest=${latestEtag ?? 'unknown'})`
  );

  for (const path of MODEL_FILES) {
    await downloadOne(path);
  }
  if (latestEtag) writeFileSync(MARKER, latestEtag);
  console.log('Model up to date.');
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
