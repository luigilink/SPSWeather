function Get-SPSTimerServiceStatus {
    <#
        .SYNOPSIS
        Reports the status of the SharePoint Timer service instance of every server of the farm.

        .DESCRIPTION
        Returns one row per instance of (Get-SPFarm).TimerService.Instances, with the server name
        and the status. Every instance must be 'Online': a single instance in another state means
        the servers no longer communicate through the timer service, which notably blocks the
        deployment of a WSP (the job that deploys it never runs on that server). Any status other
        than 'Online' is therefore a failure (IsInfo = $false).

        A farm that returns no instance at all, or a query that fails, is also reported as a
        failure ('No instance' / 'Unreachable'), never as healthy.

        The check is read-only: it never changes the status of an instance.

        .PARAMETER Server
        FQDN of the farm entry point, where the query runs once.

        .PARAMETER InstallAccount
        The account used for the remote session.

        .PARAMETER Farm
        Farm label written in the Farm column of every row.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
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
        class TimerServiceInstance {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$Status
            [System.String]$Note
            [System.Boolean]$IsInfo
        }
        try {
            $instances = (Get-SPFarm).TimerService.Instances
            $tbTimerInstances = New-Object -TypeName System.Collections.ArrayList
            foreach ($instance in $instances) {
                $serverName = "$($instance.Server.Name)"
                if ([System.String]::IsNullOrWhiteSpace($serverName)) { $serverName = "$($instance.Server)" }
                $state = "$($instance.Status)"
                $isOnline = ($state -eq 'Online')
                $note = ''
                if (-not $isOnline) {
                    $note = 'Not Online: timer jobs (including the WSP deployment) do not run on this server.'
                }
                [void]$tbTimerInstances.Add([TimerServiceInstance]@{
                        Farm   = $params.Farm
                        Server = $serverName
                        Status = $state
                        Note   = $note
                        IsInfo = $isOnline
                    })
            }

            if ($tbTimerInstances.Count -eq 0) {
                return [TimerServiceInstance]@{
                    Farm   = $params.Farm
                    Server = ''
                    Status = 'No instance'
                    Note   = 'The farm returned no Timer service instance.'
                    IsInfo = $false
                }
            }

            # Failures first, then by server name.
            return $tbTimerInstances | Sort-Object -Property `
                @{ Expression = 'IsInfo'; Descending = $false }, `
                @{ Expression = 'Server'; Descending = $false }
        }
        catch {
            return [TimerServiceInstance]@{
                Farm   = $params.Farm
                Server = $env:COMPUTERNAME
                Status = 'Unreachable'
                Note   = $_.Exception.Message
                IsInfo = $false
            }
        }
    }
    return $result
}
