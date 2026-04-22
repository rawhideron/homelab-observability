#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-observability}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_cmd helm
require_cmd kubectl
require_cmd sudo

echo "Using repo root: ${REPO_ROOT}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install loki grafana/loki \
  -n "${NAMESPACE}" \
  --values "${REPO_ROOT}/observability/loki-values.yaml" \
  --wait --timeout 5m

helm upgrade --install tempo grafana/tempo \
  -n "${NAMESPACE}" \
  --values "${REPO_ROOT}/observability/tempo-values.yaml" \
  --wait --timeout 5m

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n "${NAMESPACE}" \
  --values "${REPO_ROOT}/observability/kube-prometheus-stack-values.yaml" \
  --wait --timeout 10m

helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
  -n "${NAMESPACE}" \
  --values "${REPO_ROOT}/observability/otel-collector-gateway-values.yaml" \
  --wait --timeout 5m

sudo install -m 0755 "${REPO_ROOT}/observability/otel-forward.py" /usr/local/bin/otel-forward.py
sudo install -m 0644 "${REPO_ROOT}/observability/otel-forward.service" /etc/systemd/system/otel-forward.service
sudo systemctl daemon-reload
sudo systemctl enable --now otel-forward

kubectl -n "${NAMESPACE}" get pods
sudo systemctl is-enabled otel-forward
sudo systemctl is-active otel-forward
