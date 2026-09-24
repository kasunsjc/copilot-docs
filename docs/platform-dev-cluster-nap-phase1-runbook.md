# Platform Dev Cluster: Phase 1 Baseline Runbook (PowerShell)

Companion to [platform-dev-cluster-nap-cutover.md](./platform-dev-cluster-nap-cutover.md). This covers **Phase 1: Baseline and preparation** using PowerShell scripts in [`scripts/nap-phase1`](../scripts/nap-phase1).

## Prerequisites

- PowerShell 7+ (`pwsh`) recommended; Windows PowerShell 5.1 also works.
- Azure CLI (`az`) logged in with access to the cluster subscription.
- `kubectl`, and `git` if you want the Bicep SHA captured.
- If script execution is blocked: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.

## Run everything

```powershell
cd scripts/nap-phase1
./Invoke-NapPhase1.ps1 `
  -ResourceGroup  '<resource-group>' `
  -ClusterName    '<aks-name>' `
  -SubscriptionId '<subscription-id>' `
  -BicepRepoPath  'C:\src\<bicep-repo>'   # optional
```

Output goes to `./nap-baseline-<yyyyMMdd-HHmm>/`. Commit that folder as test evidence.

Each step can also be run on its own, for example:

```powershell
./01-Compatibility.ps1 -ResourceGroup <rg> -ClusterName <aks> -OutDir ./nap-baseline
```

## Scripts and outputs

| Step | Script | Key outputs | What to review |
|---|---|---|---|
| 1.0 Compatibility | `01-Compatibility.ps1` | `cluster.json`, `compat.json`, `compat-findings.txt` | Any `BLOCKER` line; confirm `outboundType` is final (can't change after NAP). |
| 1.1 Node pools | `02-NodePools.ps1` | `nodepools.csv`, `pool-labels-taints.json`, `autoscaler-profile.json`, `nodes.txt`, `node-allocation.txt` | VM families/zones to allow in the NAP `NodePool`; labels/taints to carry over; min/max to restore CAS. |
| 1.2 Workloads | `03-Workloads.ps1` | `missing-requests.csv`, `requests-limits.csv`, `placement-rules.json`, `hard-antiaffinity.txt`, `agentpool-pinned.txt`, `blocking-pdbs.txt`, `pv-zones.csv` | Fix missing requests; replace `agentpool` pinning; size limits for hard anti-affinity; fix PDBs with 0 disruptions allowed. |
| 1.3 Capacity | `04-Capacity.ps1` | `quota.txt`, `skus.csv`, `subnet.txt` | vCPU quota covers peak + anti-affinity overhead; SKUs available in target zones; free subnet IPs. |
| 1.4 Rollback | `05-RollbackSnapshot.ps1` | `workloads-backup.yaml`, `bicep-sha.txt` | Snapshot exists before any Phase 2 change. |

## Phase 1 exit checklist

- [ ] No `BLOCKER` entries in `compat-findings.txt`.
- [ ] `missing-requests.csv` is empty for platform workloads (or exceptions are documented).
- [ ] `agentpool-pinned.txt` is empty, or those workloads are switched to a NAP label (e.g. `platform.team/pool: dev-general`).
- [ ] `blocking-pdbs.txt` reviewed; no PDB will block every drain.
- [ ] NodePool `limits.cpu` ≥ peak replicas × request + hard anti-affinity overhead, and below free vCPU quota.
- [ ] Allowed SKU families and zones in the NodePool match `nodepools.csv` and `skus.csv`.
- [ ] Autoscaler profile and pool min/max are saved for rollback.
- [ ] Baseline folder committed.

## Improvements to the cutover plan

1. **Rollback:** NAP may not be switchable back to `Manual` without first deleting all NAP `NodePool`s and draining NodeClaims. Verify against current docs, then rehearse: scale CAS pools up -> re-enable CAS -> `kubectl delete nodepools --all` -> wait for NodeClaims to drain -> change Bicep mode.
2. **`default` NodePool:** NAP creates a broad `default` NodePool. Delete/restrict it, or give `platform-dev-general` a higher `weight`.
3. **NodePool hardening:** add `weight`, a custom label, OS/arch/zone/`sku-cpu` requirements, `expireAfter`, a disruption `budgets` entry, and a `memory` limit. Match `imageFamily` to the current pool `osSku`.
4. **Phase 2 order:** enable NAP and apply the NodePool, prove it with a canary pod, *then* disable CAS, so capacity is never unmanaged.
5. **Drain deliberately:** cordon and drain one CAS node at a time (`kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`) and watch NodeClaims; this also tests PDBs.
6. **Bicep:** set `enableAutoScaling: false` on agent pools so redeploys don't re-enable CAS; confirm the API version supports the `nodeProvisioningProfile` fields you use.
7. **Metrics:** record Pending -> NodeClaim Ready time, SKUs chosen, cost/day vs CAS, and failed NodeClaims.
8. **System pool:** keep it manual and fixed; never scale it to zero.
9. **Operations:** NAP clusters can't be stopped — remove stop/start automation. Run a node image upgrade during the test to observe drift replacement.
