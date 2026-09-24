<#
.SYNOPSIS
  1.0 Cluster compatibility check for NAP.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ClusterName,
    [Parameter(Mandatory)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
Write-Host "== 1.0 Compatibility ==" -ForegroundColor Cyan

# Full cluster config (also your rollback reference)
$clusterJson = (az aks show -g $ResourceGroup -n $ClusterName -o json) -join "`n"
$clusterJson | Set-Content (Join-Path $OutDir 'cluster.json')
$c = $clusterJson | ConvertFrom-Json

$compat = [ordered]@{
    k8sVersion        = $c.kubernetesVersion
    identity          = $c.identity.type
    servicePrincipal  = $c.servicePrincipalProfile.clientId
    networkPlugin     = $c.networkProfile.networkPlugin
    networkPluginMode = $c.networkProfile.networkPluginMode
    networkPolicy     = $c.networkProfile.networkPolicy
    dataplane         = $c.networkProfile.networkDataplane
    outboundType      = $c.networkProfile.outboundType
    loadBalancerSku   = $c.networkProfile.loadBalancerSku
    podCidr           = $c.networkProfile.podCidr
    ipFamilies        = ($c.networkProfile.ipFamilies -join ',')
    nodeProvisioning  = $c.nodeProvisioningProfile
    autoUpgrade       = $c.autoUpgradeProfile
}
$compat | ConvertTo-Json -Depth 10 | Tee-Object -FilePath (Join-Path $OutDir 'compat.json')

# Windows pools block NAP
$pools   = (az aks nodepool list -g $ResourceGroup --cluster-name $ClusterName -o json) -join "`n" | ConvertFrom-Json
$windows = $pools | Where-Object osType -eq 'Windows' | Select-Object -ExpandProperty name

# Automatic findings
$findings = @()
if ($windows)                                              { $findings += "BLOCKER: Windows node pools found: $($windows -join ', ')" }
if ($compat.identity -notmatch 'Assigned')                 { $findings += "BLOCKER: Cluster does not use a managed identity (identity=$($compat.identity))." }
if ($compat.servicePrincipal -and $compat.servicePrincipal -ne 'msi') { $findings += "BLOCKER: Service principal in use ($($compat.servicePrincipal))." }
if ($compat.ipFamilies -match 'IPv6')                      { $findings += "BLOCKER: IPv6 is enabled." }
if ($compat.loadBalancerSku -and $compat.loadBalancerSku -ne 'standard') { $findings += "BLOCKER: Load balancer SKU is $($compat.loadBalancerSku); Standard is required." }
if ($compat.networkPlugin -eq 'kubenet')                   { $findings += "CHECK: kubenet in use - confirm NAP support in current docs." }
if ($compat.networkPolicy -eq 'calico')                    { $findings += "CHECK: Calico network policy - confirm NAP support in current docs." }
$findings += "CHECK: outboundType is '$($compat.outboundType)'. It cannot be changed after NAP is enabled - confirm it is final."

$findings | Tee-Object -FilePath (Join-Path $OutDir 'compat-findings.txt') | ForEach-Object {
    if ($_ -like 'BLOCKER*') { Write-Warning $_ } else { Write-Host $_ -ForegroundColor Yellow }
}
