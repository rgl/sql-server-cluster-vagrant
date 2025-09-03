$adDomain = Get-ADDomain
$domain = $adDomain.DNSRoot
$domainDn = $adDomain.DistinguishedName
$usersAdPath = "CN=Users,$domainDn"
$msaAdPath = "CN=Managed Service Accounts,$domainDn"
$password = ConvertTo-SecureString -AsPlainText 'HeyH0Password' -Force


# configure the AD to allow the use of Group Managed Service Accounts (gMSA).
# see https://docs.microsoft.com/en-us/windows-server/security/group-managed-service-accounts/group-managed-service-accounts-overview
# see https://docs.microsoft.com/en-us/windows-server/security/group-managed-service-accounts/create-the-key-distribution-services-kds-root-key
# NB we cannot use -EffectiveImmediately because it would still wait 10h for
#    the KDS root key to propagate, instead, we force the time to 10h ago to
#    make it really immediate.
Add-KdsRootKey -EffectiveTime (Get-Date).AddHours(-10) | Out-Null


# remove the non-routable vagrant nat ip address from dns.
# NB this is needed to prevent the non-routable ip address from
#    being registered in the dns server.
# NB the nat interface is the first dhcp interface of the machine.
$vagrantNatAdapter = Get-NetAdapter -Physical `
    | Where-Object {$_ | Get-NetIPAddress | Where-Object {$_.PrefixOrigin -eq 'Dhcp'}} `
    | Sort-Object -Property Name `
    | Select-Object -First 1
$vagrantNatIpAddress = ($vagrantNatAdapter | Get-NetIPAddress).IPv4Address
# remove the $domain nat ip address resource records from dns.
$vagrantNatAdapter | Set-DnsClient -RegisterThisConnectionsAddress $false
Get-DnsServerResourceRecord -ZoneName $domain -Type 1 `
    | Where-Object {$_.RecordData.IPv4Address -eq $vagrantNatIpAddress} `
    | Remove-DnsServerResourceRecord -ZoneName $domain -Force
# disable ipv6.
$vagrantNatAdapter | Disable-NetAdapterBinding -ComponentID ms_tcpip6
# remove the dc.$domain nat ip address resource record from dns.
$dnsServerSettings = Get-DnsServerSetting -All
$dnsServerSettings.ListeningIPAddress = @(
        $dnsServerSettings.ListeningIPAddress `
            | Where-Object {$_ -ne $vagrantNatIpAddress}
    )
Set-DnsServerSetting $dnsServerSettings
# flush the dns client cache.
Clear-DnsClientCache


# add the vagrant user to the Enterprise Admins group.
# NB this is needed to install the Enterprise Root Certification Authority.
Add-ADGroupMember `
    -Identity 'Enterprise Admins' `
    -Members "CN=vagrant,$usersAdPath"


# disable all user accounts, except the ones defined here.
$enabledAccounts = @(
    # NB vagrant only works when this account is enabled.
    'vagrant',
    'Administrator'
)
Get-ADUser -Filter {Enabled -eq $true} `
    | Where-Object {$enabledAccounts -notcontains $_.Name} `
    | Disable-ADAccount


# set the Administrator password.
# NB this is also an Domain Administrator account.
Set-ADAccountPassword `
    -Identity "CN=Administrator,$usersAdPath" `
    -Reset `
    -NewPassword $password
Set-ADUser `
    -Identity "CN=Administrator,$usersAdPath" `
    -PasswordNeverExpires $true


# create the SQL Server Administrators groups.
New-ADGroup `
    -Path $usersAdPath `
    -Name 'SQL Server Administrators' `
    -Description 'Members of this group are System Administrators in SQL Server' `
    -GroupCategory 'Security' `
    -GroupScope 'DomainLocal'

# add the vagrant user to the SQL Server Administrators group.
Add-ADGroupMember `
    -Identity 'SQL Server Administrators' `
    -Members "CN=vagrant,$usersAdPath"


# create the John Doe user as a Domain Admin.
$name = 'john.doe'
New-ADUser `
    -Path $usersAdPath `
    -Name $name `
    -UserPrincipalName "$name@$domain" `
    -EmailAddress "$name@$domain" `
    -GivenName 'John' `
    -Surname 'Doe' `
    -DisplayName 'John Doe' `
    -AccountPassword $password `
    -Enabled $true `
    -PasswordNeverExpires $true
Add-ADGroupMember `
    -Identity 'Domain Admins' `
    -Members "CN=$name,$usersAdPath"

# create the Jane Doe user as a SQL Server Administrator.
$name = 'jane.doe'
New-ADUser `
    -Path $usersAdPath `
    -Name $name `
    -UserPrincipalName "$name@$domain" `
    -EmailAddress "$name@$domain" `
    -GivenName 'Jane' `
    -Surname 'Doe' `
    -DisplayName 'Jane Doe' `
    -AccountPassword $password `
    -Enabled $true `
    -PasswordNeverExpires $true
Add-ADGroupMember `
    -Identity 'SQL Server Administrators' `
    -Members "CN=$name,$usersAdPath"
# NB Print Operators is used as the easiest way for a user to have the
#    "Allow logon locally" user right.
Add-ADGroupMember `
    -Identity 'Print Operators' `
    -Members "CN=$name,$usersAdPath"


# create the SqlServer group Managed Service Account (gMSA).
# NB computer principals (or security group of computer principals) need
#    to be explicitly allowed to use the gMSA with one of the following
#    cmdlets:
#       Set-ADServiceAccount
#       Add-ADComputerServiceAccount
# NB you can use this account to run a windows service by using the
#    SQL\SqlServer$ account name and an empty password.
@(
    'SqlServer'
    'SqlServerAgent'
) | ForEach-Object {
    New-ADServiceAccount `
        -Path $msaAdPath `
        -DNSHostName $domain `
        -Name $_
    # allow any domain controller/computer the use the gMSA.
    # NB to known which security groups this computer is member of, execute:
    #       Get-ADPrincipalGroupMembership "$env:COMPUTERNAME`$"
    Set-ADServiceAccount `
        -Identity $_ `
        -PrincipalsAllowedToRetrieveManagedPassword @(
            ,"CN=Domain Controllers,$usersAdPath"
            ,"CN=Domain Computers,$usersAdPath"
        )
    # test whether this computer can use the gMSA.
    Test-ADServiceAccount `
        -Identity $_ `
        | Out-Null
}


# install the Windows Failover Cluster management tools.
Write-Host 'Installing the Windows Failover Cluster management tools...'
Install-WindowsFeature RSAT-Clustering-Mgmt,RSAT-Clustering-PowerShell
