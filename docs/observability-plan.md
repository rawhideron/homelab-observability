# Homelab Observability Hub

Central observability platform running on 192.168.1.176, collecting metrics, logs, and traces from all homelab Kubernetes clusters.

## Architecture

- **Hub (192.168.1.176):** OTel Collector gateway + Prometheus + Grafana + Loki + Tempo
- **Source clusters:** OTel agents (DaemonSet) ship to hub at 192.168.1.176:4317

| Cluster | Host | OTel cluster.name |
|---|---|---|
| jan2026 | 192.168.1.230 | jan2026 |
| rawhideron | 192.168.1.153 | rawhideron |
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

### Source: rawhideron (192.168.1.153 — rawhideron)

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts && helm repo update
kubectl create namespace otel-agent --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector -n otel-agent   --values observability/otel-collector-agent-values.yaml   --set "extraEnvs[0].value=rawhideron" --wait --timeout 3m
```

## Querying in Grafana

Filter by cluster and namespace using variables:
- `label_values(k8s_cluster_name)` → jan2026, rawhideron, or zephyrus
- `label_values(k8s_namespace_name{k8s_cluster_name="$cluster"})` → reunion, n8n-rag, etc.

## Recommended Dashboard IDs

| ID | Name |
|---|---|
| 315 | Kubernetes cluster overview |
| 1860 | Node Exporter Full |
| 15141 | Kubernetes pods (Loki logs) |
