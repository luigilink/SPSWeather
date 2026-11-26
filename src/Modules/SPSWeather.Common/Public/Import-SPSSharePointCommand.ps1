function Import-SPSSharePointCommand {
    <#
        .SYNOPSIS
        Loads the SharePoint command surface in a version-aware way.

        .DESCRIPTION
        SharePoint exposes its cmdlets differently depending on the release:

        - SharePoint 2013 / 2016 / 2019 ship the `Microsoft.SharePoint.PowerShell`
          PSSnapin.
        - SharePoint Subscription Edition ships the `SharePointServer` PowerShell
          module instead, and no longer registers the snap-in.

        This function detects the installed product version with
        Get-SPSInstalledProductVersion and loads the right one. It is idempotent: if
        the snap-in or module is already loaded, it does nothing. Running SPSWeather
        through plain powershell.exe (e.g. a scheduled task) therefore no longer
        requires the SharePoint Management Shell.

        Returns the loading mechanism used: 'PSSnapin' or 'SharePointServer'. Throws
        when SharePoint is not installed on the host.

        .EXAMPLE
        Import-SPSSharePointCommand
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    $version = Get-SPSInstalledProductVersion
    if ($null -eq $version) {
        throw 'SharePoint is not installed on this server (Microsoft.SharePoint.dll not found). Run this on a SharePoint server.'
    }

    if ($version.ProductMajorPart -eq 15 -or $version.ProductBuildPart -le 12999) {
        # SharePoint 2013 / 2016 / 2019 -> PSSnapin
        if ($null -eq (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)) {
            Add-PSSnapin Microsoft.SharePoint.PowerShell
        }
        return 'PSSnapin'
    }
    else {
        # SharePoint Subscription Edition -> SharePointServer module
        if (-not (Get-Module -Name SharePointServer)) {
            Import-Module -Name SharePointServer -Verbose:$false -WarningAction SilentlyContinue -DisableNameChecking
        }
        return 'SharePointServer'
    }
}
