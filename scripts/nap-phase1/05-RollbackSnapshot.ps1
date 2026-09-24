<#
.SYNOPSIS
  1.4 Rollback snapshot: workload manifests and Bicep git revision.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutDir,
    [string]$BicepRepoPath
)
$ErrorActionPreference = 'Stop'
Write-Host "== 1.4 Rollback snapshot ==" -ForegroundColor Cyan

if ($BicepRepoPath) {
    git -C $BicepRepoPath rev-parse HEAD | Set-Content (Join-Path $OutDir 'bicep-sha.txt')
} else {
    Write-Warning 'BicepRepoPath not supplied - record the Bicep commit SHA manually.'
}

kubectl get deploy,sts,ds,pdb,hpa -A -o yaml | Set-Content (Join-Path $OutDir 'workloads-backup.yaml')
