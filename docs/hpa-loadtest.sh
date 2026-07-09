#!/usr/bin/env bash
# docs/hpa-loadtest.sh
# Drives CPU load on the backend, captures HPA scaling, saves evidence.
# Run this AFTER the cluster is live and metrics-server is working.
#
# Prerequisites: hey (https://github.com/rakyll/hey)
#   go install github.com/rakyll/hey@latest
set -euo pipefail

export KUBECONFIG=./kubeconfig
API_URL="https://api.stephenie.name.ng"
EVIDENCE_DIR="docs/EVIDENCE"

echo "==> Verifying metrics-server is working..."
kubectl top pods -n taskapp || {
  echo "ERROR: kubectl top not working — metrics-server may not be ready yet."
  echo "Wait 2 minutes after install and try again."
  exit 1
}

echo ""
echo "==> Current HPA state (before load):"
kubectl get hpa -n taskapp
kubectl get pods -n taskapp | grep backend

echo ""
echo "==> Starting 3-minute load test (100 concurrent requests)..."
echo "    Watch in another terminal: watch -n 5 kubectl get hpa -n taskapp"
echo ""

hey -z 180s -c 100 -m GET "${API_URL}/api/health" > "${EVIDENCE_DIR}/hpa-loadtest-raw.log" &
HEY_PID=$!

# Poll HPA every 15 seconds and log replica count
echo "timestamp,current_replicas,desired_replicas,cpu_percent" > "${EVIDENCE_DIR}/hpa-scale.csv"
START=$(date +%s)
MAX_SEEN=0

while kill -0 $HEY_PID 2>/dev/null; do
  sleep 15
  ELAPSED=$(( $(date +%s) - START ))

  HPA_LINE=$(kubectl get hpa backend-hpa -n taskapp --no-headers 2>/dev/null || echo "0/60%   2   6   2")
  CURRENT=$(echo "$HPA_LINE" | awk '{print $6}')
  DESIRED=$(echo "$HPA_LINE" | awk '{print $7}')
  CPU=$(kubectl top pods -n taskapp --no-headers 2>/dev/null \
    | grep backend | awk '{sum+=$2} END {print sum}' | tr -d 'm' || echo "0")

  echo "${ELAPSED}s,${CURRENT},${DESIRED},${CPU}m" | tee -a "${EVIDENCE_DIR}/hpa-scale.csv"

  if [[ "${CURRENT}" -gt "${MAX_SEEN}" ]]; then
    MAX_SEEN="${CURRENT}"
    echo "    *** New peak: ${CURRENT} replicas — capturing screenshot prompt ***"
    kubectl get hpa -n taskapp
    kubectl get pods -n taskapp -o wide | grep backend
    echo ""
    echo "    >>> Take your hpa-scale.png screenshot NOW <<<"
    echo ""
  fi
done

wait $HEY_PID

echo ""
echo "==> Load test complete. Results:"
grep "Summary\|Requests/sec\|Status code" "${EVIDENCE_DIR}/hpa-loadtest-raw.log" || true

echo ""
echo "==> Max replicas seen: ${MAX_SEEN}"
echo ""
echo "==> HPA state after load (replicas should be scaling back down):"
kubectl get hpa -n taskapp

echo ""
echo "Evidence saved:"
echo "  ${EVIDENCE_DIR}/hpa-scale.csv      — replica count over time"
echo "  ${EVIDENCE_DIR}/hpa-loadtest-raw.log — hey output"
echo ""
echo "Take your hpa-scale.png screenshot when replicas show > 2."
