param(
    [string]$domain='example.test'
)

$credential = New-Object `
    System.Management.Automation.PSCredential(
        "vagrant@$domain",
        (ConvertTo-SecureString "vagrant" -AsPlainText -Force))

Invoke-Command -ComputerName DC -Credential $credential {
    function Get-AccountServicePrincipals {
        Write-Host "Account Service Principals"
        Get-ADObject `
            -LDAPFilter "(servicePrincipalName=*)" `
            -Properties DistinguishedName,ServicePrincipalName `
            | ForEach-Object {
                $dn = $_.DistinguishedName
                $_.ServicePrincipalName | ForEach-Object {
                    [PSCustomObject]@{
                        DistinguishedName = $dn
                        ServicePrincipalName = $_
                    }
                }
            }
    }

    $accountServicePrincipals = Get-AccountServicePrincipals `
        | Sort-Object DistinguishedName,ServicePrincipalName

    $maxLength = $accountServicePrincipals | ForEach-Object {
        [PSCustomObject]@{
            DistinguishedName = $_.DistinguishedName.Length
            ServicePrincipalName = $_.ServicePrincipalName.Length
        }
    } `
    | Measure-Object `
        -Property DistinguishedName,ServicePrincipalName `
        -Maximum
    $distinguishedNameLength = $maxLength[0].Maximum
    $servicePrincipalNameLength = $maxLength[1].Maximum

    "| Account Distinguished Name$(' ' * ($distinguishedNameLength - 26)) | Service Principal Name$(' ' * ($servicePrincipalNameLength - 22)) |"
    "|-$('-' * $distinguishedNameLength)-|-$('-' * $servicePrincipalNameLength)-|"
    $accountServicePrincipals | ForEach-Object {
        "| $($_.DistinguishedName)$(' ' * ($distinguishedNameLength - $_.DistinguishedName.Length)) | $($_.ServicePrincipalName)$(' ' * ($servicePrincipalNameLength - $_.ServicePrincipalName.Length)) |"
    }
}
