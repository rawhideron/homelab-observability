# Homelab Observability Hub

Central observability platform running on 192.168.1.176, collecting metrics, logs, and traces from all homelab Kubernetes clusters.

## Component Versions

| Component | Chart | Image |
|---|---|---|
| OTel Collector (gateway + agents) | opentelemetry-collector 0.150.1 | otel/opentelemetry-collector-contrib:0.149.0 |
| otelcol-contrib (host-agent) | — | 0.149.0 |

## Architecture

- **Hub (192.168.1.176):** OTel Collector gateway + Prometheus + Grafana + Loki + Tempo
- **Source clusters:** OTel agents (DaemonSet) ship to hub at 192.168.1.176:4317

| Cluster | Host | OTel cluster.name |
|---|---|---|
| jan2026 | 192.168.1.230 | jan2026 |
| inspiron-k3s | 192.168.1.177 | inspiron-k3s |
| zephyrus | 192.168.1.176 | zephyrus |

## Grafana

URL: http://192.168.1.176:30300  
Default login: admin / changeme

## Install Commands

### Hub (192.168.1.176 — ron-goodman)

```bash
cd /home/ron-goodman/Projects/homelab-observability

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

kubectl create namespace observability

helm upgrade --install loki grafana/loki -n observability --values observability/loki-values.yaml --wait --timeout 5m
helm upgrade --install tempo grafana/tempo -n observability --values observability/tempo-values.yaml --wait --timeout 5m
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n observability --values observability/kube-prometheus-stack-values.yaml --wait --timeout 10m
helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector -n observability --values observability/otel-collector-gateway-values.yaml --wait --timeout 3m
```

### Source: jan2026 (192.168.1.230 — rongoodman)

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts && helm repo update
kubectl create namespace otel-agent --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector -n otel-agent   --values observability/otel-collector-agent-values.yaml   --set "extraEnvs[0].value=jan2026" --wait --timeout 3m
```

### Source: zephyrus (192.168.1.176 — ron-goodman)

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts && helm repo update
kubectl create namespace otel-agent --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector -n otel-agent   --values observability/otel-collector-agent-values.yaml   --set "extraEnvs[0].value=zephyrus" --wait --timeout 3m
```

### Source: inspiron-k3s (192.168.1.177 — rawhideron)

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

## Querying in Grafana

Filter by cluster and namespace using variables:
- `label_values(k8s_cluster_name)` → jan2026, inspiron-k3s, zephyrus or zephyrus-k3s
- `label_values(k8s_namespace_name{k8s_cluster_name="$cluster"})` → reunion, n8n-rag, etc.

## Recommended Dashboard IDs

| ID | Name |
|---|---|
| 315 | Kubernetes cluster overview |
| 1860 | Node Exporter Full |
| 15141 | Kubernetes pods (Loki logs) |
