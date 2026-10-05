param(
    [string]$netbiosDomain,
    [string]$domain,
    [string]$restartService='1'
)

. ./provision-sql-server-common.ps1

Write-Host "Configuring SQL Server to allow encrypted connections at $domain..."
$certificate = Get-ChildItem -DnsName $domain Cert:\LocalMachine\My
$superSocketNetLibPath = Resolve-Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$env:SQL_SERVER_INSTANCE_NAME\MSSQLServer\SuperSocketNetLib"
Set-ItemProperty `
    -Path $superSocketNetLibPath `
    -Name Certificate `
    -Value $certificate.Thumbprint
Set-ItemProperty `
    -Path $superSocketNetLibPath `
    -Name ForceEncryption `
    -Value 0 # NB set to 1 to force all connections to be encrypted.

Write-Host "Granting SQL Server Read permissions to the $domain private key..."
Grant-CPrivateKeyPermission `
    -Path "cert:\LocalMachine\My\$($certificate.Thumbprint)" `
    -Identity "$netbiosDomain\SqlServer$" `
    -Permission Read

if ($restartService -eq '1') {
    Write-Host "Restarting the SQL Server $env:SQL_SERVER_SERVICE_NAME service..."
    Restart-Service $env:SQL_SERVER_SERVICE_NAME -Force
}
