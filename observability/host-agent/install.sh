#!/usr/bin/env bash
set -euo pipefail

OTEL_VERSION="0.149.0"
INSTALL_BIN="/usr/local/bin/otelcol-contrib"
CONFIG_DIR="/etc/otelcol-contrib"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
SERVICE_FILE="/etc/systemd/system/otel-collector.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Downloading otelcol-contrib ${OTEL_VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_linux_amd64.tar.gz"
# Stock Ubuntu installs ship wget but not always curl
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${URL}" -o "${TMP}/otelcol-contrib.tar.gz"
else
  wget -q "${URL}" -O "${TMP}/otelcol-contrib.tar.gz"
fi

tar -xzf "${TMP}/otelcol-contrib.tar.gz" -C "${TMP}"
sudo install -m 0755 "${TMP}/otelcol-contrib" "${INSTALL_BIN}"
echo "    installed ${INSTALL_BIN}"

echo "==> Installing config"
sudo mkdir -p "${CONFIG_DIR}"
# METRICS_ONLY=1 skips journald shipping (see otel-collector-config-metrics-only.yaml)
if [[ "${METRICS_ONLY:-0}" == 1 ]]; then
  CONFIG_SRC="${SCRIPT_DIR}/otel-collector-config-metrics-only.yaml"
else
  CONFIG_SRC="${SCRIPT_DIR}/otel-collector-config.yaml"
fi
sudo install -m 0644 "${CONFIG_SRC}" "${CONFIG_FILE}"
echo "    installed ${CONFIG_FILE}"

echo "==> Installing systemd service"
sudo install -m 0644 "${SCRIPT_DIR}/otel-collector.service" "${SERVICE_FILE}"
sudo systemctl daemon-reload
sudo systemctl enable --now otel-collector
echo "    service enabled and started"

echo ""
echo "==> Status"
sudo systemctl is-active otel-collector
