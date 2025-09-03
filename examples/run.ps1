@(
    'examples\powershell\sqlps.ps1'
    'examples\powershell\sqlclient.ps1'
    'examples\powershell\create-database-TheSimpsons.ps1'
    'examples\powershell\use-encrypted-connection.ps1'
    'examples\python\run.ps1'
    'examples\java\run.ps1'
    'examples\csharp\run.ps1'
    'examples\go\run.ps1'
) | ForEach-Object {
    pwsh.exe -File c:\vagrant\ps.ps1 $_
    if ($LASTEXITCODE) {
        throw "failed to run $_ with exit code $LASTEXITCODE"
    }
}
