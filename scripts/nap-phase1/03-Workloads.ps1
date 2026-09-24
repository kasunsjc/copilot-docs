<#
.SYNOPSIS
  1.2 Inventory of workload requests, placement rules, PDBs, DaemonSets and storage.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
Write-Host "== 1.2 Workloads ==" -ForegroundColor Cyan

function Get-K8s([string]$kinds) {
    ((kubectl get $kinds -A -o json) -join "`n" | ConvertFrom-Json).items
}

# Containers missing CPU or memory requests (fix before NAP)
$pods = Get-K8s 'pods'
$missing = foreach ($p in $pods) {
    foreach ($ct in $p.spec.containers) {
        if (-not $ct.resources.requests.cpu -or -not $ct.resources.requests.memory) {
            [pscustomobject]@{ Namespace = $p.metadata.namespace; Pod = $p.metadata.name; Container = $ct.name
                               CpuRequest = $ct.resources.requests.cpu; MemRequest = $ct.resources.requests.memory }
        }
    }
}
$missing | Export-Csv (Join-Path $OutDir 'missing-requests.csv') -NoTypeInformation
Write-Host ("Containers missing requests: {0}" -f @($missing).Count) -ForegroundColor Yellow

# Requests and limits per workload
$workloads = Get-K8s 'deploy,statefulset,daemonset'
$workloads | ForEach-Object {
    $w = $_
    foreach ($ct in $w.spec.template.spec.containers) {
        [pscustomobject]@{
            Kind = $w.kind; Namespace = $w.metadata.namespace; Name = $w.metadata.name; Container = $ct.name
            CpuReq = $ct.resources.requests.cpu; MemReq = $ct.resources.requests.memory
            CpuLim = $ct.resources.limits.cpu;   MemLim = $ct.resources.limits.memory
        }
    }
} | Export-Csv (Join-Path $OutDir 'requests-limits.csv') -NoTypeInformation

# Placement rules
$placement = $workloads | Where-Object kind -in 'Deployment', 'StatefulSet' | ForEach-Object {
    $s = $_.spec.template.spec
    if ($s.nodeSelector -or $s.affinity -or $s.topologySpreadConstraints -or $s.tolerations) {
        [pscustomobject]@{
            kind = $_.kind; ns = $_.metadata.namespace; name = $_.metadata.name; replicas = $_.spec.replicas
            nodeSelector = $s.nodeSelector; affinity = $s.affinity; spread = $s.topologySpreadConstraints
            tolerations = $s.tolerations; grace = $s.terminationGracePeriodSeconds
        }
    }
}
$placement | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $OutDir 'placement-rules.json')

# Required anti-affinity (drives node count under NAP)
$placement | Where-Object { $_.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution } |
    ForEach-Object {
        $keys = ($_.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution.topologyKey | Sort-Object -Unique) -join ','
        "{0}/{1} replicas={2} topologyKeys={3}" -f $_.ns, $_.name, $_.replicas, $keys
    } | Tee-Object -FilePath (Join-Path $OutDir 'hard-antiaffinity.txt')

# Workloads pinned to a CAS pool name (will never move to NAP)
$placement | Where-Object { $_.nodeSelector.agentpool -or (($_.affinity | ConvertTo-Json -Depth 20 -Compress) -match 'agentpool') } |
    ForEach-Object { "{0}/{1}" -f $_.ns, $_.name } |
    Tee-Object -FilePath (Join-Path $OutDir 'agentpool-pinned.txt')

# PDBs and blocking PDBs
kubectl get pdb -A -o wide | Set-Content (Join-Path $OutDir 'pdbs.txt')
Get-K8s 'pdb' | Where-Object { $_.status.disruptionsAllowed -eq 0 } |
    ForEach-Object { "{0}/{1}" -f $_.metadata.namespace, $_.metadata.name } |
    Tee-Object -FilePath (Join-Path $OutDir 'blocking-pdbs.txt')

# DaemonSet overhead on every NAP node
kubectl get ds -A -o wide | Set-Content (Join-Path $OutDir 'daemonsets.txt')

# Stateful workloads and zone-bound disks
kubectl get pvc -A -o wide | Set-Content (Join-Path $OutDir 'pvcs.txt')
((kubectl get pv -o json) -join "`n" | ConvertFrom-Json).items | ForEach-Object {
    [pscustomobject]@{
        Name = $_.metadata.name; StorageClass = $_.spec.storageClassName
        Claim = "{0}/{1}" -f $_.spec.claimRef.namespace, $_.spec.claimRef.name
        Zones = ($_.spec.nodeAffinity.required.nodeSelectorTerms.matchExpressions |
                 Where-Object key -match 'zone' | ForEach-Object { $_.values }) -join ','
    }
} | Export-Csv (Join-Path $OutDir 'pv-zones.csv') -NoTypeInformation
