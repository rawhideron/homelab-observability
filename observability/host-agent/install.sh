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

curl -fsSL \
  "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_linux_amd64.tar.gz" \
  -o "${TMP}/otelcol-contrib.tar.gz"

tar -xzf "${TMP}/otelcol-contrib.tar.gz" -C "${TMP}"
sudo install -m 0755 "${TMP}/otelcol-contrib" "${INSTALL_BIN}"
echo "    installed ${INSTALL_BIN}"

echo "==> Installing config"
sudo mkdir -p "${CONFIG_DIR}"
sudo install -m 0644 "${SCRIPT_DIR}/otel-collector-config.yaml" "${CONFIG_FILE}"
echo "    installed ${CONFIG_FILE}"

echo "==> Installing systemd service"
sudo install -m 0644 "${SCRIPT_DIR}/otel-collector.service" "${SERVICE_FILE}"
sudo systemctl daemon-reload
sudo systemctl enable --now otel-collector
echo "    service enabled and started"

echo ""
echo "==> Status"
sudo systemctl is-active otel-collector
