#!/usr/bin/env bash
# Usage: ./change-grafana-password.sh <new-password>
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <new-password>" >&2
  exit 1
fi

kubectl create secret generic grafana-admin-credentials \
  -n observability \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$1" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n observability rollout restart deployment kube-prometheus-stack-grafana
kubectl -n observability rollout status deployment kube-prometheus-stack-grafana
