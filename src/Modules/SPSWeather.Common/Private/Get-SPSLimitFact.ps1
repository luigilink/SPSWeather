function Get-SPSLimitFact {
    <#
        .SYNOPSIS
        Reads, once, the facts that the supported limits of SharePoint are checked against.

        .DESCRIPTION
        One read-only remote call to the farm entry point. It gathers facts only, never a judgement (that is
        Get-SPSLimitStatus): the content databases with their number of site collections, the number of web applications, the managed
        paths of each web application and the host-named ones. The thresholds never travel to the remote side.

        The facts of a database that uses Remote BLOB Storage say so (Rbs), because the 200 GB limit includes the external BLOBs, which
        no SQL query sees. A failure to read anything is returned as an Error text, never thrown.

        .PARAMETER Server
        FQDN of the farm entry point, where the query runs once.

        .PARAMETER InstallAccount
        The account used for the remote session.

        .PARAMETER Farm
        Farm label written in the Farm column of the result.
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount,

        [Parameter()]
        [System.String]
        $Farm = 'SPS'
    )

    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments @{ Farm = $Farm } `
        -Server $Server `
        -ScriptBlock {
        $params = $args[0]
        try {
            $contentDatabases = New-Object -TypeName System.Collections.ArrayList
            foreach ($database in @(Get-SPContentDatabase)) {
                $sqlServer = if ($database.Server -and $database.Server.Address) { "$($database.Server.Address)" } else { "$($database.Server)" }
                # $null when it cannot be read: the check then says nothing about the external BLOBs
                $rbs = $null
                try { $rbs = [System.Boolean]$database.RemoteBlobStorageSettings.Enabled() } catch { $rbs = $null }
                [void]$contentDatabases.Add([PSCustomObject]@{
                        Name             = "$($database.Name)"
                        SqlServer        = $sqlServer
                        SiteCount        = [System.Int32]$database.CurrentSiteCount
                        WarningSiteCount = [System.Int32]$database.WarningSiteCount
                        Rbs              = $rbs
                    })
            }

            $webApplications = New-Object -TypeName System.Collections.ArrayList
            foreach ($webApplication in @(Get-SPWebApplication)) {
                $pathCount = $null
                try { $pathCount = @(Get-SPManagedPath -WebApplication $webApplication -ErrorAction Stop).Count } catch { $pathCount = $null }
                [void]$webApplications.Add([PSCustomObject]@{
                        Name      = "$($webApplication.Name)"
                        PathCount = $pathCount
                    })
            }

            $hostNamedPathCount = $null
            try { $hostNamedPathCount = @(Get-SPManagedPath -HostHeader -ErrorAction Stop).Count } catch { $hostNamedPathCount = $null }

            return [PSCustomObject]@{
                Farm                      = "$($params.Farm)"
                ContentDatabases          = @($contentDatabases)
                WebApplicationCount       = $webApplications.Count
                WebApplications           = @($webApplications)
                HostNamedManagedPathCount = $hostNamedPathCount
                Error                     = ''
            }
        }
        catch {
            return [PSCustomObject]@{
                Farm                      = "$($params.Farm)"
                ContentDatabases          = @()
                WebApplicationCount       = $null
                WebApplications           = @()
                HostNamedManagedPathCount = $null
                Error                     = "$($_.Exception.Message)"
            }
        }
    }
    return $result
}
