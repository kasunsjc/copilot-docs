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

---

## Testing pod placement with NAP (affinity, anti-affinity, and constraints)

Reference: [Control where your pods land on AKS with NAP – AKS Engineering Blog](https://blog.aks.azure.com/2026/03/20/node-provisioning-best-practice)

NAP reacts to **pending pods**. It reads the pod's scheduling expressions (node selectors, node affinity, pod affinity/anti-affinity, topology spread constraints, tolerations, and resource requests), combines them with `NodePool` and `AKSNodeClass` constraints, and then decides what node shape to create. Because of this, placement rules directly drive provisioning behavior — and over-constrained pods can either stay `Pending` forever or cause unnecessary node churn.

### Core testing principles

1. **Start simple, then add complexity.** Begin with the minimum constraint set, confirm it works, then layer on affinity or spread rules one at a time.
2. **Change one constraint per test.** This isolates which rule caused a pod to stay pending or caused NAP to pick an unexpected SKU.
3. **Do not over-constrain.** Broad anti-affinity or narrow selectors can make it impossible for NAP to find any valid node.
4. **Always observe events, not just the end state.** Both the kube-scheduler and Karpenter emit events explaining why scheduling or provisioning failed.
5. **Keep NodePools mutually exclusive.** If a pod matches multiple NodePools, placement becomes unpredictable. Use distinct taints, labels, and requirements per pool.

### Test matrix

| # | Test | What to verify | Expected result |
|---|---|---|---|
| 1 | Baseline scale-up | Deploy a workload with only resource requests | NAP provisions a correctly sized node; pod schedules |
| 2 | Node affinity / nodeSelector | Require a specific label (e.g. zone, arch, SKU family) | NAP provisions a node carrying that label |
| 3 | Pod affinity | Co-locate pods via `podAffinity` with a topology key | Pods land on the same node/zone as the target pod |
| 4 | Pod anti-affinity (`kubernetes.io/hostname`) | Require replicas on separate nodes | NAP creates one node per replica; no co-location |
| 5 | Pod anti-affinity (`topology.kubernetes.io/zone`) | Require replicas in separate zones | Nodes provisioned across distinct zones |
| 6 | Preferred vs required | Compare `preferredDuringScheduling` and `requiredDuringScheduling` | Preferred degrades gracefully; required may leave pods pending |
| 7 | Topology spread constraints | Spread N replicas across zones with `maxSkew` | Balanced distribution; no excessive node creation |
| 8 | `whenUnsatisfiable` behavior | Test both `DoNotSchedule` and `ScheduleAnyway` | `DoNotSchedule` triggers provisioning; `ScheduleAnyway` may pack tighter |
| 9 | Taints and tolerations | Workload targeting a tainted NodePool | Only tolerating pods land there |
| 10 | Multiple NodePool match | Workload that could match 2 pools | Confirm intended pool wins via weight/requirements |
| 11 | Over-constrained pod | Intentionally impossible constraint set | Pod stays `Pending`; clear event explains why; no runaway node creation |
| 12 | Consolidation safety | Scale down and let NAP consolidate | Anti-affinity and spread rules still honored after consolidation |
| 13 | Node replacement / drift | Trigger node expiry or drift replacement | Replacement nodes still satisfy affinity/spread rules |
| 14 | PDB interaction | Consolidate with PDBs in place | PDBs respected; no availability drop |
| 15 | Scale burst | Scale from 1 to N replicas rapidly | Constraints honored at scale; provisioning latency acceptable |
| 16 | Zone capacity failure | Constrain to a capacity-limited zone | Clear failure events; verify fallback behavior |

### Critical scenarios for anti-affinity users

Because you rely on pod affinity/anti-affinity, pay particular attention to:

- **Hostname anti-affinity forces one pod per node.** Every replica requires a dedicated node, so NAP will provision one node per replica. Confirm your NodePool limits and vCPU quota can absorb this, and check the cost impact — bin packing benefits are largely lost here.
- **Anti-affinity plus consolidation.** Verify that when NAP consolidates, it does not attempt a replacement plan that would violate anti-affinity. Test with realistic replica counts, not just 2 replicas.
- **Required anti-affinity can deadlock.** If NAP cannot create a node satisfying the rule (quota, SKU, or zone exhaustion), pods stay pending indefinitely. Make sure alerting covers long-pending pods.
- **Prefer topology spread over anti-affinity where possible.** Spread constraints usually give better packing and more predictable NAP behavior than strict `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity.
- **Pod affinity is expensive to satisfy.** Co-location rules can force NAP into a narrow set of valid nodes. Validate that the anchor pod exists and is schedulable first.

### Example test workload — zone spread

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nap-spread-test
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nap-spread-test
  template:
    metadata:
      labels:
        app: nap-spread-test
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: nap-spread-test
      containers:
        - name: app
          image: mcr.microsoft.com/oss/nginx/nginx:1.25
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
```

### Example test workload — hostname anti-affinity

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nap-antiaffinity-test
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nap-antiaffinity-test
  template:
    metadata:
      labels:
        app: nap-antiaffinity-test
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: nap-antiaffinity-test
              topologyKey: kubernetes.io/hostname
      containers:
        - name: app
          image: mcr.microsoft.com/oss/nginx/nginx:1.25
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
```

### Validation commands

```bash
# Where did pods actually land?
kubectl get pods -o wide -l app=nap-spread-test

# Node-to-zone mapping
kubectl get nodes -L topology.kubernetes.io/zone -L node.kubernetes.io/instance-type

# Why is a pod pending?
kubectl describe pod <pod-name>

# What is NAP doing?
kubectl get nodeclaims
kubectl describe nodeclaim <nodeclaim-name>
kubectl get events -A --field-selector source=karpenter -w

# Count pods per node to confirm anti-affinity
kubectl get pods -o wide --no-headers | awk '{print $8}' | sort | uniq -c
```

### Exit criteria before production rollout

- All placement rules produce the intended distribution under both scale-up and scale-down.
- No workload becomes permanently unschedulable under realistic constraint combinations.
- Consolidation and node replacement preserve affinity, anti-affinity, and spread guarantees.
- Provisioning latency for constrained workloads is within your SLOs.
- Node count and cost under anti-affinity rules are understood and acceptable.
- Alerts exist for long-pending pods and repeated NAP provisioning failures.

---

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

- [Control where your pods land on AKS with NAP – AKS Engineering Blog](https://blog.aks.azure.com/2026/03/20/node-provisioning-best-practice)
- [Configure node pools for node auto-provisioning (NAP) in AKS](https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning-node-pools)
- Azure AKS Node Auto-Provisioning documentation
- Azure AKS migration guidance from Cluster Autoscaler to NAP
- AKS troubleshooting guidance for NAP and node provisioning
