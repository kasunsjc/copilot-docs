# Production CAS to NAP Cutover Plan

## Objective

Use the same migration pattern validated on the dedicated platform-team development cluster, but apply it in a controlled wave-based manner for production. The pattern is:

1. Disable Cluster Autoscaler (CAS) on the existing user node pools.
2. Keep the current nodes running as fixed fallback capacity.
3. Enable NAP at the AKS cluster level.
4. Apply conservative `AKSNodeClass` and `NodePool` definitions.
5. Reduce old fixed user-pool capacity gradually.
6. Validate NAP behavior with real production workloads.
7. Only then retire old CAS-managed pools or move to more aggressive consolidation.

This is the simplest migration model and is appropriate when you have already validated the same approach in a dedicated development cluster and are ready to extend it to production in controlled phases.

## When to use this approach

Use this approach when:

- the platform team has validated NAP on a dedicated dev cluster,
- the production cluster is not shared with a large number of uncontrolled workloads,
- the team is comfortable with a wave-based migration,
- rollback is still possible if NAP does not produce the expected scheduling behavior.

This is a valid production path because the AKS migration guidance documents a pattern in which existing pools become fixed-size while NAP provisions new capacity in response to pending Pods. The important guardrail is that you keep existing nodes as fallback capacity until testing proves that NAP is safe for the cluster.

## Production readiness gates

Do not start production migration until all of the following are true:

- NAP has been proven in a dedicated platform dev cluster.
- The cluster uses supported features and does not rely on NAP-incompatible settings.
- The NodePools and AKSNodeClasses are version-controlled and reviewed.
- User workloads have realistic CPU and memory requests.
- Zone, affinity, anti-affinity, and topology spread constraints have been tested with real workloads.
- PodDisruptionBudgets and shutdown behavior have been validated.
- Regional quotas and subnet/IP capacity have been checked.
- Monitoring and alerting exist for pending Pods, failed NodeClaims, quota exhaustion, and Karpenter events.

## Production cutover sequence

### Phase 1: Capture the current CAS state

Before any change, record the CA state for each production pool:

```bash
az aks nodepool list \
  --resource-group <resource-group> \
  --cluster-name <aks-name> \
  --query "[].{name:name, vmSize:vmSize, mode:mode, count:count, min:minCount, max:maxCount, enableAutoScaling:enableAutoScaling, zones:availabilityZones, taints:nodeTaints, labels:nodeLabels}" \
  --output table
```

Capture workload and placement baseline:

```bash
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type
kubectl get pods -A -o wide
kubectl get pdb -A
```

### Phase 2: Disable CAS on the existing user pools

Disable autoscaling on each pool while keeping the current nodes online:

```bash
az aks nodepool update \
  --resource-group <resource-group> \
  --cluster-name <aks-name> \
  --name <user-pool-name> \
  --disable-cluster-autoscaler
```

This keeps the existing nodes in place as fixed capacity and stops the CAS controller from changing pool size. The old user pools remain available as fallback capacity until the NAP path is proven.

### Phase 3: Enable NAP at the cluster level

Apply the AKS cluster setting in Bicep:

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

Equivalent CLI command:

```bash
az aks update \
  --resource-group <resource-group> \
  --name <aks-name> \
  --node-provisioning-mode Auto
```

### Phase 4: Apply production-grade NAP policy

Start with conservative settings. Avoid aggressive consolidation and avoid mixed Spot/on-demand complexity at the same time as the migration.

Example NodePool:

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: prod-general
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.azure.com
        kind: AKSNodeClass
        name: prod-general
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
    cpu: 100
---
apiVersion: karpenter.azure.com/v1beta1
kind: AKSNodeClass
metadata:
  name: prod-general
spec:
  imageFamily: Ubuntu
```

This is intentionally conservative. Production can later evolve toward a richer VM family policy and more advanced disruption settings once validation proves the behavior.

### Phase 5: Validate NAP before reducing production capacity

Before shrinking any production CAS-fixed pool, confirm that NAP is active and healthy:

```bash
kubectl get nodepools
kubectl get aksnodeclasses
kubectl get nodeclaims
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type
kubectl get events -A --field-selector source=karpenter -w
```

Verify the following:

- NAP can create a NodeClaim
- the node joins the cluster
- it becomes Ready
- OS image, networking, identity, and storage drivers work correctly
- application health checks pass

### Phase 6: Reduce old CAS user pools gradually

Only after the NAP path is proven, reduce the old user pools in controlled waves:

```bash
az aks nodepool scale \
  --resource-group <resource-group> \
  --cluster-name <aks-name> \
  --name <old-user-pool-name> \
  --node-count <lower-count>
```

Do not scale all old pools to zero in a single step. Use a staged wave approach. For example:

- Wave 1: reduce by 20%
- Wave 2: validate and proceed if stable
- Wave 3: reduce by another 20%
- Wave 4: continue until the old pool is no longer needed

This ensures there is still fallback capacity while NAP proves itself under real workload pressure.

## Production-specific guardrails

### Do

- Run with a change window and rollback owner.
- Validate one cluster or workload class first.
- Keep old pools until the final wave is stable.
- Start with `WhenEmpty` consolidation.
- Keep NodePool limits conservative.
- Monitor Pending Pods, failed NodeClaims, and Karpenter events in real time.
- Confirm HPA, readiness, PDBs, and application behavior under scale changes.

### Do not

- Do not delete old user pools on day one.
- Do not scale all old pools to zero immediately.
- Do not introduce Spot or aggressive underutilized-node consolidation at the same time as the migration.
- Do not change workload resource requests and NAP migration together unless absolutely necessary.
- Do not migrate all production clusters in a single wave.

## Production rollback plan

If the NAP migration causes instability:

1. Re-enable autoscaling on the old CAS user pools.
2. Scale the pools back up to the previous safe counts.
3. Disable NAP in the AKS Bicep template or CLI configuration.
4. Restore the original nodepool definitions.
5. Validate the application and cluster health before retrying.

## Recommended production sequence

1. Validate in dedicated platform dev cluster.
2. Move one lower-risk production cluster or workload class.
3. Disable CAS and keep existing nodes as fixed fallback.
4. Enable NAP.
5. Apply conservative NodePools and AKSNodeClasses.
6. Reduce old user pools in small waves.
7. Validate real workload behavior under scale, placement, and consolidation.
8. Proceed only if all rollout gates pass.

## Summary

Yes, the same migration pattern can be used in production as in the dedicated platform development cluster. The difference is not the model itself; it is the pace, the guardrails, and the rollback discipline. Production should move in waves with conservative NAP settings and fixed fallback capacity retained until the cluster proves it is stable.
