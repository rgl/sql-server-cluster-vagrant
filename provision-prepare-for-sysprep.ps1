# remove appx packages that prevent sysprep from working.
# NB without this, sysprep will fail with:
#       2024-12-14 14:08:40, Error                 SYSPRP Package Microsoft.MicrosoftEdge.Stable_131.0.2903.99_neutral__8wekyb3d8bbwe was installed for a user, but not provisioned for all users. This package will not function properly in the sysprep image.
#       2025-06-25 20:31:48, Error                 SYSPRP Package Microsoft.Edge.GameAssist_1.0.3336.0_x64__8wekyb3d8bbwe was installed for a user, but not provisioned for all users. This package will not function properly in the sysprep image.
# NB you can list all the appx and which users have installed them:
#       Get-AppxPackage -AllUsers | Format-List PackageFullName,PackageUserInformation
# see https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/sysprep-fails-remove-or-update-store-apps#cause
Write-Host "Removing appx packages that prevent sysprep from working..."
Get-AppxPackage -AllUsers `
    | Where-Object { $_.PackageUserInformation.InstallState -eq 'Installed' } `
    | Where-Object {
        $_.PackageFullName -like 'Microsoft.MicrosoftEdge.*' -or `
        $_.PackageFullName -like 'Microsoft.Edge.GameAssist*' -or `
        $_.PackageFullName -like 'NotepadPlusPlus*'
    } `
    | ForEach-Object {
        Write-Host "Removing the $($_.PackageFullName) appx package..."
        Remove-AppxPackage -AllUsers -Package $_.PackageFullName
    }
