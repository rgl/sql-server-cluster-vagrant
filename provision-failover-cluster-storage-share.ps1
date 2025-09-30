param(
    [string]$clusterName
)

$shareName = "fc-storage-${clusterName}"
$sharePath = "C:\$shareName"
# TODO limit this to the windows failover cluster computer account (e.g.
#      SQLC$). that is, do not let every computer create a folder in
#      this directory.
$accounts = @(
    "Domain Computers"
)

# create the failover cluster storage smb share directory.
New-Item -Path $sharePath -ItemType Directory | Out-Null
$acl = Get-Acl $sharePath
$acl.SetAccessRuleProtection($true, $false)
$acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
@(
    "SYSTEM",
    "Administrators"
) | ForEach-Object {
    $acl.AddAccessRule((
        New-Object System.Security.AccessControl.FileSystemAccessRule(
            $_,
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )))
}
$acl.AddAccessRule((
    New-Object System.Security.AccessControl.FileSystemAccessRule(
        "CREATOR OWNER",
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "InheritOnly",
        "Allow"
    )))
$accounts | ForEach-Object {
    $acl.AddAccessRule((
        New-Object System.Security.AccessControl.FileSystemAccessRule(
            $_,
            "CreateDirectories",
            "None",
            "None",
            "Allow"
        )))
}
Set-Acl -Path $sharePath -AclObject $acl

# create the failover cluster storage smb share.
New-SmbShare -Name $shareName -Path $sharePath -FullAccess $accounts
