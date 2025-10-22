# see https://community.chocolatey.org/packages/sql-server-management-studio
choco install -y sql-server-management-studio --version 21.6.17

# install the SqlServer PowerShell Module.
# see https://www.powershellgallery.com/packages/Sqlserver
# see https://learn.microsoft.com/en-us/powershell/module/sqlserver/?view=sqlserver-ps
# see https://learn.microsoft.com/en-us/sql/powershell/download-sql-server-ps-module?view=sql-server-ver16
Write-Host "Installing the SqlServer PowerShell module..."
Install-Module SqlServer -AllowClobber -RequiredVersion 22.4.5.1
