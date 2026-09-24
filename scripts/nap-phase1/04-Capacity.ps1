<#
.SYNOPSIS
  1.3 Capacity checks: vCPU quota, SKU availability by zone, subnet IPs.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ClusterName,
    [Parameter(Mandatory)][string]$OutDir,
    [string]$SkuPrefix = 'Standard_D'
)
$ErrorActionPreference = 'Stop'
Write-Host "== 1.3 Capacity ==" -ForegroundColor Cyan

$location = az aks show -g $ResourceGroup -n $ClusterName --query location -o tsv

# vCPU quota
((az vm list-usage -l $location -o json) -join "`n" | ConvertFrom-Json) |
    Where-Object { $_.name.localizedValue -match 'Total Regional|Standard D|Standard E|Standard F' } |
    Select-Object @{ n = 'Quota'; e = { $_.name.localizedValue } }, currentValue, limit,
                  @{ n = 'Free'; e = { $_.limit - $_.currentValue } } |
    Format-Table -AutoSize | Out-String -Width 300 | Tee-Object -FilePath (Join-Path $OutDir 'quota.txt')

# SKUs by zone and restrictions
((az vm list-skus -l $location --resource-type virtualMachines -o json) -join "`n" | ConvertFrom-Json) |
    Where-Object { $_.name -like "$SkuPrefix*" } |
    Select-Object name,
        @{ n = 'zones';      e = { $_.locationInfo[0].zones -join ',' } },
        @{ n = 'restricted'; e = { ($_.restrictions.reasonCode | Sort-Object -Unique) -join ',' } } |
    Export-Csv (Join-Path $OutDir 'skus.csv') -NoTypeInformation

# Subnet IP usage (important for Azure CNI without overlay)
$subnetId = az aks nodepool list -g $ResourceGroup --cluster-name $ClusterName --query "[0].vnetSubnetId" -o tsv
if ($subnetId) {
    $sn = (az network vnet subnet show --ids $subnetId -o json) -join "`n" | ConvertFrom-Json
    $prefix = if ($sn.addressPrefix) { $sn.addressPrefix } else { $sn.addressPrefixes -join ',' }
    $size   = [math]::Pow(2, 32 - [int]($prefix -split '/')[1]) - 5   # Azure reserves 5 IPs
    $used   = @($sn.ipConfigurations).Count
    [pscustomobject]@{ Subnet = $sn.name; Prefix = $prefix; Usable = $size; Used = $used; Free = $size - $used } |
        Format-Table -AutoSize | Out-String | Tee-Object -FilePath (Join-Path $OutDir 'subnet.txt')
} else {
    'Managed VNet (no custom subnet).' | Tee-Object -FilePath (Join-Path $OutDir 'subnet.txt')
}
