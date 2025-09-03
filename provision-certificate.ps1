param(
    [string]$clusterFqdn = $null,
    [string]$clusterIp = $null,
    [string]$computerIp = $null
)

# define a function for easing the execution of bash scripts.
$bashPath = 'C:\tools\msys64\usr\bin\bash.exe'
function Bash($script) {
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # we also redirect the stderr to stdout because PowerShell
        # oddly interleaves them.
        # see https://www.gnu.org/software/bash/manual/bash.html#The-Set-Builtin
        Write-Output 'exec 2>&1;set -eu;export PATH="/usr/bin:$PATH"' $script | &$bashPath
        if ($LASTEXITCODE) {
            throw "bash execution failed with exit code $LASTEXITCODE"
        }
    } finally {
        $ErrorActionPreference = $eap
    }
}

# create a testing CA and a certificate for the current machine.
$ca_file_name = 'example-ca'
$ca_common_name = 'Example CA'
Bash @"
mkdir -p /c/vagrant/tmp/ca
cd /c/vagrant/tmp/ca

# see https://www.openssl.org/docs/man1.0.2/apps/x509v3_config.html

# create CA certificate.
if [ ! -f $ca_file_name-crt.pem ]; then
    openssl genrsa \
        -out $ca_file_name-key.pem \
        2048 \
        2>/dev/null
    chmod 400 $ca_file_name-key.pem
    openssl req -new \
        -sha256 \
        -subj "/CN=$ca_common_name" \
        -key $ca_file_name-key.pem \
        -out $ca_file_name-csr.pem
    openssl x509 -req -sha256 \
        -signkey $ca_file_name-key.pem \
        -extensions a \
        -extfile <(echo "[a]
            basicConstraints=critical,CA:TRUE,pathlen:0
            keyUsage=critical,digitalSignature,keyCertSign,cRLSign
            ") \
        -days $(5*365) \
        -in  $ca_file_name-csr.pem \
        -out $ca_file_name-crt.pem
    openssl x509 \
        -in $ca_file_name-crt.pem \
        -outform der \
        -out $ca_file_name-crt.der
    # dump the certificate contents (for logging purposes).
    #openssl x509 -noout -text -in $ca_file_name-crt.pem
fi
"@

Write-Host "Importing $ca_file_name CA..."
Import-Certificate `
    -FilePath "c:\vagrant\tmp\ca\$ca_file_name-crt.der" `
    -CertStoreLocation Cert:\LocalMachine\Root `
    | Out-Null

# if we do not have a cluster fqdn, just bail. the intent was to just create
# and import the CA.
if (!$clusterFqdn) {
    Exit 0
}

# create a certificate for the current machine.
$domain = $env:COMPUTERNAME
$ip = $computerIp
$clusterDomain = $clusterFqdn.ToLowerInvariant()
$clusterHostname = ($clusterFqdn -split '\.')[0].ToUpperInvariant()
Bash @"
mkdir -p /c/vagrant/tmp/ca
cd /c/vagrant/tmp/ca

# see https://www.openssl.org/docs/man1.0.2/apps/x509v3_config.html

# create a server certificate that is usable by SQL Server.
if [ ! -f $domain-crt.pem ]; then
    openssl genrsa \
        -out $domain-key.pem \
        2048 \
        2>/dev/null
    chmod 400 $domain-key.pem
    openssl req -new \
        -sha256 \
        -subj "/CN=$domain" \
        -key $domain-key.pem \
        -out $domain-csr.pem
    openssl x509 -req -sha256 \
        -CA $ca_file_name-crt.pem \
        -CAkey $ca_file_name-key.pem \
        -CAcreateserial \
        -extensions a \
        -extfile <(echo "[a]
            subjectAltName=DNS:$clusterDomain,DNS:$clusterHostname,IP:$clusterIp,DNS:$domain,IP:$ip
            extendedKeyUsage=critical,serverAuth
            ") \
        -days $(5*365) \
        -in  $domain-csr.pem \
        -out $domain-crt.pem
    openssl pkcs12 -export \
        -keyex \
        -inkey $domain-key.pem \
        -in $domain-crt.pem \
        -certfile $domain-crt.pem \
        -passout pass: \
        -out $domain-key.p12
    # dump the certificate contents (for logging purposes).
    #openssl x509 -noout -text -in $domain-crt.pem
    #openssl pkcs12 -info -nodes -passin pass: -in $domain-key.p12
fi
"@

Write-Host "Importing $domain p12..."
Import-PfxCertificate `
    -FilePath "c:\vagrant\tmp\ca\$domain-key.p12" `
    -CertStoreLocation Cert:\LocalMachine\My `
    -Password $null `
    -Exportable `
    | Out-Null
