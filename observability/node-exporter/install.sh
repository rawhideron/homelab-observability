#!/usr/bin/env bash
# Installs Prometheus node_exporter as a systemd service running as a dedicated
# non-root user. Re-running it upgrades or replaces an existing install.
set -euo pipefail

VERSION="1.12.1"
SHA256="b51d8a76aa2a9156a55d501aca6276fae09e262259a5e4e831d2c2222f084e63"
INSTALL_BIN="/usr/local/bin/node_exporter"
SERVICE_FILE="/etc/systemd/system/node_exporter.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Downloading node_exporter ${VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

NAME="node_exporter-${VERSION}.linux-amd64"
URL="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/${NAME}.tar.gz"
# Stock Ubuntu installs ship wget but not always curl
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${URL}" -o "${TMP}/${NAME}.tar.gz"
else
  wget -q "${URL}" -O "${TMP}/${NAME}.tar.gz"
fi
echo "${SHA256}  ${TMP}/${NAME}.tar.gz" | sha256sum -c -

tar -xzf "${TMP}/${NAME}.tar.gz" -C "${TMP}"

echo "==> Creating node_exporter user"
if ! id node_exporter >/dev/null 2>&1; then
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
fi

echo "==> Installing binary and systemd service"
# Stop first: install can't overwrite a running binary ("Text file busy")
sudo systemctl stop node_exporter 2>/dev/null || true
sudo install -o root -g root -m 0755 "${TMP}/${NAME}/node_exporter" "${INSTALL_BIN}"
sudo install -m 0644 "${SCRIPT_DIR}/node_exporter.service" "${SERVICE_FILE}"
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

echo ""
echo "==> Status"
sudo systemctl is-active node_exporter
