# Dedicated Platform Team Dev Cluster: CAS to NAP Cutover Plan

## Objective

Use the dedicated platform-team development cluster to validate NAP in a controlled way before any broader migration. Because this cluster is dedicated to the platform team and is not shared with application teams, the simpler migration path is to disable Cluster Autoscaler (CAS) and then enable NAP, while keeping the current CAS-created nodes running as a fallback until validation is complete.

This approach is simpler than running CAS and NAP side by side and is the right choice when the cluster is reserved for validation and not used by unrelated production workloads.

## Recommended approach

### Phase 1: Baseline and preparation

1. Inventory the current CAS user pools.
   - VM family and SKU
   - zones and region
   - labels, taints, and tolerations
   - min/max counts
   - Spot vs on-demand
   - GPU or specialized workload pools

2. Inventory workload placement rules.
   - resource requests and limits
   - `nodeSelector` and `nodeAffinity`
   - `podAffinity` and `podAntiAffinity`
   - `topologySpreadConstraints`
   - PodDisruptionBudgets and app shutdown behavior

3. Define the initial NAP target configuration.
   - Start with a conservative general-purpose on-demand `NodePool`.
   - Allow the VM families currently used by platform workloads.
   - Set conservative resource limits.
   - Use `WhenEmpty` consolidation first.

4. Prepare rollback.
   - Keep the existing CAS user pools intact.
   - Do not delete them during the validation period.
   - Save the current autoscaler settings so they can be restored quickly.

### Phase 2: Enable NAP and cut over

1. Disable autoscaling on the existing CAS user pools while leaving their nodes running.
2. Enable NAP at the AKS cluster level in Bicep by setting the AKS cluster `nodeProvisioningProfile.mode` to `Auto`.
3. Apply the initial `AKSNodeClass` and `NodePool` definitions.
4. Validate that NAP can create a `NodeClaim`, a node, and schedule Pods successfully.
5. Gradually reduce the old CAS user pools to force pending workloads onto NAP.
6. Observe actual scheduling behavior under production-like placement policies.
7. Only after validation, enable more aggressive consolidation and eventually remove old CAS-managed pools.

## Bicep pattern for the cutover

This is the first change to add to the cluster definition:

```bicep
resource aks 'Microsoft.ContainerService/managedClusters@2025-05-01' = {
  name: aksName
  location: location
  properties: {
    // existing AKS properties

    nodeProvisioningProfile: {
      mode: 'Auto'
    }
  }
}
```

At the same time, disable autoscaling on each user pool in Bicep or via CLI so the existing nodes remain but CAS stops managing them:

```bash
az aks nodepool update \
  --resource-group <resource-group> \
  --cluster-name <aks-name> \
  --name <user-pool-name> \
  --disable-cluster-autoscaler
```

## Initial NAP NodePool design

For the platform testing cluster, start simple:

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: platform-dev-general
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.azure.com
        kind: AKSNodeClass
        name: platform-dev-general
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: karpenter.azure.com/sku-family
          operator: In
          values: ["D"]
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 10m
  limits:
    cpu: 20
---
apiVersion: karpenter.azure.com/v1beta1
kind: AKSNodeClass
metadata:
  name: platform-dev-general
spec:
  imageFamily: Ubuntu
```

Start with the VM family and zones already used by your current CAS pool. Adjust later after workload validation.

## Validation sequence for the first deployment

1. Deploy a basic workload with just CPU and memory requests.
2. Confirm a `NodeClaim` appears and a node is created.
3. Confirm the workload becomes Ready.
4. Deploy one real workload that uses the target affinity and anti-affinity rules.
5. Validate zone spread and node placement.
6. Increase the replica count to realistic production-like values.
7. Reduce the old CAS user pool counts gradually.
8. Observe how NAP handles updated Pod scheduling pressure.
9. Test a deliberately impossible scheduling combination and confirm the Pod remains Pending with clear events.
10. Validate scale-down and consolidation in a safe manner.

## Commands to observe during the cutover

```bash
kubectl get nodepools
kubectl get aksnodeclasses
kubectl get nodeclaims -w
kubectl get pods -A -o wide -w
kubectl get events -A --field-selector source=karpenter -w
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type
```

## Decision points

Proceed only after all of the following are true:

- NAP has created a node successfully.
- The application becomes Ready on NAP-managed nodes.
- Pod distribution matches your expected affinity, anti-affinity, and topology spread rules.
- `PodDisruptionBudget` and workload shutdown behavior are still valid under consolidation.
- No long-pending Pods or repeated failed NodeClaims are observed.
- The cluster team has a clear rollback path back to CAS.

## Rollback plan

If the NAP validation fails:

1. Re-enable autoscaling on the CAS user pools.
2. Scale the old pools back up to the previous safe counts.
3. Remove or disable the NAP cluster profile in the AKS Bicep config.
4. Reapply the original nodepool configuration.

## Summary

Because the cluster is dedicated to the platform team and not shared with application teams, the cleanest starting approach is to disable CAS and enable NAP on the dev cluster, while leaving the existing CAS-created nodes intact until validation proves NAP is safe. This reduces operational complexity and provides the clearest signal for how NAP behaves with your actual workload placement rules.
