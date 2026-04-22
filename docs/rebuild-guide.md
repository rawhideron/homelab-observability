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
  -n otel-agent \
  --values observability/otel-collector-agent-values.yaml \
  --set "extraEnvs[0].value=jan2026" \
  --wait --timeout 3m
```

### rawhideron

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
kubectl create namespace otel-agent --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector \
  -n otel-agent \
  --values observability/otel-collector-agent-values.yaml \
  --set "extraEnvs[0].value=rawhideron" \
  --wait --timeout 3m
```

### zephyrus

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
kubectl create namespace otel-agent --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector \
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
