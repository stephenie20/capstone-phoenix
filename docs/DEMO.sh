#!/usr/bin/env bash
# docs/DEMO.sh
# 10-minute live demo script for the capstone viva.
# Run each numbered block in order. Comments are what you say out loud.
# Rehearse this at least twice before the real demo.
set -euo pipefail

export KUBECONFIG=./kubeconfig
DOMAIN="stephenie.name.ng"

# ─────────────────────────────────────────────────────────────────────────────
# BLOCK 1 (~1 min) — Show the cluster is real and multi-node
# ─────────────────────────────────────────────────────────────────────────────
echo "=== 1. Multi-node cluster ==="
kubectl get nodes -o wide
# Say: "Three nodes — one control plane, two workers, all Ready.
#       This is a real k3s cluster on AWS t3.small instances."

echo ""
echo "=== 1b. Pods spread across both workers ==="
kubectl get pods -n taskapp -o wide
# Say: "Frontend and backend replicas are on *different* nodes —
#       topologySpreadConstraints enforces this."

# ─────────────────────────────────────────────────────────────────────────────
# BLOCK 2 (~1 min) — Show TLS is real
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== 2. Valid Let's Encrypt certificate ==="
curl -sI https://${DOMAIN} | grep -E "HTTP|server|x-powered"
echo ""
echo "Certificate details:"
echo | openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} 2>/dev/null \
  | openssl x509 -noout -issuer -subject -dates
# Say: "Issuer is Let's Encrypt. Real cert, real domain, not self-signed."

# ─────────────────────────────────────────────────────────────────────────────
# BLOCK 3 (~1 min) — Show Argo CD owns the cluster
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== 3. GitOps — Argo CD status ==="
kubectl -n argocd get app taskapp
# Say: "Synced and Healthy. Argo CD reconciles from the git repo —
#       I cannot make a permanent change without a git commit."

# ─────────────────────────────────────────────────────────────────────────────
# BLOCK 4 (~2 min) — GitOps commit → auto-sync
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== 4. Live GitOps: bump frontend replicas 2 → 3 ==="
OVERLAY="manifests/overlays/production/kustomization.yaml"

# Patch replica count inline (revert after demo)
sed -i 's/value: 2$/value: 3/' ${OVERLAY}
git add ${OVERLAY}
git commit -m "demo: scale frontend to 3 replicas"
git push

echo "Pushed. Watching Argo sync (polls every 3 min, or force it)..."
kubectl -n argocd get app taskapp -w &
WATCH_PID=$!

# Force immediate sync for the demo
sleep 5
kubectl -n argocd app sync taskapp

wait $WATCH_PID || true
kubectl get pods -n taskapp | grep frontend
# Say: "Three frontend pods now. Argo applied the change — I never ran kubectl apply."

# Revert for cleanliness
sed -i 's/value: 3$/value: 2/' ${OVERLAY}
git add ${OVERLAY}
git commit -m "demo: revert frontend to 2 replicas [skip ci]"
git push

# ─────────────────────────────────────────────────────────────────────────────
# BLOCK 5 (~2 min) — Zero-downtime rolling deploy
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== 5. Zero-downtime rolling deploy ==="
echo "Starting load in background (30s, 5 concurrent)..."
hey -z 30s -c 5 https://${DOMAIN} > /tmp/zero-downtime.log &
HEY_PID=$!

echo "Triggering rolling restart..."
kubectl rollout restart deployment/backend -n taskapp
kubectl rollout status deployment/backend -n taskapp --timeout=60s

wait $HEY_PID
echo ""
echo "Load test results:"
grep "Status code distribution" -A5 /tmp/zero-downtime.log
# Say: "Every response was 200. maxUnavailable: 0 means the new pod
#       must pass its readiness probe before the old one is terminated."

# ─────────────────────────────────────────────────────────────────────────────
# BLOCK 6 (~2 min) — Live node drain (failover demo)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== 6. Node drain — failover demo ==="

# Find a worker that has app pods on it
DRAIN_NODE=$(kubectl get pods -n taskapp -o wide \
  | grep -v control-plane | awk 'NR==2{print $7}')
echo "Draining node: ${DRAIN_NODE}"
echo "Starting health check in background..."

# Continuous health check during drain
(for i in $(seq 1 30); do
  CODE=$(curl -so /dev/null -w "%{http_code}" https://${DOMAIN})
  echo "$(date +%T) — HTTP ${CODE}"
  sleep 2
done) &
HEALTH_PID=$!

kubectl drain ${DRAIN_NODE} \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=30

echo ""
echo "Node drained. Pods rescheduled:"
kubectl get pods -n taskapp -o wide

wait $HEALTH_PID
# Say: "Every health check returned 200 throughout the drain.
#       The PDB kept minAvailable: 1 — Kubernetes could not evict the
#       last backend pod until a replacement was Ready."

echo ""
echo "Uncordoning node..."
kubectl uncordon ${DRAIN_NODE}

# ─────────────────────────────────────────────────────────────────────────────
# BLOCK 7 (~1 min) — PVC data persistence
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== 7. Data survives a postgres pod kill ==="
kubectl exec -n taskapp postgres-0 -- \
  psql -U taskapp -d taskapp -c \
  "INSERT INTO tasks (title, done) VALUES ('demo-persistence', false);" 2>/dev/null

kubectl delete pod postgres-0 -n taskapp
kubectl wait pod/postgres-0 -n taskapp --for=condition=Ready --timeout=60s

kubectl exec -n taskapp postgres-0 -- \
  psql -U taskapp -d taskapp -c \
  "SELECT title, done FROM tasks WHERE title='demo-persistence';"
# Say: "Row survived. The PVC re-attached to the restarted pod automatically."

echo ""
echo "=== Demo complete ==="
