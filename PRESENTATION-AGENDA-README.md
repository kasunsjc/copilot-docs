# Presentation Agenda: Azure Monitor + Managed Grafana + Camunda Metrics

**Total Duration:** 45 minutes  
**Format:** Technical presentation with live demo  
**Audience:** Platform engineers, DevOps teams, and technical leads

> **Timing guide:** Each section shows the recommended duration and cumulative clock position so you can track pace during delivery.

---

## 1) Executive Context and Desired Outcomes
⏱ **5 min** | 🕐 *0:00 – 0:05*

- Current observability gaps and operational pain points
- Why managed observability on Azure (scale, reliability, reduced ops burden)
- Business outcomes: faster incident response, better platform health visibility, SLO tracking
- Technical outcomes: standardised telemetry pipeline, reusable dashboards, actionable alerting

> **Speaker note:** Keep this audience-relevant and brief. Frame the problem before showing any technology. Reference a real pain point your team has experienced (e.g. "we couldn't tell if Camunda process execution was degraded without manually checking pods").

---

## 2) End-to-End Architecture Walkthrough
⏱ **5 min** | 🕐 *0:05 – 0:10*

- AKS as compute platform for Camunda workloads
- Camunda metrics exposure via Spring Boot Actuator endpoint
- Azure Managed Prometheus data ingestion model
- Azure Monitor Workspace as metrics storage and query backend
- Azure Managed Grafana as presentation and analysis layer
- End-to-end flow: Camunda pod → PodMonitor scrape → `ama-metrics` agent → Azure Prometheus → Grafana dashboards

> **Speaker note:** Use the architecture diagram from `azure-monitoring.md` here. Walk left-to-right so the audience follows data flow naturally. Pause on the "Remote Write" step — many engineers don't realise the agent writes to Azure Monitor rather than hosting Prometheus themselves.

---

## 3) Platform Prerequisites and Governance Readiness
⏱ **3 min** | 🕐 *0:10 – 0:13*

- AKS, Azure Monitor Workspace, and Managed Grafana baseline requirements
- Identity and access model (platform team, app team, read-only consumers)
- RBAC and least-privilege role assignments
- Network prerequisites and policy posture
- Deployment standards (Bicep + Azure DevOps pipeline)
- Environment strategy (dev, non-prod, prod)

> **Speaker note:** Emphasise that all infrastructure is provisioned via Bicep through Azure DevOps — not ad-hoc `az` commands. This is important for consistency and auditability.

---

## 4) Implementation Blueprint (High-Level Sequence)
⏱ **2 min** | 🕐 *0:13 – 0:15*

- Phase 1: Provision monitoring foundations (workspace + add-on + Grafana)
- Phase 2: Enable Camunda metrics and scrape config
- Phase 3: Validate ingestion and baseline observability
- Phase 4: Build dashboards and alert rules
- Phase 5: Operational handover and runbook formalisation

> **Speaker note:** This is your "roadmap slide" moment. Keep it quick — just enough so the audience knows what's coming and why the order matters.

---

## 5) Azure Monitor Deep Dive (Managed Prometheus)
⏱ **9 min** | 🕐 *0:15 – 0:24*

### 5.1 Core Components *(2 min)*
- Azure Monitor managed service for Prometheus architecture
- `ama-metrics` pod roles: main agent, node collector, kube-state-metrics sidecar
- Workspace linkage model for AKS clusters and how Bicep wires them together

### 5.2 Data Collection Mechanics *(3 min)*
- Scrape model and target discovery via PodMonitor/ServiceMonitor CRDs
- `apiVersion: azmonitoring.coreos.com/v1` vs standard `monitoring.coreos.com/v1`
- Scrape intervals, relabeling considerations, and cardinality risks to plan for

### 5.3 Data Quality and Performance Considerations *(2 min)*
- High-cardinality metric impact and cost/performance trade-offs
- Metric naming and label strategy for Camunda workloads
- Retention and query behaviour expectations in Azure Monitor Workspace

