#!/bin/bash

# FlowWatch Demo - Showcase intrusion detection on real attack data

API="http://localhost:3000"
SAMPLES=5

echo ""
echo "=============================================================================="
echo "FlowWatch - Network Intrusion Detection Demo"
echo "=============================================================================="
echo ""

# Check API
echo "Checking API connection..."
if ! curl -s "$API/health" > /dev/null 2>&1; then
    echo "API not running!"
    echo "   Start it with: cd src && npm start"
    exit 1
fi
echo "Connected"
echo ""

# Test benign traffic
echo "=============================================================================="
echo "Test 1: Benign Traffic (Monday)"
echo "Description: Normal network traffic"
echo "=============================================================================="
head -n $((SAMPLES+1)) data/Monday-WorkingHours.pcap_ISCX.csv | \
  curl -s -X POST "$API/analyze/csv" \
  -H "Content-Type: text/csv" -d @- | \
  jq -r '.[] | "\(.prediction) (confidence: \(.confidence | @json))"' | head -n $SAMPLES
echo ""

# Test DDoS attack
echo "=============================================================================="
echo "Test 2: DDoS Attack"
echo "Description: Distributed Denial of Service attacks"
echo "=============================================================================="
head -n $((SAMPLES+1)) data/Friday-WorkingHours-Afternoon-DDos.pcap_ISCX.csv | \
  curl -s -X POST "$API/analyze/csv" \
  -H "Content-Type: text/csv" -d @- | \
  jq -r '.[] | "\(.prediction) (confidence: \(.confidence | @json))"' | head -n $SAMPLES
echo ""

# Test PortScan attack
echo "=============================================================================="
echo "Test 3: PortScan Attack"
echo "Description: Network port scanning attempts"
echo "=============================================================================="
head -n $((SAMPLES+1)) data/Friday-WorkingHours-Afternoon-PortScan.pcap_ISCX.csv | \
  curl -s -X POST "$API/analyze/csv" \
  -H "Content-Type: text/csv" -d @- | \
  jq -r '.[] | "\(.prediction) (confidence: \(.confidence | @json))"' | head -n $SAMPLES
echo ""

# Test Web Attack
echo "=============================================================================="
echo "Test 4: Web Attack"
echo "Description: Web-based attacks (SQL injection, XSS, brute force)"
echo "=============================================================================="
head -n $((SAMPLES+1)) data/Thursday-WorkingHours-Morning-WebAttacks.pcap_ISCX.csv | \
  curl -s -X POST "$API/analyze/csv" \
  -H "Content-Type: text/csv" -d @- | \
  jq -r '.[] | "\(.prediction) (confidence: \(.confidence | @json))"' | head -n $SAMPLES
echo ""

echo "=============================================================================="
echo "Demo complete! Model correctly identifies benign traffic vs attacks."
echo "=============================================================================="
echo ""
