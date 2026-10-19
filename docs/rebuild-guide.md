# Rebuild Guide

This repo is the source of truth for the observability hub. If the host reboots, the
Kind node IP changes, or the hub needs to be recreated from scratch, prefer rebuilding
from this repo instead of trying to preserve the old environment exactly.

## Hub Rebuild

Run this on `192.168.1.176` from the repo root:

```bash
chmod +x observability/rebuild-hub.sh
./observability/rebuild-hub.sh
```

What it does:

- refreshes Helm repos
- creates the `observability` namespace if needed
- installs or upgrades Loki, Tempo, Prometheus/Grafana, and the OTel gateway
- installs the host-side `otel-forward` systemd service
- enables and starts `otel-forward`
- prints pod status and service status for a quick check

## Source Agent Reinstall

Run on each source cluster host after the cluster is available:

### jan2026

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
kubectl create namespace otel-agent --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector \
  --version 0.150.1 \
  -n otel-agent \
  --values observability/otel-collector-agent-values.yaml \
  --set "extraEnvs[0].value=jan2026" \
  --wait --timeout 3m
```

### inspiron-k3s (192.168.1.177)

```bash
# k3s's kubeconfig is root-only, so run helm with sudo and give it the chart repo URL
sudo helm --kubeconfig /etc/rancher/k3s/k3s.yaml upgrade --install otel-agent opentelemetry-collector \
  --repo https://open-telemetry.github.io/opentelemetry-helm-charts --version 0.150.1 \
  --create-namespace -n otel-agent \
  --values observability/otel-collector-agent-values.yaml \
  --set "extraEnvs[0].value=inspiron-k3s" --wait --timeout 3m

# Host metrics for the Hosts dashboard. Metrics only: shipping the 3.2 GB journal
# from its spinning disk drove this 8 GB machine into swap on 2026-10-19.
# Installed but currently disabled; enable with: sudo systemctl enable --now otel-collector
METRICS_ONLY=1 bash observability/host-agent/install.sh
```

### zephyrus

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
kubectl create namespace otel-agent --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector \
  --version 0.150.1 \
  -n otel-agent \
  --values observability/otel-collector-agent-values.yaml \
  --set "extraEnvs[0].value=zephyrus" \
  --wait --timeout 3m
```

## Verification

From another host, these should be reachable on `192.168.1.176`:

- `30300` for Grafana
- `9090` for Prometheus
- `9093` for Alertmanager
- `4317` for OTLP gRPC

On the hub host:

```bash
systemctl status otel-forward --no-pager
kubectl -n observability get pods
```
