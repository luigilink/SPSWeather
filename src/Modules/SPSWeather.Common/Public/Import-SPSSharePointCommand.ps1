function Import-SPSSharePointCommand {
    <#
        .SYNOPSIS
        Loads the SharePoint Server Subscription Edition command surface.

        .DESCRIPTION
        SharePoint Server Subscription Edition ships the `SharePointServer` PowerShell
        module (the legacy `Microsoft.SharePoint.PowerShell` PSSnapin is no longer
        registered). This function imports that module. It is idempotent: if the
        module is already loaded it does nothing. Running SPSWeather through plain
        `powershell.exe` (e.g. a scheduled task) therefore no longer requires the
        SharePoint Management Shell.

        Throws when SharePoint is not installed on the host.

        Returns the string 'SharePointServer' (the loading mechanism used) so callers
        can log which surface was loaded.

        .EXAMPLE
        Import-SPSSharePointCommand
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    if ($null -eq (Get-SPSInstalledProductVersion)) {
        throw 'SharePoint is not installed on this server (Microsoft.SharePoint.dll not found). Run this on a SharePoint Server Subscription Edition server.'
    }

    if (-not (Get-Module -Name SharePointServer)) {
        Import-Module -Name SharePointServer -Verbose:$false -WarningAction SilentlyContinue -DisableNameChecking
    }
    return 'SharePointServer'
}
