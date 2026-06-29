function Get-SYSEvtAppErrors {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
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
        $Farm = 'SPS',

        [Parameter()]
        [System.String[]]
        $Servers
    )

    if (-not $Servers) { $Servers = @($Server) }

    # One direct CredSSP session per server (single hop) so each node is reached
    # without a second hop from the entry server.
    $tbSYSEventViewerAppErrors = New-Object -TypeName System.Collections.ArrayList
    foreach ($spServer in $Servers) {
        try {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
            if ($remoteServer -notmatch "\.") {
                $suffix = if ($Server -match "\.") { $Server.Substring($Server.IndexOf(".") + 1) } else { "" }
                if ($suffix) { $remoteServer = "$remoteServer.$suffix" }
            }
            $rows = Invoke-SPSCommand -Credential $InstallAccount `
                -Arguments @($Farm, $spServer) `
                -Server $remoteServer `
                -ScriptBlock {
                $cfgFarm = $args[0]; $cfgServer = $args[1]
                $errs = New-Object -TypeName System.Collections.ArrayList
                $appErrors = Get-WinEvent -FilterHashTable @{LogName = 'Application'; Level = 2; StartTime = ((Get-Date) - (New-TimeSpan -Days 1)) } -ErrorAction SilentlyContinue
                if ($null -eq $appErrors) {
                    [void]$errs.Add([PSCustomObject]@{
                            Farm = $cfgFarm; Server = $cfgServer; ID = 'Non Applicable';
                            Severity = 'Non Applicable'; Name = 'No error found the last 24h'; Count = '0';
                        })
                }
                else {
                    $grpAppErrors = $appErrors | Group-Object Id | Select-Object -Property Count, Name
                    foreach ($grpAppError in $grpAppErrors) {
                        $currentAppError = $appErrors | Where-Object -FilterScript { $_.ID -eq $grpAppError.Name } | Get-Unique
                        [void]$errs.Add([PSCustomObject]@{
                                Farm = $cfgFarm; Server = $cfgServer; ID = $currentAppError.Id;
                                Severity = $currentAppError.LevelDisplayName; Name = $currentAppError.ProviderName; Count = $grpAppError.Count;
                            })
                    }
                }
                return $errs
            }
            foreach ($r in $rows) { [void]$tbSYSEventViewerAppErrors.Add($r) }
        }
        catch {
            [void]$tbSYSEventViewerAppErrors.Add([PSCustomObject]@{
                    Farm = $Farm; Server = $spServer; ID = 'Non Applicable';
                    Severity = 'Warning'; Name = 'Unreachable'; Count = '0';
                })
        }
    }
    return $tbSYSEventViewerAppErrors
}
