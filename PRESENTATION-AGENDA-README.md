# Presentation Agenda: Azure Monitor + Managed Grafana + Camunda Metrics

This agenda can be used to present how to implement Azure Monitor managed service with Azure Managed Grafana and integrate Camunda components to ingest metrics into Azure Managed Prometheus.

## 1) Introduction and Outcomes
- What observability problem we are solving
- Target architecture and expected outcomes
- Success criteria for implementation

## 2) Solution Architecture Overview
- AKS cluster, Camunda workloads, and metrics endpoints
- Azure Monitor managed service for Prometheus
- Azure Managed Grafana for visualization
- End-to-end metrics flow from Camunda to dashboards

## 3) Prerequisites and Platform Readiness
- AKS cluster requirements
- Azure Monitor Workspace and Grafana prerequisites
- Required access, RBAC, and networking prerequisites
- Tooling and deployment pipeline readiness

## 4) Provisioning Core Azure Components
- Enabling Azure Monitor managed service for Prometheus on AKS
- Creating and linking Azure Monitor Workspace
- Provisioning Azure Managed Grafana
- Assigning Grafana permissions to query metrics

## 5) Camunda Metrics Enablement
- Enabling Prometheus metrics in Camunda
- Exposing `/actuator/prometheus`
- Validating Camunda metric output

## 6) Scrape Configuration for Camunda
- Creating and applying PodMonitor
- Matching labels, namespace, path, and port naming
- Verifying target discovery and scrape behavior

## 7) Network and Security Controls
- NetworkPolicy required for `ama-metrics` to scrape Camunda
- Namespace/pod selector alignment
- Principle of least privilege for role assignments

## 8) Validation and Verification
- Checking `ama-metrics` pods and logs
- Verifying data ingestion in Azure Prometheus
- Running baseline PromQL queries
- Confirming Grafana data source connectivity

## 9) Dashboard and Alerting Setup
- Creating core Camunda dashboards in Grafana
- Recommended key metrics and visualizations
- Creating alert rules for incidents, failures, and saturation

## 10) Troubleshooting and Operational Runbook
- Common failure points (PodMonitor, network policy, RBAC, endpoint)
- Step-by-step troubleshooting flow
- Escalation path and ownership

## 11) Implementation Plan and Next Steps
- Rollout approach (dev → test → prod)
- Milestones and responsibilities
- Post-implementation review and continuous improvement

## Reference
- Existing implementation guide: [azure-monitoring.md](./azure-monitoring.md)
