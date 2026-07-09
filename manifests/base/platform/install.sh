#!/usr/bin/env bash
# platform/install.sh
# Installs all platform components onto the cluster.
# Run ONCE after `kubectl get nodes` shows all nodes Ready.
# Idempotent — safe to re-run.
set -euo pipefail

CERT_MANAGER_VERSION="v1.14.5"
ARGOCD_VERSION="v2.11.3"
INGRESS_NGINX_VERSION="v1.10.1"

echo "==> 1. ingress-nginx"
kubectl apply -f \
  "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${INGRESS_NGINX_VERSION}/deploy/static/provider/cloud/deploy.yaml"

echo "    Waiting for ingress-nginx to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo "==> 2. cert-manager"
kubectl apply -f \
  "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

echo "    Waiting for cert-manager webhooks..."
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=120s

echo "==> 3. metrics-server (required for HPA)"
kubectl apply -f \
  https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# k3s: metrics-server needs --kubelet-insecure-tls on single-CA setups
kubectl patch deployment metrics-server \
  --namespace kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' \
  || true   # already patched on re-run

echo "==> 4. Argo CD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "    Waiting for Argo CD server..."
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=180s

echo ""
echo "✅  Platform ready."
echo ""
echo "Next steps:"
echo "  1. Apply the ClusterIssuer + App:   kubectl apply -f gitops/application.yaml"
echo "  2. Get the initial Argo CD password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "  3. Port-forward Argo UI:             kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  4. Create secrets out-of-band (see manifests/base/*/secret.example.yaml)"
