param(
    [string]$action,
    [string]$clusterName,
    [string]$clusterIpAddress
)

Write-Host 'Installing the Failover-Clustering Windows feature...'
Install-WindowsFeature Failover-Clustering -IncludeManagementTools

# set the Domain network interface default gateway.
# NB this is required to use a windows failover cluster.
Write-Host 'Setting the Domain network interface default gateway...'
if (Get-NetRoute -InterfaceAlias Domain -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue) {
    Remove-NetRoute `
        -InterfaceAlias Domain `
        -DestinationPrefix "0.0.0.0/0" `
        -Confirm:$false
}
New-NetRoute `
    -InterfaceAlias Domain `
    -DestinationPrefix "0.0.0.0/0" `
    -NextHop ($clusterIpAddress -replace '\.\d+$','.1') `
    -RouteMetric 271 `
    | Out-Null

if ($action -eq "create") {
    Write-Host "Creating the $clusterName Failover Cluster..."
    $vagrantNetAdapter = Get-NetAdapter Vagrant
    $clusterIgnoreNetworkCidr = ($vagrantNetAdapter | Get-NetIPConfiguration).IPv4Address `
        | Select-Object -First 1 `
        | ForEach-Object {
            "$($_.IPAddress -replace '\.\d+$','.0')/$($_.PrefixLength)"
        }
    $clusterIgnoreNetworkAddress = $clusterIgnoreNetworkCidr -replace '/.+',''
    # NB this will create the $clusterName AD Computer object.
    # NB to be the most compatible, it should have a length of 15 or less characters.
    New-Cluster `
        -Name $clusterName `
        -Node $env:COMPUTERNAME `
        -StaticAddress $clusterIpAddress `
        -IgnoreNetwork $clusterIgnoreNetworkCidr `
        -NoStorage `
        | Out-Null

    Write-Host "Waiting for the $clusterName Failover Cluster to be available..."
    while (!(Get-Cluster -Name $clusterName -ErrorAction SilentlyContinue)) {
        Start-Sleep -Second 5
    }

    Write-Host "Configuring the $clusterName Failover Cluster Network..."
    Set-ClusterExcludedAdapter `
        -ExclusionType IPPrefix `
        -ExclusionValue $clusterIgnoreNetworkCidr
    $vagrantClusterNetwork = Get-ClusterNetwork -Cluster $clusterName | Where-Object { $_.Address -eq $clusterIgnoreNetworkAddress }
    $domainClusterNetwork  = Get-ClusterNetwork -Cluster $clusterName | Where-Object { $_.Address -ne $clusterIgnoreNetworkAddress }
    $vagrantClusterNetwork.Name = 'Vagrant Cluster Network'
    $vagrantClusterNetwork.Role = 'None'
    $domainClusterNetwork.Name = 'Domain Cluster Network'
    $domainClusterNetwork.Role = 'ClusterAndClient'
    Get-ClusterResource -Cluster $clusterName `
        | Where-Object { $_.ResourceType -eq 'IP Address' } `
        | Where-Object {
            ($_ | Get-ClusterParameter -Name Network).Value -ne $domainClusterNetwork.Name
        } `
        | Remove-ClusterResource -Force

    $clusterFileSharePath = "\\DC\fc-storage-${clusterName}"
    Write-Host "Setting the $clusterName Failover Cluster Quorum Share to $clusterFileSharePath..."
    Set-ClusterQuorum `
        -Cluster $clusterName `
        -NodeAndFileShareMajority $clusterFileSharePath
} else {
    Write-Host "Adding the current node to the $clusterName Failover Cluster..."
    Add-ClusterNode `
        -Cluster $clusterName `
        -Name $env:COMPUTERNAME
}

Write-Host "Waiting for the $clusterName Failover Cluster resources to be online..."
while (Get-ClusterResource -Cluster $clusterName | Where-Object State -ne Online) {
    Start-Sleep -Second 5
}

Write-Host "Getting the $clusterName Failover Cluster resources..."
Get-ClusterResource `
    -Cluster $clusterName

Write-Host "Getting the $clusterName Failover Cluster nodes..."
Get-ClusterNode `
    -Cluster $clusterName

Write-Host "Testing the cluster..."
$reportPath = "C:\tmp\sql-server-cluster-validation-report-$env:COMPUTERNAME"
Remove-Item -ErrorAction SilentlyContinue -Force "$reportPath.*"
Test-Cluster `
    -Cluster $clusterName `
    -ReportName $reportPath
