# homelab-observability

![Stack Status](https://img.shields.io/badge/stack-operational-brightgreen)
![Metrics](https://img.shields.io/badge/metrics-flowing-brightgreen)
![Logs](https://img.shields.io/badge/logs-flowing-brightgreen)
![Traces](https://img.shields.io/badge/traces-ready-blue)
![Clusters](https://img.shields.io/badge/clusters-2-blue)
![Grafana](https://img.shields.io/badge/grafana-10.x-orange)
![OTel](https://img.shields.io/badge/opentelemetry-0.147.0-blue)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

Central observability platform for all homelab Kubernetes clusters. Metrics, logs, and traces from multiple clusters flow into a single Grafana instance on a dedicated hub machine.

---

## Architecture

```
192.168.1.230 (jan2026)   192.168.1.176 (zephyrus)
OTel Agent DaemonSet       OTel Agent DaemonSet
        |                          |
        └──────── OTLP gRPC ───────┘
                     |
              192.168.1.153:4317
              (iptables DNAT → NodePort 30317)
                     |
           OTel Gateway (hub cluster)
           /           |           \
    Prometheus       Loki         Tempo
    (metrics)       (logs)       (traces)
           \           |           /
                  Grafana :30300
```

### Hub: 192.168.1.153 (rawhideron) — 4-node Kind cluster, 8GB RAM

| Component | Chart | Namespace | Status |
|---|---|---|---|
| OTel Collector (gateway) | open-telemetry/opentelemetry-collector | observability | ✅ Running |
| Prometheus + Grafana | prometheus-community/kube-prometheus-stack | observability | ✅ Running |
| Loki | grafana/loki | observability | ✅ Running |
| Tempo | grafana/tempo | observability | ✅ Running |

### Source Clusters

| Cluster | Host | Login | OTel Agent | ArgoCD |
|---|---|---|---|---|
| jan2026 | 192.168.1.230 | rongoodman | ✅ Running (4 pods) | https://goodmanreunion.duckdns.org/argocd |
| zephyrus | 192.168.1.176 | ron-goodman | ✅ Running | — |

---

## Accessing the UIs

### Grafana — primary UI for all signals

| URL | Credentials |
|---|---|
| http://192.168.1.153:30300 | admin / changeme |

Grafana has Prometheus, Loki, and Tempo pre-wired as datasources. This is the main
interface for querying metrics, browsing logs, and viewing traces. Loki and Tempo
have no standalone UI — use Grafana for everything.

### Prometheus (port-forward required)

```bash
# Run on 192.168.1.153
kubectl port-forward svc/kube-prometheus-stack-prometheus \
  -n observability 9090:9090 --address 0.0.0.0
```

Open: http://192.168.1.153:9090

### Alertmanager (port-forward required)

```bash
kubectl port-forward svc/kube-prometheus-stack-alertmanager \
  -n observability 9093:9093 --address 0.0.0.0
```

Open: http://192.168.1.153:9093

### Loki (API only)

```bash
kubectl port-forward svc/loki -n observability 3100:3100 --address 0.0.0.0
```

Open: http://192.168.1.153:3100

---

## Grafana Setup

### Recommended dashboards

Import via **Dashboards → New → Import → enter ID → Load**

| ID | Description |
|---|---|
| 315 | Kubernetes cluster overview |
| 1860 | Node Exporter Full (host metrics) |
| 15141 | Kubernetes pods / Loki log viewer |

### Cluster filter variable

Add a dashboard variable to switch between clusters:

| Field | Value |
|---|---|
| Name | `cluster` |
| Type | Query |
| Data source | Prometheus |
| Query | `label_values(k8s_node_cpu_usage, k8s_cluster_name)` |

Namespace drill-down variable:
```
label_values(k8s_namespace_name{k8s_cluster_name="$cluster"}, k8s_namespace_name)
```

---

## Installation

### Prerequisites

- Kind cluster running on each machine
- `kubectl`, `helm` installed
- Helm repos added (see commands below)

### Hub (192.168.1.153)

```bash
cd /home/rawhideron/Projects/homelab-observability

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

kubectl create namespace observability

helm upgrade --install loki grafana/loki \
  -n observability --values observability/loki-values.yaml --wait --timeout 5m

helm upgrade --install tempo grafana/tempo \
  -n observability --values observability/tempo-values.yaml --wait --timeout 5m

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n observability --values observability/kube-prometheus-stack-values.yaml --wait --timeout 10m

helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
  -n observability --values observability/otel-collector-gateway-values.yaml --wait --timeout 3m
```

Then configure the iptables DNAT to forward `192.168.1.153:4317` to the gateway NodePort:

```bash
sudo systemctl enable --now otel-forward
```

### Source cluster: jan2026 (192.168.1.230)

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
kubectl create namespace otel-agent --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector \
  -n otel-agent \
  --values observability/otel-collector-agent-values.yaml \
  --set "extraEnvs[0].value=jan2026" --wait --timeout 3m
```

### Source cluster: zephyrus (192.168.1.176)

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
kubectl create namespace otel-agent --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector \
  -n otel-agent \
  --values observability/otel-collector-agent-values.yaml \
  --set "extraEnvs[0].value=zephyrus" --wait --timeout 3m
```

---

## Repository Structure

```
homelab-observability/
├── observability/
│   ├── otel-collector-gateway-values.yaml   # Hub OTel gateway (deployment)
│   ├── otel-collector-agent-values.yaml     # Source cluster agents (DaemonSet)
│   ├── kube-prometheus-stack-values.yaml    # Prometheus + Grafana
│   ├── loki-values.yaml                     # Log storage
│   └── tempo-values.yaml                    # Trace storage
└── docs/
    ├── observability-plan.md                # Original design plan
    └── access-guide.md                      # UI access reference
```

---

## Signals

| Signal | Collector | Storage | Status |
|---|---|---|---|
| Metrics | kubeletstats + hostmetrics receivers | Prometheus | ✅ Flowing — `k8s_cluster_name` label set |
| Logs | filelog receiver (container logs) | Loki | ✅ Flowing — all namespaces |
| Traces | OTLP receiver | Tempo | 🔵 Ready — requires app instrumentation |

> Traces will populate once application services (e.g. `attendees-api`) are instrumented with the OpenTelemetry SDK to emit OTLP spans.

---

## Networking Notes

Kind nodes run as Docker containers on an internal bridge (172.21.x.x), not directly
reachable from other LAN machines. The hub exposes the OTel gateway via:

1. **NodePort 30317** on Kind node `kind-worker2` (172.21.0.5)
2. **iptables DNAT** on the host: `192.168.1.153:4317 → 172.21.0.5:30317`
3. **systemd service** `otel-forward` manages the DNAT rule across reboots
