if (!(Get-Command -ErrorAction SilentlyContinue go)) {
    # install go.
    # see https://community.chocolatey.org/packages/golang
    choco install -y golang --version 1.25.3

    # setup the current process environment.
    $env:GOROOT = 'C:\Program Files\Go'
    $env:PATH += ";$env:GOROOT\bin"

    # setup the Machine environment.
    [Environment]::SetEnvironmentVariable('GOROOT', $env:GOROOT, 'Machine')
    [Environment]::SetEnvironmentVariable(
        'PATH',
        "$([Environment]::GetEnvironmentVariable('PATH', 'Machine'));$env:GOROOT\bin",
        'Machine')

    Write-Host '# go env'
    go env
}
