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

    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments $PSBoundParameters `
        -Server $Server `
        -ScriptBlock {
        $params = $args[0]
        class SYSLastRebootStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$OSName
            [System.String]$OSVersion
            [System.String]$LastRebootTime
        }
        $tbSYSLastRebootStatus = New-Object -TypeName System.Collections.ArrayList
        foreach ($spServer in $params.Servers) {
            try {
                [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
                $cimWin32_OS = Get-CimInstance -ComputerName $remoteServer -ClassName win32_operatingsystem
                [void]$tbSYSLastRebootStatus.Add([SYSLastRebootStatus]@{
                        Farm           = $params.Farm;
                        Server         = $spServer;
                        OSName         = $cimWin32_OS.Caption;
                        OSVersion      = $cimWin32_OS.Version;
                        LastRebootTime = $cimWin32_OS.LastBootUpTime;
                    })
            }
            catch {
                [void]$tbSYSLastRebootStatus.Add([SYSLastRebootStatus]@{
                        Farm           = $params.Farm;
                        Server         = $spServer;
                        OSName         = 'Unreachable';
                        OSVersion      = '';
                        LastRebootTime = '';
                    })
            }
        }
        return $tbSYSLastRebootStatus
    }
    return $result
}
