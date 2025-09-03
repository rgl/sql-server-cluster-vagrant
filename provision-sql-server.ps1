param(
    [string]$domain='example.test',
    [string]$fcName='SQL-CLUSTER',
    [string]$action,
    [string]$aglName='SQL',
    [string]$aglIpAddress='10.20.20.101'
)

. ./provision-sql-server-common.ps1

$netbiosDomain = ($domain -split '\.')[0].ToUpperInvariant()
$mirroringEndpointName = 'hadr_endpoint'
$mirroringEndpointPort = 5022
$primaryComputerName = $env:COMPUTERNAME -replace '\d+$','1'
$secondaryComputerName = $env:COMPUTERNAME -replace '\d+$','2'
$primaryReplicaMirroringEndpointUrl = "TCP://${primaryComputerName}.${domain}:$mirroringEndpointPort"
$secondaryReplicaMirroringEndpointUrl = "TCP://${secondaryComputerName}.${domain}:$mirroringEndpointPort"

Write-Host 'Creating the firewall rule to allow inbound access to the SQL Server TCP/IP port 1433...'
New-NetFirewallRule `
    -Name 'SQL-SERVER-In-TCP' `
    -DisplayName 'SQL Server (TCP-In)' `
    -Direction Inbound `
    -Enabled True `
    -Protocol TCP `
    -LocalPort 1433 `
    | Out-Null

Write-Host 'Creating the firewall rule to allow inbound access to the SQL Server Browser UDP/IP port 1434...'
New-NetFirewallRule `
    -Name 'SQL-SERVER-BROWSER-In-UDP' `
    -DisplayName 'SQL Server Browser (UDP-In)' `
    -Direction Inbound `
    -Enabled True `
    -Protocol UDP `
    -LocalPort 1434 `
    | Out-Null

Write-Host "Creating the firewall rule to allow inbound access to the SQL Server Mirroring TCP/IP port $mirroringEndpointPort..."
New-NetFirewallRule `
    -Name 'SQL-SERVER-MIRRORING-In-TCP' `
    -DisplayName 'SQL Server Mirroring (TCP-In)' `
    -Direction Inbound `
    -Enabled True `
    -Protocol TCP `
    -LocalPort $mirroringEndpointPort `
    | Out-Null

# download.
$setupPath = Get-SqlServerSetup

# install.
# NB this cannot be executed from a network share (e.g. c:\vagrant).
# NB the logs are saved at "$env:ProgramFiles\Microsoft SQL Server\<version>\Setup Bootstrap\Log\<YYYYMMDD_HHMMSS>".
#    e.g. "C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log"
# NB you could also use /INDICATEPROGRESS to make the setup write the logs to
#    stdout in realtime.
# see https://learn.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt?view=sql-server-ver16#integrated-install-failover-cluster-parameters
# see https://learn.microsoft.com/en-us/sql/sql-server/failover-clusters/install/create-a-new-sql-server-failover-cluster-setup?view=sql-server-ver16
# see https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/create-an-availability-group-sql-server-powershell?
Write-Host "Installing SQL Server..."
# NB the setup data path parameters are:
#       /INSTALLSQLDATADIR    System database directory
#       /SQLUSERDBDIR         User database directory
#       /SQLUSERDBLOGDIR      User database log directory
#       /SQLTEMPDBDIR         TempDB data directory
#       /SQLTEMPDBLOGDIR      TempDB log directory
#       /SQLBACKUPDIR         Backup directory
# NB when using the setup wizard, it sets /INSTALLSQLDATADIR, /SQLUSERDBDIR,
#    /SQLUSERDBLOGDIR, /SQLTEMPDBDIR, and /SQLTEMPDBLOGDIR to the same
#    directory path.
$dataRootPath = "C:\sql-server-storage"
&$setupPath `
    /IACCEPTSQLSERVERLICENSETERMS `
    /QUIET `
    /ACTION=Install `
    /FEATURES=SQLENGINE,REPLICATION `
    /UPDATEENABLED=0 `
    /INSTANCEID="$env:SQL_SERVER_INSTANCE_NAME" `
    /INSTANCENAME="$env:SQL_SERVER_INSTANCE_NAME" `
    /SQLSVCACCOUNT="$netbiosDomain\SqlServer$" `
    /AGTSVCACCOUNT="$netbiosDomain\SqlServerAgent$" `
    /SQLSYSADMINACCOUNTS="$env:USERDOMAIN\$env:USERNAME" `
    /INSTALLSQLDATADIR="$dataRootPath\Data" `
    /SQLUSERDBDIR="$dataRootPath\Data" `
    /SQLUSERDBLOGDIR="$dataRootPath\Data" `
    /SQLTEMPDBDIR="$dataRootPath\Data" `
    /SQLTEMPDBLOGDIR="$dataRootPath\Data" `
    /SQLBACKUPDIR="$dataRootPath\Backup"
if ($LASTEXITCODE) {
    $logsPath = Resolve-path "C:\Program Files\Microsoft SQL Server\*\Setup Bootstrap\Log"
    throw "failed with exit code $LASTEXITCODE. see the logs at $logsPath."
}

Write-Host "Configuring the SQL Server TLS certificate..."
PowerShell.exe -File ps.ps1 `
    provision-sql-server-network-encryption.ps1 `
    $netbiosDomain `
    "$aglName.$domain".ToLowerInvariant()
