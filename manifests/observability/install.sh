#!/usr/bin/env bash
# manifests/observability/install.sh
# Installs kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
# with a pre-configured dashboard for TaskApp metrics.
#
# Prerequisites: helm >= 3.14 installed on your laptop.
# Run after platform/install.sh.
set -euo pipefail

STACK_VERSION="58.5.3"   # kube-prometheus-stack chart version

echo "==> Adding prometheus-community Helm repo"
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update

echo "==> Installing kube-prometheus-stack"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version "${STACK_VERSION}" \
  --values manifests/observability/prometheus-values.yaml \
  --wait \
  --timeout 10m

echo ""
echo "✅  Observability stack ready."
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "  URL:      http://localhost:3000"
echo "  User:     admin"
echo "  Password: $(kubectl get secret -n monitoring kube-prometheus-stack-grafana \
    -o jsonpath='{.data.admin-password}' | base64 -d)"
echo ""
echo "Key dashboards pre-installed:"
echo "  - Kubernetes / Compute Resources / Namespace (taskapp)"
echo "  - Kubernetes / Compute Resources / Pod"
echo "  - TaskApp custom (ID imported from observability/grafana-dashboard.json)"
