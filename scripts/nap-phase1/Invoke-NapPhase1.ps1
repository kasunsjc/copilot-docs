<#
.SYNOPSIS
  Runs all Phase 1 (baseline and requirements gathering) steps for the CAS -> NAP cutover.

.EXAMPLE
  ./Invoke-NapPhase1.ps1 -ResourceGroup rg-platform-dev -ClusterName aks-platform-dev -SubscriptionId 0000-... -BicepRepoPath C:\src\infra
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ClusterName,
    [Parameter(Mandatory)][string]$SubscriptionId,
    [string]$OutDir = (Join-Path (Get-Location) ("nap-baseline-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmm'))),
    [string]$BicepRepoPath
)

$ErrorActionPreference = 'Stop'

foreach ($tool in 'az', 'kubectl') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not installed or not on PATH." }
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
Write-Host "Output folder: $OutDir" -ForegroundColor Cyan

az account set --subscription $SubscriptionId
az aks get-credentials -g $ResourceGroup -n $ClusterName --overwrite-existing | Out-Null

$common = @{ ResourceGroup = $ResourceGroup; ClusterName = $ClusterName; OutDir = $OutDir }

& "$PSScriptRoot/01-Compatibility.ps1"     @common
& "$PSScriptRoot/02-NodePools.ps1"         @common
& "$PSScriptRoot/03-Workloads.ps1"         -OutDir $OutDir
& "$PSScriptRoot/04-Capacity.ps1"          @common
& "$PSScriptRoot/05-RollbackSnapshot.ps1"  -OutDir $OutDir -BicepRepoPath $BicepRepoPath

Write-Host "`nPhase 1 baseline complete. Review and commit: $OutDir" -ForegroundColor Green