if ($LASTEXITCODE) {
    throw "failed with exit code $LASTEXITCODE."
}

# NB this makes it easier to connect to the named instance from SQL Server
#    Management Studio; e.g., we can use SQL1\SQLSERVER instead of
#    SQL1\SQLSERVER,1433.
Write-Host "Enabling and starting the SQL Server Browser service..."
Set-Service -Name SQLBrowser -StartupType Automatic
Start-Service -Name SQLBrowser

# install the SqlServer PowerShell Module.
# see https://www.powershellgallery.com/packages/Sqlserver
# see https://learn.microsoft.com/en-us/powershell/module/sqlserver/?view=sqlserver-ps
# see https://learn.microsoft.com/en-us/sql/powershell/download-sql-server-ps-module?view=sql-server-ver16
Write-Host "Installing the SqlServer PowerShell module..."
Install-Module SqlServer -AllowClobber -RequiredVersion 22.4.5.1

# update $env:PSModulePath to include the modules installed by recently installed package.
$env:PSModulePath = "$([Environment]::GetEnvironmentVariable('PSModulePath', 'User'));$([Environment]::GetEnvironmentVariable('PSModulePath', 'Machine'))"

Import-Module SqlServer

# set the tcp port.
# NB the sql server service must be restarted for this to take effect.
Write-Host "Setting the SQL Server TCP port..."
$regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$env:SQL_SERVER_INSTANCE_NAME\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
Set-ItemProperty -Path $regPath -Name TcpPort -Value '1433'
Set-ItemProperty -Path $regPath -Name TcpDynamicPorts -Value ''
Set-ItemProperty -Path "$regPath\.." -Name Enabled -Value 1
# NB we do not restart the sql server service here because it will be restarted
#    when we call Enable-SqlAlwaysOn bellow.
# if ((Get-Service $env:SQL_SERVER_SERVICE_NAME).Status -eq 'Running') {
#     Restart-Service $env:SQL_SERVER_SERVICE_NAME -Force
# }

Write-Host 'Enabling Mixed Mode Authentication...'
$server = New-Object Microsoft.SqlServer.Management.Smo.Server "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME"
$server.Settings.LoginMode = 'Mixed'
$server.Alter()

Write-Host "Creating the $netbiosDomain\SQL Server Administrators group login as a sysadmin..."
$sqlServerAdministratorsGroupName = "$netbiosDomain\SQL Server Administrators"
$server = New-Object Microsoft.SqlServer.Management.Smo.Server("$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME")
$login = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $sqlServerAdministratorsGroupName)
$login.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::WindowsGroup
$login.Create()
$server.Roles['sysadmin'].AddMember($sqlServerAdministratorsGroupName)

Write-Host "Creating the $netbiosDomain\SqlServer$ account login as a regular user..."
$server = New-Object Microsoft.SqlServer.Management.Smo.Server("$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME")
$login = New-Object Microsoft.SqlServer.Management.Smo.Login($server, "$netbiosDomain\SqlServer$")
$login.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::WindowsUser
$login.Create()

# create the test users.
$testUsers = @(
    'alice.doe'
    'bob.doe'
    'carol.doe'
    'dave.doe'
    'eve.doe'
)
# create SQL Server accounts.
$testUsersSidsPath = 'C:\vagrant\tmp\test-users-sids.json'
$testUsersSids = if ($action -eq 'create') {
    @{}
} else {
    $data = @{}
    (Get-Content -Raw $testUsersSidsPath | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
        $data[$_.Name] = $_.Value
    }
    $data
}
$testUsers | ForEach-Object {
    Write-Host "Creating the $_ SQL Server login..."
    $login = New-Object Microsoft.SqlServer.Management.Smo.Login "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME",$_
    $login.LoginType = 'SqlLogin'
    $login.PasswordPolicyEnforced = $false
    $login.PasswordExpirationEnabled = $false
    if ($action -ne 'create') {
        $login.Sid = $testUsersSids[$_]
    }
    $login.Create('HeyH0Password')
    if ($action -eq 'create') {
        $testUsersSids[$_] = $login.Sid
    }
}
if ($action -eq 'create') {
    Set-Content `
        $testUsersSidsPath `
        ($testUsersSids | ConvertTo-Json -Compress -Depth 10)
}
# grant sysadmin permissions to alice.doe.
$server = New-Object Microsoft.SqlServer.Management.Smo.Server "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME"
$sysadminRole = $server.Roles['sysadmin']
$sysadminRole.AddMember('alice.doe')
$sysadminRole.Alter()

