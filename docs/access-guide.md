# Observability Stack — Access Guide

## Hub: 192.168.1.153

### Grafana (always accessible)

| URL | Credentials |
|-----|-------------|
| http://192.168.1.153:30300 | admin / changeme |

Grafana is the primary UI for all observability data. Prometheus, Loki, and Tempo
are pre-wired as datasources. Loki and Tempo have no standalone UI.

### Prometheus (always accessible)

| URL | Notes |
|-----|-------|
| http://192.168.1.153:9090 | NodePort 30900 |

### Alertmanager (always accessible)

| URL | Notes |
|-----|-------|
| http://192.168.1.153:9093 | NodePort 30903 |

### Loki (API only — use Grafana instead)

```bash
kubectl port-forward svc/loki -n observability 3100:3100 --address 0.0.0.0
```

Then open: http://192.168.1.153:3100

---

## Networking Notes (Kind-specific)

Kind nodes run as Docker containers on an internal bridge (172.21.x.x). NodePorts
are accessible from within the cluster using the node container IPs:

| Node | IP | Services |
|---|---|---|
| kind-worker | 172.21.0.3 | Prometheus (30900), Alertmanager (30903) |
| kind-worker2 | 172.21.0.5 | OTel Gateway (30317), Grafana (30300) |
| kind-worker3 | 172.21.0.2 | — |

Cross-node pod-to-pod networking (CNI) is not fully functional in this setup.
Datasources use NodePort or ClusterIP-routed endpoints to work around this.

---

## Grafana — Getting Started

### Datasource status

| Datasource | URL | Status |
|---|---|---|
| Prometheus | http://172.21.0.3:30900 | ✅ Connected |
| Loki | http://loki.observability.svc.cluster.local:3100 | ✅ Connected |
| Tempo | http://tempo.observability.svc.cluster.local:3200 | ✅ Connected |

### Suggested dashboard imports

| Dashboard ID | Description |
|---|---|
| 315 | Kubernetes cluster overview |
| 1860 | Node Exporter Full (host metrics) |
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
