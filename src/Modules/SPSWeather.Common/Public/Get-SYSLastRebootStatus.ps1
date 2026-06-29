function Get-SYSLastRebootStatus {
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

    # One direct CredSSP session per server (single hop) instead of fanning out
    # from a single session, which avoided the double-hop 0x80090322 failures.
    $tbSYSLastRebootStatus = New-Object -TypeName System.Collections.ArrayList
    foreach ($spServer in $Servers) {
        try {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
            if ($remoteServer -notmatch "\.") {
                # DNS returned short name; rebuild FQDN from $spServer to keep its original casing.
                $suffix = if ($Server -match "\.") { $Server.Substring($Server.IndexOf(".") + 1) } else { "" }
                if ($suffix) { $remoteServer = "$spServer.$suffix" }
            }
            $row = Invoke-SPSCommand -Credential $InstallAccount `
                -Arguments @($Farm, $spServer) `
                -Server $remoteServer `
                -ScriptBlock {
                $cimWin32_OS = Get-CimInstance -ClassName win32_operatingsystem
                return [PSCustomObject]@{
                    Farm           = $args[0];
                    Server         = $args[1];
                    OSName         = $cimWin32_OS.Caption;
                    OSVersion      = $cimWin32_OS.Version;
                    LastRebootTime = $cimWin32_OS.LastBootUpTime;
                }
            }
            [void]$tbSYSLastRebootStatus.Add($row)
        }
        catch {
            [void]$tbSYSLastRebootStatus.Add([PSCustomObject]@{
                    Farm           = $Farm;
                    Server         = $spServer;
                    OSName         = 'Unreachable';
                    OSVersion      = '';
                    LastRebootTime = '';
                })
        }
    }
    return $tbSYSLastRebootStatus
}
