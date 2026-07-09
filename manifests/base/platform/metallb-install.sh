#!/usr/bin/env bash
# manifests/base/platform/metallb-install.sh
# Installs MetalLB in L2 mode so ingress-nginx gets a stable VIP
# instead of binding to one worker node's IP.
#
# Run AFTER platform/install.sh, BEFORE applying gitops/application.yaml.
# Usage: bash manifests/base/platform/metallb-install.sh <worker1-ip> <worker2-ip>
#
# The VIP will be one of the worker public IPs you pass in.
# Point your DNS A records at that VIP — it floats between nodes.
set -euo pipefail

WORKER1_IP="${1:?Usage: $0 <worker1-public-ip> <worker2-public-ip>}"
WORKER2_IP="${2:?Usage: $0 <worker1-public-ip> <worker2-public-ip>}"
METALLB_VERSION="v0.14.5"

echo "==> Installing MetalLB ${METALLB_VERSION}"
kubectl apply -f \
  "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

echo "    Waiting for MetalLB controller..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb,component=controller \
  --timeout=120s

echo "==> Configuring L2 address pool (worker IPs: ${WORKER1_IP}, ${WORKER2_IP})"
cat <<EOF | kubectl apply -f -
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: worker-pool
  namespace: metallb-system
spec:
  addresses:
    - ${WORKER1_IP}/32
    - ${WORKER2_IP}/32
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - worker-pool
EOF

echo ""
echo "✅  MetalLB ready."
echo ""
echo "ingress-nginx will now get a LoadBalancer IP from the worker pool."
echo "Check it with:"
echo "  kubectl get svc -n ingress-nginx ingress-nginx-controller"
echo ""
echo "Point your DNS A records (stephenie.name.ng, api.stephenie.name.ng)"
echo "at whichever IP MetalLB assigns — it floats on failover."
