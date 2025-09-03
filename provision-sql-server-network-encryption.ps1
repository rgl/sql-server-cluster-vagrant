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
# NB this originally came from http://stackoverflow.com/questions/17185429/how-to-grant-permission-to-private-key-from-powershell/22146915#22146915
function Get-PrivateKeyContainerPath() {
    param(
        [Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()]$name,
        [Parameter(Mandatory=$true)][boolean]$isCng
    )
    if ($isCng) {
        $searchDirectories = @('Microsoft\Crypto\Keys', 'Microsoft\Crypto\SystemKeys')
    } else {
        $searchDirectories = @('Microsoft\Crypto\RSA\MachineKeys', 'Microsoft\Crypto\RSA\S-1-5-18', 'Microsoft\Crypto\RSA\S-1-5-19', 'Crypto\DSS\S-1-5-20')
    }
    $commonApplicationDataDirectory = [Environment]::GetFolderPath('CommonApplicationData')
    foreach ($searchDirectory in $searchDirectories) {
        $privateKeyFile = Get-ChildItem -Path "$commonApplicationDataDirectory\$searchDirectory" -Filter $name -Recurse
        if ($privateKeyFile) {
            return $privateKeyFile.FullName
        }
    }
    throw "cannot find private key file path for the $name key container"
}
Add-Type -Path '.\Security.Cryptography.dll' # from https://clrsecurity.codeplex.com/
function Grant-PrivateKeyReadPermissions($certificate, $accountName) {
    if ([Security.Cryptography.X509Certificates.X509CertificateExtensionMethods]::HasCngKey($certificate)) {
        $privateKey = [Security.Cryptography.X509Certificates.X509Certificate2ExtensionMethods]::GetCngPrivateKey($certificate)
        $keyContainerName = $privateKey.UniqueName
        $privateKeyPath = Get-PrivateKeyContainerPath $keyContainerName $true
    } elseif ($certificate.PrivateKey) {
        $privateKey = $certificate.PrivateKey
        $keyContainerName = $certificate.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
        $privateKeyPath = Get-PrivateKeyContainerPath $keyContainerName $false
    } else {
        throw 'certificate does not have a private key, or that key is inaccessible, therefore permission cannot be granted'
    }
    $acl = Get-Acl -Path $privateKeyPath
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule @($accountName, 'Read', 'Allow')))
    Set-Acl $privateKeyPath $acl
}
Grant-PrivateKeyReadPermissions $certificate "$netbiosDomain\SqlServer$"

if ($restartService -eq '1') {
    Write-Host "Restarting the SQL Server $env:SQL_SERVER_SERVICE_NAME service..."
    Restart-Service $env:SQL_SERVER_SERVICE_NAME -Force
}