Write-Host 'SQL Server Version:'
$versionResult = Invoke-Sqlcmd `
    -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Query "select @@version as Version"
Write-Output $versionResult.Version

# enable always on and restart sql server.
Write-Host "Enabling Always On Availability Groups..."
Enable-SqlAlwaysOn `
    -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Force

# verify that always on is enabled.
Write-Host "Verifying that Always On Availability Groups is enabled..."
$result = Invoke-Sqlcmd `
    -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Query "select serverproperty('IsHadrEnabled') as IsHadrEnabled"
if ($result.IsHadrEnabled -ne 1) {
    throw "failed to enable Always On."
}

Write-Host "Creating the database mirroring endpoint..."
$mirroringEndpoint = New-SqlHadrEndpoint `
    -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Name $mirroringEndpointName `
    -Port $mirroringEndpointPort

Write-Host "Granting the $netbiosDomain\SqlServer$ account connect access to the $mirroringEndpointName endpoint..."
Invoke-Sqlcmd `
    -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
    -Query "grant connect on endpoint::[$mirroringEndpointName] to [$netbiosDomain\SqlServer$]"

Write-Host "Starting the database mirroring endpoint..."
Set-SqlHadrEndpoint `
    -InputObject $mirroringEndpoint `
    -State Started `
    | Out-Null

Write-Host "Verifying the database mirroring endpoint..."
$endpoint = Get-Item "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME\Endpoints\$mirroringEndpointName"
if ($endpoint.EndpointState -ne 'Started') {
    throw "the database mirroring endpoint is not started. instead its on the $($endpoint.EndpointState) state."
}

if ($action -eq 'create') {
    Write-Host "Creating the $aglName Availability Group with the $primaryComputerName and $secondaryComputerName computers..."
    $versionResult = Invoke-Sqlcmd `
        -ServerInstance "$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
        -Query "select serverproperty('ProductVersion') as version"
    $version = ($versionResult.version -split '\.')[0..1] -join '.'
    $primaryReplica = New-SqlAvailabilityReplica `
        -Name "$primaryComputerName\$env:SQL_SERVER_INSTANCE_NAME" `
        -EndpointURL $primaryReplicaMirroringEndpointUrl `
        -AvailabilityMode SynchronousCommit `
        -FailoverMode Automatic `
        -SeedingMode Automatic `
        -Version $version `
        -AsTemplate
    $secondaryReplica = New-SqlAvailabilityReplica `
        -Name "$secondaryComputerName\$env:SQL_SERVER_INSTANCE_NAME" `
        -EndpointURL $secondaryReplicaMirroringEndpointUrl `
        -AvailabilityMode SynchronousCommit `
        -FailoverMode Automatic `
        -SeedingMode Automatic `
        -Version $version `
        -AsTemplate
    # NB this will appear as a Role in the Windows Failover Cluster.
    New-SqlAvailabilityGroup `
        -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
        -Name $aglName `
        -AvailabilityReplica @($primaryReplica, $secondaryReplica) `
        | Out-Null
} else {
    Write-Host "Joining the $aglName Availability Group..."
    Join-SqlAvailabilityGroup `
        -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME" `
        -Name $aglName
}

Write-Host "Granting the $aglName Availability Group permissions to create any database..."
Grant-SqlAvailabilityGroupCreateAnyDatabase `
    -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME\AvailabilityGroups\$aglName"

Write-Host "Getting the $aglName Availability Group status..."
Get-ChildItem `
    -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME\AvailabilityGroups\$aglName\AvailabilityReplicas" `
    | Format-Table

if ($action -eq 'create') {
    Write-Host "Creating the $aglName Availability Group Listener..."
    # NB this will create the $aglName Computer account in the DC.
    New-SqlAvailabilityGroupListener `
        -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\$env:SQL_SERVER_INSTANCE_NAME\AvailabilityGroups\$aglName" `
        -Name $aglName `
        -StaticIp "$aglIpAddress/255.255.255.0" `
        -Port 1433 `
        | Out-Null
}
