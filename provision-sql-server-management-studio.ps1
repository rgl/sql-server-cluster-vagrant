# see https://community.chocolatey.org/packages/sql-server-management-studio
choco install -y sql-server-management-studio --version 22.10.2

# install the SqlServer PowerShell Module.
# see https://www.powershellgallery.com/packages/Sqlserver
# see https://learn.microsoft.com/en-us/powershell/module/sqlserver/?view=sqlserver-ps
# see https://learn.microsoft.com/en-us/sql/powershell/download-sql-server-ps-module?view=sqlserver-ps
Write-Host "Installing the SqlServer PowerShell module..."
Install-Module SqlServer -AllowClobber -RequiredVersion 22.4.5.1
