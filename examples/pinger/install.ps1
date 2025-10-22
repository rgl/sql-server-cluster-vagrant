. ../../provision-go.ps1

Write-Host '# build and run'
$path = "C:\pinger"
if (Test-Path $path) {
    Remove-Item -Recurse -Force $path
}
Copy-Item -Recurse "c:\vagrant\examples\pinger" $path
Push-Location $path
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
Pop-Location
