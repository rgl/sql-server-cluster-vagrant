param(
    [Parameter(Mandatory=$true)]
    [String]$script,
    [Parameter(ValueFromRemainingArguments=$true)]
    [String[]]$scriptArguments,
    [Parameter(Mandatory=$false)]
    [switch]$ExecAsDomainAdmin
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1' | Write-Host
    Exit 1
}

# enable TLS 1.1 and 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol `
    -bor [Net.SecurityProtocolType]::Tls11 `
    -bor [Net.SecurityProtocolType]::Tls12

# wrap the choco command (to make sure this script aborts when it fails).
function Start-Choco([string[]]$Arguments, [int[]]$SuccessExitCodes=@(0)) {
    $command, $commandArguments = $Arguments
    if ($command -eq 'install') {
        $Arguments = @($command, '--no-progress') + $commandArguments
    }
    for ($n = 0; $n -lt 10; ++$n) {
        if ($n) {
            # NB sometimes choco fails with "The package was not found with the source(s) listed."
            #    but normally its just really a transient "network" error.
            Write-Host "Retrying choco install..."
            Start-Sleep -Seconds 3
        }
        &C:\ProgramData\chocolatey\bin\choco.exe @Arguments
        if ($SuccessExitCodes -Contains $LASTEXITCODE) {
            return
        }
    }
    throw "$(@('choco')+$Arguments | ConvertTo-Json -Compress) failed with exit code $LASTEXITCODE"
}
function choco {
    Start-Choco $Args
}

function Start-Example([string]$name, [scriptblock]$script) {
    $path = "$env:TEMP\$name"
    if (Test-Path $path) {
        Remove-Item -Recurse -Force $path
    }
    Copy-Item -Recurse "c:\vagrant\examples\$name" $path
    Push-Location $path
    &$script
    Pop-Location
}

if ($ExecAsDomainAdmin) {
    # copy the required files to c:\tmp.
    # NB execst will execute our script as an domain admin user, which does not
    #    have access to the c:\vagrant share, so we have to copy the files to
    #    a location that the domain admin user can access.
    Push-Location c:\vagrant
    @(
        $script
        'ps.ps1'
        'provision-sql-server-common.ps1'
        'provision-sql-server-network-encryption.ps1'
        'examples\powershell\common.ps1'
    ) | Where-Object { -not (Test-Path "c:\tmp\$_") } | ForEach-Object {
        $parent = Split-Path $_ -Parent
        if ($parent) {
            New-Item -ItemType Directory -Path "c:\tmp\$parent" -Force | Out-Null
        }
        Copy-Item $_ "c:\tmp\$_"
    }
    . c:\tmp\provision-sql-server-common.ps1
    Get-SqlServerSetup
    Pop-Location
    $env:EXECST_USERNAME = $env:DC_ADMIN_USERNAME
    $env:EXECST_PASSWORD = $env:DC_ADMIN_PASSWORD
    execst `
        --env EXECST=1 `
        --workdir c:\tmp `
        -- `
        powershell `
            -file ps.ps1 `
            $script `
            @scriptArguments
    Exit $LASTEXITCODE
}

if ($env:EXECST -eq "1") {
    Set-Location c:\tmp
} else {
    Set-Location c:\vagrant
}
$script = Resolve-Path $script
Set-Location (Split-Path $script -Parent)
Write-Host "Running $script..."
. $script @scriptArguments
