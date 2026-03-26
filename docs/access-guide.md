# Observability Stack — Access Guide

## Hub: 192.168.1.153

### Grafana (always accessible)

| URL | Credentials |
|-----|-------------|
| http://192.168.1.153:30300 | admin / changeme |

Grafana is the primary UI for all observability data. Prometheus, Loki, and Tempo
are pre-wired as datasources — use Grafana to query metrics, browse logs, and
view traces. Loki and Tempo have no standalone UI.

### Prometheus (port-forward required)

```bash
# Run on 192.168.1.153
kubectl port-forward svc/kube-prometheus-stack-prometheus \
  -n observability 9090:9090 --address 0.0.0.0
```

Then open: http://192.168.1.153:9090

### Alertmanager (port-forward required)

```bash
kubectl port-forward svc/kube-prometheus-stack-alertmanager \
  -n observability 9093:9093 --address 0.0.0.0
```

Then open: http://192.168.1.153:9093

### Loki (API only — use Grafana instead)

```bash
kubectl port-forward svc/loki -n observability 3100:3100 --address 0.0.0.0
```

Then open: http://192.168.1.153:3100

---

## Grafana — Getting Started

### Suggested dashboard imports

| Dashboard ID | Description |
|---|---|
| 315 | Kubernetes cluster overview |
| 1860 | Node Exporter full (host metrics) |
| 15141 | Kubernetes / Loki log viewer |

Import via: Dashboards → New → Import → enter ID → Load

### Cluster filter variable

To filter dashboards by source cluster, create a variable:

- Name: `cluster`
- Type: Query
- Data source: Prometheus
- Query: `label_values(k8s_node_cpu_usage, k8s_cluster_name)`

This lets you toggle between `jan2026` (192.168.1.230) and `zephyrus` (192.168.1.176).

---

## Source Clusters

| Cluster | Host | Login | ArgoCD UI |
|---|---|---|---|
| jan2026 | 192.168.1.230 | rongoodman | https://goodmanreunion.duckdns.org/argocd |
| zephyrus | 192.168.1.176 | ron-goodman | — |

---

## Architecture Summary

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