### 5.4 Operational Validation *(2 min)*
- Health checks: confirming `ama-metrics` pods are in `Running` state
- Verifying ingestion using the `up` metric and workload-specific PromQL
- What to check before promoting from pilot to production

> **Speaker note:** Section 5.2 is the most technical. Slow down here and be ready for questions on "why not self-hosted Prometheus?". Key answer: zero infrastructure management, automatic retention, and native Azure RBAC integration.

---

## 6) Azure Managed Grafana Deep Dive
⏱ **6 min** | 🕐 *0:24 – 0:30*

### 6.1 Integration Model *(2 min)*
- How Grafana connects to Azure Monitor Workspace via managed identity
- Data source authentication and the Monitoring Reader role assignment
- Multi-environment organisation: folder strategy and access tiers

### 6.2 Dashboard Design Standards *(2 min)*
- Executive vs operational dashboard personas and their different needs
- Golden signals (latency, traffic, errors, saturation) applied to Camunda
- Dashboard structuring patterns: summary overview → service drill-down → pod-level detail

### 6.3 Alerting Integration *(2 min)*
- Alert rule ownership model: platform (infra saturation) vs application team (Camunda SLOs)
- Threshold-based and trend-based (rate-of-change) alert patterns
- Routing strategy: Teams channel, email, pager / on-call tooling

> **Speaker note:** Use a live Grafana screenshot or demo environment here if available. The dashboard section resonates most with non-technical stakeholders — this is a good moment to show concrete value.

---

## 7) Camunda Metrics Integration Deep Dive
⏱ **5 min** | 🕐 *0:30 – 0:35*

### 7.1 Application Instrumentation *(1 min)*
- Enabling Prometheus export via `MANAGEMENT_PROMETHEUS_METRICS_EXPORT_ENABLED=true`
- Endpoint exposure at `/actuator/prometheus` — no code changes required
- Verifying expected Camunda and JVM metric categories in output

### 7.2 Scrape Target Modeling *(2 min)*
- Pod label design for reliable target discovery by the PodMonitor
- Selector fields: `matchLabels`, namespace scope, port name, path, interval
- Port naming requirement: port must be a named port in the pod spec

### 7.3 Domain Metrics Mapping *(2 min)*
- Key operational metrics: `camunda_process_instance_running`, `camunda_incident_open`, `camunda_job_execution_active`
- JVM and HTTP metrics for capacity planning: heap, GC, request latency
- Translating technical metrics into business-facing health indicators (e.g. active process instances as a throughput KPI)

> **Speaker note:** Most application engineers will be surprised how little configuration is needed to get Camunda exporting metrics. The biggest gotcha is port naming — highlight that early.

---

## 8) Security, Network, and Compliance Considerations
⏱ **3 min** | 🕐 *0:35 – 0:38*

- `NetworkPolicy` model: why `ama-metrics` needs explicit ingress permission
- Combined `namespaceSelector` + `podSelector` (AND logic) for least-privilege access
- RBAC boundaries: Monitoring Reader on workspace, Grafana Admin scoped per environment
- Auditability: all infrastructure changes through Azure DevOps pipeline, not manual CLI
- Data governance: observability data stays within your Azure tenant and subscription

> **Speaker note:** This section matters for compliance-conscious stakeholders. Emphasise the pipeline-enforced deployment model as the audit trail story.

---

## 9) Validation and Live Demo
⏱ **4 min** | 🕐 *0:38 – 0:42*

### 9.1 Validation Checklist *(1 min)*
- ✅ Add-on enabled and `ama-metrics` pods healthy
- ✅ PodMonitor deployed and selectors matched
- ✅ Metrics visible in Prometheus Explorer (`up`, then Camunda-specific)
- ✅ Grafana data source connected and queryable

### 9.2 Live Demo Sequence *(3 min)*
1. Show `kubectl get pods -n kube-system | grep ama-metrics` — all pods `Running`
2. Show `curl http://localhost:8080/actuator/prometheus` output for Camunda metrics
3. Run `camunda_process_instance_running` in Prometheus Explorer in Azure Portal
4. Open Grafana — walk through summary dashboard panels
5. Show an active alert rule and where notifications route

