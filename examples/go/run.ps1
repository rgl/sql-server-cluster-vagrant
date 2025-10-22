. ../../provision-sql-server-common.ps1

. ../../provision-go.ps1

Write-Host '# build and run'
Start-Example go {
    $p = Start-Process go 'build','-v' `
        -RedirectStandardOutput build-stdout.txt `
        -RedirectStandardError build-stderr.txt `
        -Wait `
        -PassThru
    Write-Output (Get-Content build-stdout.txt,build-stderr.txt)
    Remove-Item build-stdout.txt,build-stderr.txt
    if ($p.ExitCode) {
        throw "Failed to compile"
    }
    .\go.exe
    if ($LASTEXITCODE) {
        throw "failed with exit code $LASTEXITCODE"
    }
}
