# Presentation Agenda: Azure Monitor + Managed Grafana + Camunda Metrics

This detailed agenda is designed for a technical presentation on implementing Azure Monitor managed service with Azure Managed Grafana and integrating Camunda components to ingest metrics into Azure Managed Prometheus.

## 1) Executive Context and Desired Outcomes
- Current observability gaps and operational pain points
- Why managed observability on Azure (scale, reliability, reduced ops burden)
- Business outcomes: faster incident response, better platform health visibility, SLO tracking
- Technical outcomes: standardised telemetry pipeline, reusable dashboards, actionable alerting

## 2) End-to-End Architecture Walkthrough
- AKS as compute platform for Camunda workloads
- Camunda metrics exposure via Spring Boot Actuator endpoint
- Azure Managed Prometheus data ingestion model
- Azure Monitor Workspace as metrics storage and query backend
- Azure Managed Grafana as presentation and analysis layer
- End-to-end flow: Camunda pod → PodMonitor scrape → ama-metrics agent → Azure Prometheus → Grafana dashboards

## 3) Platform Prerequisites and Governance Readiness
- AKS, Azure Monitor Workspace, and Managed Grafana baseline requirements
- Identity and access model (platform team, app team, read-only consumers)
- RBAC and least-privilege role assignments
- Network prerequisites and policy posture
- Deployment standards (Bicep + Azure DevOps pipeline)
- Environment strategy (dev, non-prod, prod)

## 4) Implementation Blueprint (High-Level Sequence)
- Phase 1: Provision monitoring foundations (workspace + add-on + Grafana)
- Phase 2: Enable Camunda metrics and scrape config
- Phase 3: Validate ingestion and baseline observability
- Phase 4: Build dashboards and alert rules
- Phase 5: Operational handover and runbook formalisation

## 5) Azure Monitor Deep Dive (Managed Prometheus)

### 5.1 Core Components
- Azure Monitor managed service for Prometheus architecture
- `ama-metrics` components and their responsibilities
- Workspace linkage model for AKS clusters

### 5.2 Data Collection Mechanics
- Scrape model and target discovery behavior
- PodMonitor/ServiceMonitor support in Azure Managed Prometheus
- Scrape intervals, relabeling considerations, and cardinality risks

### 5.3 Data Quality and Performance Considerations
- High-cardinality metric impact and cost/performance trade-offs
- Metric naming and label strategy for Camunda workloads
- Retention and query behavior expectations

### 5.4 Operational Validation
- Health checks for `ama-metrics` pods
- Verifying ingestion using `up` and workload-specific PromQL
- What to verify before moving from pilot to production

## 6) Azure Managed Grafana Deep Dive

### 6.1 Integration Model
- How Grafana connects to Azure Monitor Workspace
- Data source authentication and managed identity permissions
- Multi-environment organization and folder strategy

### 6.2 Dashboard Design Standards
- Executive vs operational dashboard personas
- Golden signals and domain-specific Camunda KPIs
- Dashboard structuring patterns (summary, drill-down, service view)

### 6.3 Alerting Integration
- Alert rule ownership model (platform vs application team)
- Threshold-based and trend-based alert patterns
- Routing strategy (Teams, email, pager/on-call tooling)

## 7) Camunda Metrics Integration Deep Dive

### 7.1 Application Instrumentation
- Enabling Prometheus export via environment variables
- Endpoint exposure: `/actuator/prometheus`
- Verifying expected Camunda and JVM metrics categories

### 7.2 Scrape Target Modeling
- Pod label design for reliable target discovery
- PodMonitor selectors, namespace scope, and endpoint definitions
- Port naming alignment between workload and PodMonitor

### 7.3 Domain Metrics Mapping
- Which Camunda metrics matter for operations and capacity planning
- Process, incident, task, and job execution metric interpretation
- Translating technical metrics into business-facing health indicators

## 8) Security, Network, and Compliance Considerations
- NetworkPolicy model for controlled `ama-metrics` access
- Namespace and pod selector hardening
- RBAC boundaries and separation of duties
- Auditability of infrastructure changes through pipeline deployments
- Data governance expectations for observability telemetry

## 9) Validation, Test Scenarios, and Demonstration Flow

### 9.1 Validation Checklist
- Add-on enabled and pods healthy
- PodMonitor detected and scraping
- Metrics visible in Prometheus Explorer
- Grafana data source connected and queryable

### 9.2 Suggested Live Demo Sequence
- Show architecture and deployment status
- Validate Camunda endpoint output
- Run PromQL query for Camunda metrics
- Open dashboard and walk through panel interpretation
- Trigger/illustrate an alert scenario and response workflow

## 10) Troubleshooting Deep Dive
- Structured troubleshooting path from source endpoint to visualization
- Common failure domains:
  - Metrics endpoint unavailable
  - PodMonitor mismatch
  - NetworkPolicy blocking scrape traffic
  - Identity or workspace linkage issues
  - Grafana data source permissions/configuration
- Use the existing troubleshooting guide for investigation steps:
  - [azure-monitoring.md](./azure-monitoring.md#troubleshooting)

## 11) Operating Model and Team Responsibilities
- Platform team responsibilities (foundation, guardrails, platform observability)
- Application team responsibilities (workload metrics, dashboard ownership, alert tuning)
- SRE/Operations responsibilities (incident response, runbooks, SLO review)
- Cadence for alert tuning and dashboard quality review

## 12) Rollout Strategy, Risks, and Next Steps
- Rollout approach: pilot → staged adoption → production standard
- Known risks: cardinality growth, alert noise, ownership gaps
- Mitigations: metric governance, dashboard standards, runbook maturity
- Next steps:
  - Finalize environment onboarding checklist
  - Define KPI and SLO catalog
  - Establish monthly observability review forum

## Presentation Artifacts Checklist
- Architecture slide (current vs target state)
- Implementation sequence slide
- Azure Monitor deep-dive slide set
- Grafana dashboard screenshots or live environment links
- Troubleshooting decision tree
- Ownership and rollout plan slide

## Reference
- Existing implementation guide: [azure-monitoring.md](./azure-monitoring.md)
- Azure Monitor troubleshooting: [Prometheus metrics troubleshoot guide](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/prometheus-metrics-troubleshoot)
