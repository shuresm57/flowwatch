#!/bin/bash

# Load .env from repo root if present (provides HF_TOKEN etc.)
SCRIPT_DIR="$(dirname "$0")"
[[ -f "$SCRIPT_DIR/.env" ]] && set -a && source "$SCRIPT_DIR/.env" && set +a

# FlowWatch Demo - Test the intrusion detection API against the CICIDS2017
# `cleaned.csv` evaluation dataset hosted on HuggingFace.
#
# Usage: ./demo.sh [SAMPLES] [--attacks-only]
#   SAMPLES        Number of random rows to test (default: 30)
#   --attacks-only  Sample only non-BENIGN flows (label != 0)
#
# The script:
#   1. Streams cleaned.csv from HuggingFace into a temp file (deleted on exit)
#   2. Samples SAMPLES random rows and POSTs them to /analyze/csv
#   3. Compares each predicted label_id against the true (integer) Label column
#   4. Prints PASS/FAIL with the label name and confidence
# A summary of total passed/failed is printed at the end.
#
# cleaned.csv has 78 feature columns plus a label-encoded integer `Label` as the
# last column (0-14), so we compare the API's numeric label_id against it.
#
# Config (env vars):
#   HF_DATASET_REPO  HuggingFace dataset repo holding cleaned.csv
#   HF_REVISION      Branch/revision to pull (default: main)
#   HF_TOKEN         Token for private dataset repos
#
# Requires: curl, jq, shuf (coreutils)
# Start the API first: cd src && npm start

API="http://localhost:3000"
SAMPLES=30
ATTACKS_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --attacks-only) ATTACKS_ONLY=true ;;
    [0-9]*)         SAMPLES="$arg" ;;
  esac
done

HF_DATASET_REPO="${HF_DATASET_REPO:-valthe/flowwatch}"
HF_REVISION="${HF_REVISION:-main}"

echo ""
echo "=============================================================================="
echo "FlowWatch - Network Intrusion Detection Demo"
echo "=============================================================================="
echo ""

# Verify the API is reachable before running any tests.
echo "Checking API connection..."
if ! curl -s "$API/health" > /dev/null 2>&1; then
    echo "API not running!"
    echo "   Start it with: cd src && npm start"
    exit 1
fi
echo "Connected"
echo ""

# Stream cleaned.csv into a temp file; deleted automatically on exit.
TMPFILE=$(mktemp /tmp/flowwatch-demo.XXXXXX.csv)
trap 'rm -f "$TMPFILE"' EXIT

URL="https://huggingface.co/datasets/${HF_DATASET_REPO}/resolve/${HF_REVISION}/cleaned.csv"
AUTH=()
[[ -n "$HF_TOKEN" ]] && AUTH=(-H "Authorization: Bearer $HF_TOKEN")

echo "Streaming cleaned.csv from ${HF_DATASET_REPO}@${HF_REVISION}..."
if ! curl -fL "${AUTH[@]}" -o "$TMPFILE" "$URL"; then
  echo "Failed to stream cleaned.csv from $URL"
  echo "   Check HF_DATASET_REPO / HF_REVISION (and HF_TOKEN for a private repo)."
  exit 1
fi
echo ""

FILTER_LABEL="all flows"
$ATTACKS_ONLY && FILTER_LABEL="attacks only (non-BENIGN)"

echo "=============================================================================="
echo "Evaluating $SAMPLES random $FILTER_LABEL from cleaned.csv"
echo "=============================================================================="

# Keep the header row so the API can map columns by feature name.
HEADER=$(head -n 1 "$TMPFILE")
if $ATTACKS_ONLY; then
  # Label is the last column; 0 = BENIGN — exclude those rows.
  SAMPLED=$(tail -n +2 "$TMPFILE" | awk -F',' '{gsub(/[[:space:]]/, "", $NF); if ($NF != "0") print}' | shuf -n "$SAMPLES")
else
  SAMPLED=$(tail -n +2 "$TMPFILE" | shuf -n "$SAMPLES")
fi

# Send header + sampled rows to the batch classification endpoint.
# --data-binary preserves newlines (unlike -d which can mangle the body).
RESPONSE=$(printf '%s\n%s\n' "$HEADER" "$SAMPLED" | \
  curl -s -X POST "$API/analyze/csv" \
  -H "Content-Type: text/csv" \
  --data-binary @-)

# True label is the last CSV column (integer 0-14), trimmed of whitespace.
EXPECTED=$(printf '%s\n' "$SAMPLED" | awk -F',' '{gsub(/^[ \t]+|[ \t]+$/, "", $NF); print $NF}')
# Predicted numeric id, its human-readable name, and confidence as XX.XX%.
PREDICTED=$(printf '%s\n' "$RESPONSE" | jq -r '.[] | .label_id')
NAMES=$(printf '%s\n' "$RESPONSE" | jq -r '.[] | .label')
CONFIDENCES=$(printf '%s\n' "$RESPONSE" | jq -r '.[] | (.confidence * 10000 | round / 100 | tostring) + "%"')

TOTAL_PASS=0
TOTAL_FAIL=0
# Zip the streams together and compare expected vs predicted label id.
# Process substitution keeps the counters in the current shell scope.
while IFS=$'\t' read -r exp pred name conf; do
  if [[ "$exp" == "$pred" ]]; then
    echo "  [PASS] label $exp -> $name ($conf)"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    echo "  [FAIL] Expected label: $exp | Got: $pred ($name, $conf)"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
done < <(paste \
  <(printf '%s\n' "$EXPECTED") \
  <(printf '%s\n' "$PREDICTED") \
  <(printf '%s\n' "$NAMES") \
  <(printf '%s\n' "$CONFIDENCES"))

echo ""
TOTAL=$((TOTAL_PASS + TOTAL_FAIL))
echo "=============================================================================="
echo "Summary: $TOTAL_PASS/$TOTAL tests passed"
if [[ $TOTAL_FAIL -eq 0 ]]; then
  echo "All tests passed."
else
  echo "$TOTAL_FAIL test(s) failed."
fi
echo "=============================================================================="
echo ""
