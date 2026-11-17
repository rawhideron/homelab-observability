#!/usr/bin/env bash
# Installs the daily Java patch check (run on 230). node_exporter must be
# started with --collector.textfile.directory=/var/lib/node_exporter/textfile
# (see ../node-exporter/node_exporter.service).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo install -d -m 0755 /var/lib/node_exporter/textfile
sudo install -m 0755 "${DIR}/java-patch-check.sh" /usr/local/bin/java-patch-check
sudo install -m 0644 "${DIR}/java-patch-check.env" /etc/java-patch-check.env
sudo install -m 0644 "${DIR}/java-patch-check.service" "${DIR}/java-patch-check.timer" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now java-patch-check.timer
sudo systemctl start java-patch-check.service
