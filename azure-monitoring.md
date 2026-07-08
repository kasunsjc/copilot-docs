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
7. [Network Policy Configuration](#network-policy-configuration)
8. [Linking Grafana to Azure Monitor](#linking-grafana-to-azure-monitor)
9. [Dashboards](#dashboards)
10. [Alerting](#alerting)
11. [Troubleshooting](#troubleshooting)
12. [References](#references)

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
| AKS Cluster | Running with the Azure Monitor add-on enabled (provisioned via Bicep) |
| Bicep | Infrastructure-as-code templates for all Azure resources |
| Azure DevOps Pipeline | CI/CD pipeline used to deploy Bicep templates and Kubernetes manifests |
| kubectl | Configured to target the AKS cluster |
| Azure Monitor Workspace | Created and linked to AKS via Bicep |
| Camunda | Deployed with Prometheus metrics enabled via environment variables |
| Prometheus Operator CRDs | Installed in the cluster (required for PodMonitor) |

---

## Azure Managed Prometheus Setup

Azure Managed Prometheus is provided as part of the **Azure Monitor managed service for Prometheus**. It integrates directly with AKS via the Azure Monitor metrics add-on.

### 1. Provision via Bicep and Azure DevOps Pipeline

The Azure Monitor metrics add-on and the associated Azure Monitor Workspace are provisioned through the **Bicep templates** deployed by the **Azure DevOps pipeline**. The key Bicep configuration is the `azureMonitorProfile` property on the `managedCluster` resource:

```bicep
resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-07-01' = {
  // ...
  properties: {
    azureMonitorProfile: {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricLabelsAllowlist: ''
          metricAnnotationsAllowList: ''
        }
      }
    }
  }
}
```

The Azure Monitor Workspace is created as a separate Bicep resource and its resource ID is passed into the cluster configuration:

```bicep
resource monitorWorkspace 'microsoft.monitor/accounts@2023-04-03' = {
  name: monitorWorkspaceName
  location: location
}
```

Deploy these resources by triggering the **Azure DevOps pipeline** for the infrastructure stage. Refer to the pipeline definition in the repository for the exact stage and variable names.

### 2. Verify the Add-on is Running

After deployment, confirm the monitoring agent pods are running:

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

### 1. Provision via Bicep and Azure DevOps Pipeline

The Azure Managed Grafana instance, its link to the Azure Monitor Workspace, and all required RBAC role assignments are provisioned through the **Bicep templates** deployed by the **Azure DevOps pipeline**:

```bicep
resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: grafanaName
  location: location
  sku: {
    name: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: monitorWorkspace.id
        }
      ]
    }
  }
}

// Grant the Grafana managed identity Monitoring Reader on the Azure Monitor Workspace
resource grafanaMonitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(monitorWorkspace.id, grafana.id, monitoringReaderRoleId)
  scope: monitorWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRoleId)
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
```

Deploy these resources by triggering the **Azure DevOps pipeline** infrastructure stage.

### 2. Verify the Grafana Data Source

After deployment, confirm the Azure Monitor data source is connected:

1. Navigate to your **Azure Managed Grafana** instance.
2. Go to **Configuration → Data Sources**.
3. Confirm **Azure Monitor** is listed and shows a green **Connected** status.

---

## Camunda Metrics Integration

Camunda's Spring Boot-based engine exposes Prometheus metrics via the Spring Boot Actuator. No code changes are required — metrics are enabled through environment variables set on the Kubernetes deployment.

### 1. Configure Prometheus via Environment Variables

Set the following environment variables on your Camunda deployment (e.g. in your Kubernetes `Deployment` or `StatefulSet`):

```yaml
env:
  - name: MANAGEMENT_ENDPOINT_PROMETHEUS_ACCESS
    value: "unrestricted"
  - name: MANAGEMENT_PROMETHEUS_METRICS_EXPORT_ENABLED
    value: "true"
```

> These correspond to the Spring Boot properties `management.endpoint.prometheus.access` and `management.prometheus.metrics.export.enabled` as documented in the [Camunda Self-Managed Metrics guide](https://docs.camunda.io/docs/self-managed/operational-guides/monitoring/metrics/).

### 2. Accessing the Metrics Endpoint

Since Camunda pods are not exposed externally, use `kubectl port-forward` to verify the metrics endpoint locally:

```bash
# Forward the Camunda pod's HTTP port to localhost
kubectl port-forward pod/<CAMUNDA_POD_NAME> 8080:8080 -n <CAMUNDA_NAMESPACE>
```

Then in a separate terminal:

```bash
curl http://localhost:8080/actuator/prometheus
```

You should see a plain-text list of metrics in the Prometheus exposition format. Look for entries beginning with `camunda_` to confirm Camunda-specific metrics are being exposed.

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

## Network Policy Configuration

Kubernetes `NetworkPolicy` resources are used to restrict pod-to-pod traffic in the cluster. To allow the Azure Monitor metrics agent (`ama-metrics`) running in the `kube-system` namespace to scrape Camunda pods, a `NetworkPolicy` must explicitly permit that ingress traffic.

### NetworkPolicy YAML

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: camunda-allow-ama-metrics-scraping
  namespace: <CAMUNDA_NAMESPACE>
spec:
  podSelector:
    matchLabels:
      app: camunda          # Selects all Camunda component pods
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              rsName: ama-metrics   # Label present on the ama-metrics agent pods
      ports:
        - protocol: TCP
          port: 8080                # The port on which /actuator/prometheus is served
```

> **Note:** The `namespaceSelector` and `podSelector` are combined with an AND condition (both must match). This ensures only the `ama-metrics` pods in `kube-system` are granted access — not all pods in `kube-system`.

### Apply the NetworkPolicy

The `NetworkPolicy` is deployed as part of the Kubernetes manifests via the **Azure DevOps pipeline**:

```bash
kubectl apply -f camunda-allow-ama-metrics-scraping.yaml
```

### Verify the Policy

Confirm the policy has been applied and check the labels on the `ama-metrics` pods match:

```bash
kubectl get networkpolicy camunda-allow-ama-metrics-scraping -n <CAMUNDA_NAMESPACE>
kubectl get pods -n kube-system -l rsName=ama-metrics --show-labels
```

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

### Metrics Not Generating

Use this step-by-step guide when metrics are not appearing in Azure Monitor or Grafana. Work through each section in order — most issues are caught in the first few steps.

> **Reference:** [Troubleshoot collection of Prometheus metrics in Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/prometheus-metrics-troubleshoot)

#### Step 1 — Verify the Azure Monitor Metrics Add-on is Enabled

Confirm the add-on is active on your AKS cluster:

```bash
az aks show \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --query "azureMonitorProfile.metrics.enabled"
```

The output should be `true`. If it is `false` or `null`, re-run the Bicep deployment via the **Azure DevOps pipeline** to re-enable the add-on.

#### Step 2 — Check the ama-metrics Pods are Running

```bash
kubectl get pods -n kube-system | grep ama-metrics
```

Expected output includes the following pods in `Running` state:

| Pod | Purpose |
|---|---|
| `ama-metrics-*` | Main Prometheus scraping agent |
| `ama-metrics-node-*` | Per-node metrics collector |
| `ama-metrics-ksm-*` | kube-state-metrics sidecar |

If any pods are in `CrashLoopBackOff`, `Pending`, or `Error` state, check the logs:

```bash
kubectl logs -n kube-system <AMA_METRICS_POD_NAME> --previous
kubectl describe pod -n kube-system <AMA_METRICS_POD_NAME>
```

Common causes of pod failure:
- Insufficient node resources — check node capacity with `kubectl describe node`.
- Missing or revoked managed identity permissions on the Azure Monitor Workspace.

#### Step 3 — Verify the Azure Monitor Workspace Linkage

1. In the Azure Portal, navigate to your **AKS cluster → Insights → Monitor settings**.
2. Confirm an **Azure Monitor Workspace** is shown as linked.
3. Alternatively, inspect the Bicep-deployed resource:

```bash
az aks show \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --query "azureMonitorProfile"
```

If no workspace is linked, re-trigger the infrastructure stage of the **Azure DevOps pipeline** to reapply the Bicep templates.

#### Step 4 — Check Prometheus Operator CRDs are Installed

Azure Managed Prometheus relies on Custom Resource Definitions (CRDs) for `PodMonitor` and `ServiceMonitor`:

```bash
kubectl get crd | grep -E "podmonitor|servicemonitor"
```

You should see output similar to:

```
podmonitors.azmonitoring.coreos.com
servicemonitors.azmonitoring.coreos.com
```

If the CRDs are missing, the metrics add-on pods may not have installed correctly. Re-deploy the add-on by re-running the Azure DevOps pipeline.

#### Step 5 — Validate the PodMonitor Configuration

Verify the `PodMonitor` exists in the correct namespace:

```bash
kubectl get podmonitor -n <CAMUNDA_NAMESPACE>
```

Inspect its configuration:

```bash
kubectl describe podmonitor camunda-podmonitor -n <CAMUNDA_NAMESPACE>
```

Check the following:

| Field | What to verify |
|---|---|
| `spec.selector.matchLabels` | Labels must exactly match labels on Camunda pods |
| `podMetricsEndpoints[].port` | Must match a **named** port in the pod spec (not just a number) |
| `podMetricsEndpoints[].path` | Should be `/actuator/prometheus` |
| `namespaceSelector.matchNames` | Must include the namespace where Camunda pods run |
| `apiVersion` | Should be `azmonitoring.coreos.com/v1` for Azure Managed Prometheus |

Cross-check pod labels:

```bash
kubectl get pods -n <CAMUNDA_NAMESPACE> --show-labels
```

#### Step 6 — Check the Network Policy Allows Scraping

If `NetworkPolicy` resources are active in the cluster, ingress from the `ama-metrics` agent must be explicitly allowed. Verify the policy is in place:

```bash
kubectl get networkpolicy camunda-allow-ama-metrics-scraping -n <CAMUNDA_NAMESPACE>
```

Confirm the `ama-metrics` agent pods carry the expected label:

```bash
kubectl get pods -n kube-system -l rsName=ama-metrics --show-labels
```

If the label has changed, update the `NetworkPolicy` selector accordingly. See the [Network Policy Configuration](#network-policy-configuration) section for the full manifest.

You can also do a quick connectivity test by running `curl` from within an `ama-metrics` pod:

```bash
kubectl exec -it -n kube-system <AMA_METRICS_POD_NAME> -- \
  curl http://<CAMUNDA_POD_IP>:8080/actuator/prometheus
```

#### Step 7 — Inspect the ama-metrics Agent Scrape Logs

Look for scrape errors or target discovery issues in the agent logs:

```bash
# Tail the main agent log
kubectl logs -n kube-system -l app=ama-metrics --tail=200

# Filter for errors
kubectl logs -n kube-system -l app=ama-metrics --tail=500 | grep -i "error\|fail\|warn\|camunda"
```

Key log messages to look for:

| Log message | Likely cause |
|---|---|
| `connection refused` | Camunda pod not listening on the expected port |
| `context deadline exceeded` | Network policy blocking scrape traffic |
| `no such host` | DNS resolution failure for the pod |
| `TLS handshake error` | Scheme mismatch (`https` used when pod expects `http`) |
| `podmonitor … not found` | CRD not installed or wrong `apiVersion` |

#### Step 8 — Verify the Camunda Metrics Endpoint

Confirm Camunda is actively exposing metrics:

```bash
# Port-forward the pod locally
kubectl port-forward pod/<CAMUNDA_POD_NAME> 8080:8080 -n <CAMUNDA_NAMESPACE>

# In a separate terminal
curl http://localhost:8080/actuator/prometheus | head -20
```

If the endpoint returns an error or is empty:
- Confirm the environment variables `MANAGEMENT_ENDPOINT_PROMETHEUS_ACCESS=unrestricted` and `MANAGEMENT_PROMETHEUS_METRICS_EXPORT_ENABLED=true` are set (see [Camunda Metrics Integration](#camunda-metrics-integration)).
- Check Camunda pod logs for Spring Boot startup errors:

```bash
kubectl logs <CAMUNDA_POD_NAME> -n <CAMUNDA_NAMESPACE> | grep -i "actuator\|prometheus\|error"
```

#### Step 9 — Confirm Metrics Arriving in the Azure Monitor Workspace

Use the **Prometheus query interface** in the Azure Portal to check whether any metrics have been ingested:

1. Navigate to **Azure Monitor → Managed Prometheus → \<Your Workspace\> → Prometheus Explorer**.
2. Run a simple query to check for any metric:
   ```promql
   up
   ```
3. Run a Camunda-specific query:
   ```promql
   camunda_process_instance_running
   ```

If `up` returns data but Camunda metrics do not, the scrape target is reachable but the PodMonitor selector or path is misconfigured — revisit Step 5.

If `up` returns no data at all, the agent is not scraping any targets — revisit Steps 2–4.

#### Step 10 — Review the ama-metrics ConfigMap

Azure Managed Prometheus uses a `ConfigMap` to control scrape configuration and feature flags. Inspect it for any overrides that may suppress scraping:

```bash
kubectl get configmap -n kube-system | grep ama-metrics
kubectl describe configmap ama-metrics-settings-configmap -n kube-system
```

Ensure custom scraping is enabled if you have overridden the default `ConfigMap`:

```yaml
schema-version: v1
default-scrape-settings-enabled: true
pod-annotation-based-scraping: false   # set to true if using pod annotations
```

> **Note:** If `default-scrape-settings-enabled` is set to `false`, the agent will not automatically discover `PodMonitor` or `ServiceMonitor` resources.

---

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
- [Camunda Self-Managed Metrics guide](https://docs.camunda.io/docs/self-managed/operational-guides/monitoring/metrics/)
- [Bicep – AKS Azure Monitor Profile](https://learn.microsoft.com/en-us/azure/templates/microsoft.containerservice/managedclusters)
- [Bicep – Azure Managed Grafana](https://learn.microsoft.com/en-us/azure/templates/microsoft.dashboard/grafana)
- [Azure DevOps Pipelines documentation](https://learn.microsoft.com/en-us/azure/devops/pipelines/)
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Troubleshoot collection of Prometheus metrics in Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/prometheus-metrics-troubleshoot)