> **Speaker note:** If a live environment is not available, use pre-recorded screenshots or a recorded terminal session. Keep the demo tight — 3 minutes maximum. Audience attention drops quickly if demo setup takes time.

---

## 10) Troubleshooting Deep Dive
⏱ **2 min** | 🕐 *0:42 – 0:44*

- Structured 10-step troubleshooting path from source endpoint to visualisation
- Common failure domains:
  - Metrics endpoint unavailable → check env vars and Actuator config
  - PodMonitor label/port mismatch → check `kubectl describe podmonitor`
  - NetworkPolicy blocking scrape → check `ama-metrics` pod label `rsName=ama-metrics`
  - Workspace linkage missing → re-run Bicep pipeline
  - Grafana RBAC issue → verify Monitoring Reader role assignment
- Full step-by-step guide: [azure-monitoring.md — Troubleshooting](./azure-monitoring.md#troubleshooting)

> **Speaker note:** Don't deep-dive here unless the audience asks. Mention the runbook exists and is linked, then move on. Offer to share the troubleshooting doc separately.

---

## 11) Operating Model and Team Responsibilities
⏱ **1 min** | 🕐 *0:44 – 0:45*

| Team | Responsibility |
|---|---|
| Platform / DevOps | Foundation, RBAC, network policies, pipeline-managed infra |
| Application team | Workload metrics enablement, PodMonitor config, dashboard ownership |
| SRE / Operations | Alert tuning, incident response runbooks, SLO review cadence |

> **Speaker note:** This slide closes the "who does what" gap. Leave it visible during Q&A — it tends to prompt useful conversation.

---

## 12) Rollout Strategy, Risks, and Next Steps
*(Bonus content — use if time permits or as a leave-behind)*

- Rollout approach: pilot on dev → validated on non-prod → enforced standard on prod
- Known risks:
  - Cardinality growth as more workloads onboard
  - Alert noise before thresholds are tuned
  - Ownership gaps if application teams are not briefed
- Mitigations: metric governance policy, dashboard review standards, onboarding checklist
- Next steps:
  - Finalise environment onboarding checklist
  - Define KPI and SLO catalogue for Camunda workloads
  - Establish monthly observability review forum

---

## Timing Summary

| Section | Topic | Duration | Clock |
|---|---|---|---|
| 1 | Executive context and outcomes | 5 min | 0:00 – 0:05 |
| 2 | Architecture walkthrough | 5 min | 0:05 – 0:10 |
| 3 | Prerequisites and governance | 3 min | 0:10 – 0:13 |
| 4 | Implementation blueprint | 2 min | 0:13 – 0:15 |
| 5 | Azure Monitor deep dive | 9 min | 0:15 – 0:24 |
| 6 | Azure Managed Grafana deep dive | 6 min | 0:24 – 0:30 |
| 7 | Camunda metrics integration deep dive | 5 min | 0:30 – 0:35 |
| 8 | Security and compliance | 3 min | 0:35 – 0:38 |
| 9 | Validation and live demo | 4 min | 0:38 – 0:42 |
| 10 | Troubleshooting deep dive | 2 min | 0:42 – 0:44 |
| 11 | Operating model and responsibilities | 1 min | 0:44 – 0:45 |
| 12 | Rollout and next steps *(if time permits)* | Bonus | — |
| **Total** | | **45 min** | |

---

## Presentation Artifacts Checklist

- [ ] Architecture slide: current state gaps → target state with Azure Monitor stack
- [ ] Implementation phased sequence slide
- [ ] Azure Monitor deep-dive slide set (components, scrape model, cardinality)
- [ ] Grafana dashboard screenshot or live environment access
- [ ] Troubleshooting decision tree (from `azure-monitoring.md`)
- [ ] Team responsibilities RACI table
- [ ] Rollout plan and risk register slide

---

## Reference

- Full implementation guide: [azure-monitoring.md](./azure-monitoring.md)
- Azure Monitor troubleshooting: [Prometheus metrics troubleshoot guide](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/prometheus-metrics-troubleshoot)
