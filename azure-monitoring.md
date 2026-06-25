# Azure Managed Prometheus, Managed Grafana & Camunda Monitoring

## Overview

This document describes the observability setup for our Kubernetes-based environment using **Azure Managed Prometheus**, **Azure Managed Grafana**, and **Camunda BPM** metrics integration via **PodMonitor**. The goal is to provide a centralised, scalable monitoring solution that collects, stores, and visualises metrics from both infrastructure and application layers.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Azure Managed Prometheus Setup](#azure-managed-prometheus-setup)
4. [Azure Managed Grafana Setup](#azure-managed-grafana-setup)
5. [Camunda Metrics Integration](#camunda-metrics-integration)
6. [PodMonitor Configuration](#podmonitor-configuration)
7. [Linking Grafana to Azure Monitor](#linking-grafana-to-azure-monitor)
8. [Dashboards](#dashboards)
9. [Alerting](#alerting)
10. [Troubleshooting](#troubleshooting)
11. [References](#references)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      AKS Cluster                            │
│                                                             │
│  ┌──────────────┐     PodMonitor     ┌──────────────────┐  │
│  │   Camunda    │ ──────────────────▶│  Prometheus       │  │
│  │   Pods       │   /actuator/       │  (Azure Managed)  │  │
│  │  (metrics    │    prometheus      │                   │  │
│  │   endpoint)  │                    └────────┬─────────┘  │
│  └──────────────┘                             │             │
│                                               │ Remote Write │
└───────────────────────────────────────────────┼─────────────┘
                                                ▼
                                   ┌────────────────────────┐
                                   │   Azure Monitor        │
                                   │   (Metrics Store)      │
                                   └────────────┬───────────┘
                                                │
                                                ▼
                                   ┌────────────────────────┐
                                   │  Azure Managed Grafana │
                                   │  (Visualisation)       │
                                   └────────────────────────┘
```

**Flow Summary:**
- Camunda pods expose metrics on the `/actuator/prometheus` endpoint.
- A `PodMonitor` resource instructs the Azure Managed Prometheus agent to scrape those pods.
- Scraped metrics are stored in **Azure Monitor** (via the managed Prometheus workspace).
- **Azure Managed Grafana** queries Azure Monitor as a data source and visualises the metrics via dashboards.

---

## Prerequisites

Before setting up the monitoring stack, ensure the following are in place:

| Requirement | Details |
|---|---|
| AKS Cluster | Running with the Azure Monitor add-on enabled |
| Azure CLI | Version 2.48.0 or later |
| kubectl | Configured to target the AKS cluster |
| Helm | Version 3.x |
| Azure Monitor Workspace | Created in the same or linked subscription |
| Camunda | Deployed with Spring Boot Actuator and Prometheus metrics enabled |
| Prometheus Operator CRDs | Installed in the cluster (required for PodMonitor) |

---

## Azure Managed Prometheus Setup

Azure Managed Prometheus is provided as part of the **Azure Monitor managed service for Prometheus**. It integrates directly with AKS using the Azure Monitor metrics add-on.

### 1. Enable the Azure Monitor Metrics Add-on on AKS

```bash
az aks update \
  --resource-group <RESOURCE_GROUP> \
  --name <AKS_CLUSTER_NAME> \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id <AZURE_MONITOR_WORKSPACE_RESOURCE_ID>
```

> **Note:** Replace `<RESOURCE_GROUP>`, `<AKS_CLUSTER_NAME>`, and `<AZURE_MONITOR_WORKSPACE_RESOURCE_ID>` with your actual values.

### 2. Verify the Add-on is Running

The add-on deploys the following components in the `kube-system` and `monitoring` namespaces:

```bash
kubectl get pods -n kube-system | grep ama-metrics
kubectl get pods -n monitoring
```

You should see pods such as:
- `ama-metrics-*` — the Prometheus scraping agent
- `ama-metrics-node-*` — node-level metrics collector

### 3. Verify the Azure Monitor Workspace

In the Azure Portal, navigate to:

**Azure Monitor → Managed Prometheus → \<Your Workspace\>**

Confirm that the workspace is active and linked to your AKS cluster.

---

## Azure Managed Grafana Setup

### 1. Create an Azure Managed Grafana Instance

```bash
az grafana create \
  --name <GRAFANA_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --location <LOCATION>
```

### 2. Link Grafana to the Azure Monitor Workspace

```bash
az grafana update \
  --name <GRAFANA_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --integrations "{\"azureMonitorWorkspaceIntegrations\": [{\"azureMonitorWorkspaceResourceId\": \"<AZURE_MONITOR_WORKSPACE_RESOURCE_ID>\"}]}"
```

Alternatively, in the Azure Portal:

1. Navigate to your **Azure Managed Grafana** instance.
2. Go to **Configuration → Data Sources**.
3. Confirm **Azure Monitor** is listed and connected.

### 3. Assign Roles

Ensure the Managed Grafana instance has the **Monitoring Reader** role on the Azure Monitor Workspace:

```bash
az role assignment create \
  --assignee <GRAFANA_MANAGED_IDENTITY_PRINCIPAL_ID> \
  --role "Monitoring Reader" \
  --scope <AZURE_MONITOR_WORKSPACE_RESOURCE_ID>
```

---

## Camunda Metrics Integration

Camunda's Spring Boot-based engine can expose Prometheus metrics via the Spring Boot Actuator.

### 1. Enable Prometheus Metrics in Camunda

Add the following dependencies to your `pom.xml`:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

### 2. Configure Prometheus via Environment Variables

Set the following environment variables on your Camunda deployment (e.g. in your Kubernetes `Deployment` or `StatefulSet`):

```yaml
env:
  - name: MANAGEMENT_ENDPOINT_PROMETHEUS_ACCESS
    value: "unrestricted"
  - name: MANAGEMENT_PROMETHEUS_METRICS_EXPORT_ENABLED
    value: "true"
```

> These correspond to the Spring Boot properties `management.endpoint.prometheus.access` and `management.prometheus.metrics.export.enabled` as documented in the [Camunda Self-Managed Metrics guide](https://docs.camunda.io/docs/self-managed/operational-guides/monitoring/metrics/).

### 3. Key Camunda Metrics Available

Once configured, the following metric categories are exposed:

| Metric | Description |
|---|---|
| `camunda.job.execution.active` | Number of actively executing jobs |
| `camunda.process.instance.running` | Running process instances count |
| `camunda.task.instance.open` | Open user tasks |
| `camunda.incident.open` | Open incidents |
| `camunda.bpmn.execution.time` | BPMN execution duration |
| `jvm_memory_used_bytes` | JVM memory usage |
| `http_server_requests_seconds` | HTTP request latency |

> Verify metrics are available by hitting the endpoint directly:
> ```
> curl http://<CAMUNDA_POD_IP>:8080/actuator/prometheus
> ```

---

## PodMonitor Configuration

A `PodMonitor` custom resource tells the Azure Managed Prometheus agent which pods to scrape and how.

### PodMonitor YAML

```yaml
apiVersion: azmonitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: camunda-podmonitor
  namespace: <CAMUNDA_NAMESPACE>
  labels:
    app: camunda
    release: prometheus
spec:
  selector:
    matchLabels:
      app: camunda           # Must match the labels on your Camunda pods
  namespaceSelector:
    matchNames:
      - <CAMUNDA_NAMESPACE>
  podMetricsEndpoints:
    - port: http             # The named port on the Camunda pod/container
      path: /actuator/prometheus
      interval: 30s          # Scrape every 30 seconds
      scheme: http
      honorLabels: true
```

> **Important:** The `apiVersion` `azmonitoring.coreos.com/v1` is used for Azure Managed Prometheus. If you are using the standard Prometheus Operator, use `monitoring.coreos.com/v1` instead.

### Apply the PodMonitor

```bash
kubectl apply -f camunda-podmonitor.yaml
```

### Verify Scraping

Check the Azure Monitor metrics agent logs to confirm it is scraping the Camunda pods:

```bash
kubectl logs -n kube-system -l app=ama-metrics --tail=100 | grep camunda
```

You can also query metrics in the Azure Monitor Workspace using **Metrics Explorer** or the **Prometheus query interface**.

---

## Linking Grafana to Azure Monitor

Azure Managed Grafana is automatically pre-configured with **Azure Monitor** as a data source when linked during setup. To query Prometheus metrics:

1. Open your **Azure Managed Grafana** URL.
2. Navigate to **Explore**.
3. Select the **Azure Monitor** data source.
4. Choose **Prometheus Metrics** as the metric namespace.
5. Run a PromQL query, for example:

```promql
camunda_process_instance_running
```

---

## Dashboards

### Importing Pre-built Dashboards

You can import community or custom dashboards into Azure Managed Grafana:

1. In Grafana, go to **Dashboards → Import**.
2. Upload a JSON dashboard file or enter a Grafana.com Dashboard ID.

### Recommended Dashboards

| Dashboard | Description |
|---|---|
| Camunda BPM Overview | Process instances, incidents, and job metrics |
| JVM Micrometer | JVM heap, GC, threads |
| Kubernetes Pod Metrics | Pod CPU, memory, restarts |
| AKS Cluster Overview | Node-level resource usage |

### Sample PromQL Queries for Camunda Dashboard Panels

```promql
# Active process instances
camunda_process_instance_running

# Open incidents
camunda_incident_open

# Job execution failures (rate over 5 minutes)
rate(camunda_job_execution_failed_total[5m])

# HTTP request latency (p99)
histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[5m]))
```

---

## Alerting

### Creating Alerts via Azure Monitor

1. Navigate to **Azure Monitor → Alerts → Create Alert Rule**.
2. Set the **Scope** to your Azure Monitor Workspace.
3. Choose **Prometheus metrics** as the signal type.
4. Define your PromQL condition, for example:

```promql
camunda_incident_open > 5
```

5. Set the **Action Group** to notify via email, Teams, PagerDuty, etc.

### Example Alert Rules

| Alert | Condition | Severity |
|---|---|---|
| High Incident Count | `camunda_incident_open > 10` | Critical |
| Job Execution Failures | `rate(camunda_job_execution_failed_total[5m]) > 0.5` | Warning |
| High Memory Usage | `jvm_memory_used_bytes / jvm_memory_max_bytes > 0.85` | Warning |
| Pod Restart Loop | `kube_pod_container_status_restarts_total > 5` | Critical |

---

## Troubleshooting

### PodMonitor Not Scraping Pods

- **Check labels:** Ensure the `matchLabels` in the `PodMonitor` exactly match the labels on your Camunda pods.
  ```bash
  kubectl get pods -n <CAMUNDA_NAMESPACE> --show-labels
  ```
- **Check port name:** The `port` field in `podMetricsEndpoints` must match a **named port** in the pod spec, not just a port number.
- **Check namespace:** Ensure `namespaceSelector` includes the correct namespace.

### Metrics Not Appearing in Azure Monitor

- Verify the `ama-metrics` pods are running:
  ```bash
  kubectl get pods -n kube-system | grep ama-metrics
  ```
- Check agent logs for errors:
  ```bash
  kubectl logs -n kube-system <AMA_METRICS_POD_NAME>
  ```
- Ensure the Azure Monitor Workspace is linked to the AKS cluster.

### Grafana Cannot Query Metrics

- Confirm the Grafana managed identity has **Monitoring Reader** role on the Azure Monitor Workspace.
- Verify the Azure Monitor data source is configured correctly in Grafana under **Configuration → Data Sources**.
- Test connectivity using the **Save & Test** button on the data source configuration page.

### Camunda Metrics Endpoint Not Accessible

- Confirm the Actuator endpoint is exposed:
  ```bash
  kubectl exec -it <CAMUNDA_POD> -n <NAMESPACE> -- curl http://localhost:8080/actuator/prometheus
  ```
- Ensure the pod's container port is named and matches the `PodMonitor` port reference.

---

## References

- [Azure Monitor managed service for Prometheus](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-metrics-overview)
- [Azure Managed Grafana documentation](https://learn.microsoft.com/en-us/azure/managed-grafana/overview)
- [Enable Prometheus metrics on AKS](https://learn.microsoft.com/en-us/azure/aks/monitor-aks)
- [Prometheus PodMonitor CRD](https://prometheus-operator.dev/docs/operator/api/#monitoring.coreos.com/v1.PodMonitor)
- [Camunda Metrics with Micrometer](https://docs.camunda.org/manual/latest/user-guide/process-engine/metrics/)
- [Spring Boot Actuator - Prometheus](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html#actuator.metrics.export.prometheus)
