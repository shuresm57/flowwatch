#!/bin/bash

# FlowWatch Demo - Test the intrusion detection API against real CICIDS2017 network traffic.
#
# Usage: ./demo.sh [SAMPLES]
#   SAMPLES  Number of random rows to test per traffic type (default: 5)
#
# For each test, the script:
#   1. Picks SAMPLES random rows from a CICIDS2017 CSV file
#   2. Sends them to the /analyze/csv endpoint
#   3. Compares each prediction against the true label in the CSV
#   4. Prints PASS/FAIL with confidence percentage
# A summary of total passed/failed is printed at the end.
#
# Requires: curl, jq, shuf (coreutils)
# Start the API first: cd src && npm start

API="http://localhost:3000"
DATA="$(dirname "$0")/data"
SAMPLES="${1:-5}"
TOTAL_PASS=0
TOTAL_FAIL=0
LAST_PASS=0
LAST_FAIL=0

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

# run_test <num> <title> <description> <csv_file> <filter>
#
# Runs one test against a CSV file from the CICIDS2017 dataset.
#
# Arguments:
#   num         Test number shown in the header
#   title       Short name of the traffic/attack type
#   description One-line description printed under the header
#   csv_file    Path to the CICIDS2017 CSV (header + labelled rows)
#   filter      Optional grep pattern to pre-filter rows before sampling.
#               Use this for attack types that are sparse in a mixed file
#               (e.g. "Infiltration" appears in only ~36 of 288k rows).
#               Pass an empty string to sample from the full file.
#
# Outputs LAST_PASS and LAST_FAIL for the caller to accumulate.
run_test() {
  local TEST_NUM="$1"
  local TITLE="$2"
  local DESCRIPTION="$3"
  local FILE="$4"
  local FILTER="$5"

  echo "=============================================================================="
  echo "Test $TEST_NUM: $TITLE"
  echo "Description: $DESCRIPTION"
  echo "=============================================================================="

  local HEADER SAMPLED RESPONSE
  # Keep the header row separate so we can prepend it to the sampled rows.
  HEADER=$(head -n 1 "$FILE")

  # When a filter is set, grep first so shuf only sees matching rows.
  # This prevents sparse attack types from being drowned out by BENIGN rows.
  if [[ -n "$FILTER" ]]; then
    SAMPLED=$(grep "$FILTER" "$FILE" | shuf -n "$SAMPLES")
  else
    SAMPLED=$(tail -n +2 "$FILE" | shuf -n "$SAMPLES")
  fi

  # Send header + sampled rows to the batch classification endpoint.
  # --data-binary preserves newlines (unlike -d which can mangle the body).
  RESPONSE=$(printf '%s\n%s\n' "$HEADER" "$SAMPLED" | \
    curl -s -X POST "$API/analyze/csv" \
    -H "Content-Type: text/csv" \
    --data-binary @-)

  local EXPECTED PREDICTED CONFIDENCES
  # Extract the true label from the last CSV column, trimming surrounding whitespace.
  EXPECTED=$(printf '%s\n' "$SAMPLED" | awk -F',' '{gsub(/^[ \t]+|[ \t]+$/, "", $NF); print $NF}')
  # Extract predicted label and confidence (as XX.XX%) from the JSON response.
  PREDICTED=$(printf '%s\n' "$RESPONSE" | jq -r '.[] | .label')
  CONFIDENCES=$(printf '%s\n' "$RESPONSE" | jq -r '.[] | (.confidence * 10000 | round / 100 | tostring) + "%"')

  local PASS=0 FAIL=0
  # Zip the three streams together and compare expected vs predicted label.
  # Process substitution keeps PASS/FAIL in the current shell scope (a pipe subshell would lose them).
  while IFS=$'\t' read -r exp pred conf; do
    if [[ "$exp" == "$pred" ]]; then
      echo "  [PASS] $exp -> $pred ($conf)"
      PASS=$((PASS + 1))
    else
      echo "  [FAIL] Expected: $exp | Got: $pred ($conf)"
      FAIL=$((FAIL + 1))
    fi
  done < <(paste <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$PREDICTED") <(printf '%s\n' "$CONFIDENCES"))

  LAST_PASS=$PASS
  LAST_FAIL=$FAIL
  echo ""
}

run_test 1 "Benign Traffic (Monday)" \
  "Normal network traffic" \
  "$DATA/Monday-WorkingHours.pcap_ISCX.csv" ""
TOTAL_PASS=$((TOTAL_PASS + LAST_PASS)); TOTAL_FAIL=$((TOTAL_FAIL + LAST_FAIL))

run_test 2 "DDoS Attack" \
  "Distributed Denial of Service attacks" \
  "$DATA/Friday-WorkingHours-Afternoon-DDos.pcap_ISCX.csv" ""
TOTAL_PASS=$((TOTAL_PASS + LAST_PASS)); TOTAL_FAIL=$((TOTAL_FAIL + LAST_FAIL))

run_test 3 "PortScan Attack" \
  "Network port scanning attempts" \
  "$DATA/Friday-WorkingHours-Afternoon-PortScan.pcap_ISCX.csv" ""
TOTAL_PASS=$((TOTAL_PASS + LAST_PASS)); TOTAL_FAIL=$((TOTAL_FAIL + LAST_FAIL))

run_test 4 "Web Attack" \
  "Web-based attacks (SQL injection, XSS, brute force)" \
  "$DATA/Thursday-WorkingHours-Morning-WebAttacks.pcap_ISCX.csv" ""
TOTAL_PASS=$((TOTAL_PASS + LAST_PASS)); TOTAL_FAIL=$((TOTAL_FAIL + LAST_FAIL))

run_test 5 "DoS Attack (Hulk)" \
  "HTTP flood denial of service" \
  "$DATA/Wednesday-workingHours.pcap_ISCX.csv" "DoS Hulk"
TOTAL_PASS=$((TOTAL_PASS + LAST_PASS)); TOTAL_FAIL=$((TOTAL_FAIL + LAST_FAIL))

run_test 6 "Infiltration" \
  "Host infiltration attack" \
  "$DATA/Thursday-WorkingHours-Afternoon-Infilteration.pcap_ISCX.csv" "Infiltration"
TOTAL_PASS=$((TOTAL_PASS + LAST_PASS)); TOTAL_FAIL=$((TOTAL_FAIL + LAST_FAIL))

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
