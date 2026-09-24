<#
.SYNOPSIS
  1.1 Inventory of current CAS node pools and nodes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ClusterName,
    [Parameter(Mandatory)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
Write-Host "== 1.1 Node pools ==" -ForegroundColor Cyan

$poolsJson = (az aks nodepool list -g $ResourceGroup --cluster-name $ClusterName -o json) -join "`n"
$poolsJson | Set-Content (Join-Path $OutDir 'nodepools.json')
$pools = $poolsJson | ConvertFrom-Json

# Summary table
$pools | Select-Object name, mode, vmSize, osSku,
    @{ n = 'zones';     e = { if ($_.availabilityZones) { $_.availabilityZones -join ',' } else { 'none' } } },
    count,
    @{ n = 'autoscale'; e = { $_.enableAutoScaling } },
    minCount, maxCount,
    @{ n = 'priority';  e = { $_.scaleSetPriority } },
    maxPods, osDiskType, osDiskSizeGb,
    @{ n = 'subnet';    e = { if ($_.vnetSubnetId) { ($_.vnetSubnetId -split '/')[-1] } } },
    orchestratorVersion |
    Tee-Object -Variable summary | Format-Table -AutoSize | Out-String -Width 400 |
    Tee-Object -FilePath (Join-Path $OutDir 'nodepools.txt')
$summary | Export-Csv (Join-Path $OutDir 'nodepools.csv') -NoTypeInformation

# Labels, taints, kubelet / OS config per pool
$pools | Select-Object name, nodeLabels, nodeTaints, kubeletConfig, linuxOsConfig |
    ConvertTo-Json -Depth 10 | Set-Content (Join-Path $OutDir 'pool-labels-taints.json')

# Autoscaler profile (needed to restore CAS)
(az aks show -g $ResourceGroup -n $ClusterName --query autoScalerProfile -o json) -join "`n" |
    Set-Content (Join-Path $OutDir 'autoscaler-profile.json')

# What is actually running
kubectl get nodes -o wide `
    -L agentpool,topology.kubernetes.io/zone,node.kubernetes.io/instance-type,kubernetes.azure.com/scalesetpriority |
    Tee-Object -FilePath (Join-Path $OutDir 'nodes.txt')

kubectl describe nodes | Select-String -Pattern '^Name:|Allocated resources' -Context 0, 8 |
    ForEach-Object { $_.ToString() } | Set-Content (Join-Path $OutDir 'node-allocation.txt')

try { kubectl top nodes 2>$null | Set-Content (Join-Path $OutDir 'node-usage.txt') }
catch { Write-Warning 'kubectl top nodes failed (metrics-server unavailable?).' }
