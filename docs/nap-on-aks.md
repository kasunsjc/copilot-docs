# NAP on AKS

## What is NAP?

NAP stands for Node Auto-Provisioning in AKS. It automatically selects, creates, scales, upgrades, consolidates, and removes Kubernetes nodes based on the resource requirements and scheduling constraints of pending Pods.

NAP is AKS's managed integration of the open-source Karpenter project and the AKS Karpenter provider.

### Core behavior

When a Pod cannot be scheduled because the cluster lacks suitable capacity, NAP:

1. Evaluates the Pod's CPU, memory, architecture, GPU, taints, affinity, and other constraints.
2. Selects an appropriate Azure VM SKU.
3. Provisions a node that satisfies the workload.
4. Schedules the Pod onto that node.
5. Consolidates or removes underutilized nodes when appropriate.

NAP uses Kubernetes resources such as:

- `NodePool` – defines provisioning constraints, VM families, capacity type, limits, and priorities.
- `AKSNodeClass` – defines Azure-specific settings such as image family, subnet, OS disk, kubelet configuration, GPU settings, and tags.
- `NodeClaim` – represents a node being provisioned or managed by NAP.

## NAP vs Cluster Autoscaler

| Area | Cluster Autoscaler | NAP |
|---|---|---|
| Scaling model | Adds or removes nodes from predefined pools | Creates nodes dynamically based on Pod requirements |
| VM selection | Usually one VM size per node pool | Can select from multiple compatible VM SKUs |
| Bin packing | Limited to configured pools | Can improve packing and reduce fragmentation |
| Node lifecycle | More manual node-pool planning | Handles provisioning, consolidation, and replacement |
| Configuration | Azure CLI/node-pool settings | Kubernetes `NodePool` and `AKSNodeClass` resources |

NAP can improve VM flexibility and utilization, but it also introduces additional Kubernetes resources and policies that a platform team must manage.

## AKS Automatic vs AKS Standard

- AKS Automatic: NAP is preconfigured as part of the managed experience.
- AKS Standard: NAP can be enabled and configured with custom `NodePool` and `AKSNodeClass` resources for more control.

## Basic enablement

Example Azure CLI command:

```bash
az aks create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --node-provisioning-mode Auto \
  --generate-ssh-keys
```

After enabling NAP, you can review resources using:

```bash
kubectl get nodepools
kubectl get aksnodeclasses
kubectl get nodeclaims
kubectl get events -A --field-selector source=karpenter
```

## Key considerations when migrating from Cluster Autoscaler to NAP

### 1. Cluster compatibility

Check for unsupported capabilities before migration:

- Windows node pools are unsupported.
- IPv6 clusters are unsupported.
- Service principals are unsupported; use a system-assigned or user-assigned managed identity.
- NAP-enabled clusters cannot be stopped.
- The cluster outbound/egress type cannot be changed after NAP is enabled.
- Custom VNet deployments require a Standard Load Balancer.

Also review the node OS baseline. For example, older Azure Linux 2.0-based pools require careful upgrade or replacement planning, because the Node OS may be deprecated or removed in specific time windows.

### 2. Review current Cluster Autoscaler behavior

Document each existing pool's:

- VM SKU and zones
- min/max size
- Spot vs on-demand
- labels, taints, tolerations
- custom kubelet settings
- subnet and network configuration
- affinity, topology, and scheduling constraints
- GPU, ARM64, memory-optimized, or specialized needs

Then decide which requirements remain at the Pod level and which become NodePool or AKSNodeClass constraints.

### 3. Fix workload requests and disruption controls

NAP makes scheduling decisions based on pending Pod resource requests. Missing or inaccurate CPU and memory requests can lead to poor scaling and unpredictable behavior.

Review:

- Pod resource requests/limits
- PodDisruptionBudgets
- termination grace periods
- app shutdown behavior
- stateful workloads and rescheduling constraints
- DaemonSets and their impact on node utilization

### 4. Choose the migration model

There are two major migration patterns:

#### A. Disable CAS and then enable NAP

Simpler and easier to reason about.

- Existing pools may be converted to fixed-size pools.
- User pools can be gradually reduced while pending pods drive NAP provisioning.

#### B. Run CAS and NAP side by side temporarily

This supports a gradual migration but is more complex.

- Both autoscalers can attempt to provision capacity.
- This can lead to double-provisioning unless workloads are isolated by taints, tolerations, or migration controls.
- Workloads must be carefully mapped to one autoscaler at a time.

### 5. Design NodePools as workload classes

Rather than duplicating many fixed CAS node pools, create a smaller set of workload classes such as:

- general app capacity
- Spot-capable worker workloads
- GPU workloads
- memory-optimized workloads
- compliance-isolated workloads

Each NodePool should define the allowed VM families and constraints narrowly enough to satisfy requirements but broad enough to allow flexibility.

### 6. Validate networking and IP capacity

NAP provisions nodes dynamically, so IP planning matters more than in a static pool model.

Check:

- subnet capacity
- NSG and firewall rules
- custom networking assumptions
- Pod CIDR planning for Azure CNI Overlay
- identity and registry access for dynamically provisioned nodes

### 7. Define disruption and replacement policies

NAP may consolidate, replace, or drain nodes more aggressively than a static autoscaler model.

Plan for:

- consolidation timing
- node expiration settings
- disruption budgets
- application shutdown behavior
- upgrade windows and maintenance windows

### 8. Confirm quotas, cost controls, and SKU availability

NAP may dynamically select many VM sizes. Validate:

- regional vCPU quotas
- permitted VM family list
- Spot vs on-demand usage
- resource limits
- cost expectations
- capacity constraints in target regions

### 9. Add observability and rollback controls

Before production migration, validate:

```bash
kubectl get nodepools
kubectl get aksnodeclasses
kubectl get nodeclaims
kubectl get events -A --field-selector source=karpenter -w
```

Review provisioning events and NodeClaim status to understand why nodes were created or not created.

## Practical recommendation

For most AKS teams, the safest migration path is:

1. Validate workload requirements.
2. Build conservative `NodePool` and `AKSNodeClass` definitions.
3. Enable NAP in a staged rollout.
4. Migrate one workload group at a time.
5. Reduce old CAS-based node pool capacity only after the system is stable.
6. Remove legacy autoscaler controls after validation.

## Summary

NAP is useful when you want AKS to make node selection and lifecycle decisions based on actual Pod requirements instead of maintaining many manually sized node pools. It offers better flexibility and packing behavior than traditional static node pools, but it requires a deliberate migration plan around resource requests, scheduling constraints, networking, disruption handling, and platform controls.

## References

- Azure AKS Node Auto-Provisioning documentation
- Azure AKS migration guidance from Cluster Autoscaler to NAP
- AKS Karpenter and NodePool documentation
- AKS troubleshooting guidance for NAP and node provisioning
