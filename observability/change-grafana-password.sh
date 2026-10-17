#!/usr/bin/env bash
# Usage: ./change-grafana-password.sh <new-password>
#
# Changes the Grafana admin password by:
#   1. Reading the current password from the grafana-admin-credentials secret
#   2. Calling the Grafana API to update the password in Grafana's database
#   3. Updating the secret to stay in sync
#
# A pod restart is NOT used because Grafana only reads GF_SECURITY_ADMIN_PASSWORD
# on first boot (empty DB). After that, the database value takes precedence and
# env-var changes are ignored.
set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:30300}"
NAMESPACE="${NAMESPACE:-observability}"
SECRET="grafana-admin-credentials"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <new-password>" >&2
  exit 1
fi

NEW_PASSWORD="$1"

echo "==> Reading current password from secret ${SECRET}..."
CURRENT_PASSWORD=$(kubectl get secret -n "${NAMESPACE}" "${SECRET}" \
  -o jsonpath='{.data.admin-password}' | base64 -d)

echo "==> Updating password via Grafana API..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT \
  -H "Content-Type: application/json" \
  -u "admin:${CURRENT_PASSWORD}" \
  -d "{\"oldPassword\":\"${CURRENT_PASSWORD}\",\"newPassword\":\"${NEW_PASSWORD}\",\"confirmNew\":\"${NEW_PASSWORD}\"}" \
  "${GRAFANA_URL}/api/user/password")

if [[ "${HTTP_STATUS}" != "200" ]]; then
  echo "error: Grafana API returned HTTP ${HTTP_STATUS} — password not changed" >&2
  echo "  Check that GRAFANA_URL (${GRAFANA_URL}) is reachable and the current" >&2
  echo "  password in the secret matches what Grafana has in its database." >&2
  exit 1
fi

echo "==> Syncing new password into secret ${SECRET}..."
kubectl create secret generic "${SECRET}" \
  -n "${NAMESPACE}" \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="${NEW_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Done."
