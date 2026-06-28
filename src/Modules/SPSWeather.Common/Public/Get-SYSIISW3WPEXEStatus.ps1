function Get-SYSIISW3WPEXEStatus {
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
        class IISWorkerProcessStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$CreationDate
            [System.String]$Memory
            [System.String]$ApplicationPool
        }
        $tbIISWorkerProcessStatus = New-Object -TypeName System.Collections.ArrayList
        foreach ($spServer in $params.Servers) {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
            $w3wpProcess = Invoke-Command -ComputerName $remoteServer -ScriptBlock {
                Get-CimInstance Win32_Process -Filter "name = 'w3wp.exe'" | Sort-Object CommandLine
            }
            foreach ($w3wpProc in $w3wpProcess) {
                $w3wpProcCmdLine = $w3wpProc.CommandLine.Replace('c:\windows\system32\inetsrv\w3wp.exe -ap "', '')
                $pos = $w3wpProcCmdLine.IndexOf('"')
                $appPoolName = $w3wpProcCmdLine.Substring(0, $pos)
                $w3wpMemoryUsage = [Math]::Round($w3wpProc.WorkingSetSize / 1MB)
                [void]$tbIISWorkerProcessStatus.Add([IISWorkerProcessStatus]@{
                        Farm            = $params.Farm
                        Server          = $spServer;
                        CreationDate    = $w3wpProc.CreationDate;
                        Memory          = $w3wpMemoryUsage;
                        ApplicationPool = $appPoolName;
                    })
            }
        }
        return $tbIISWorkerProcessStatus
    }
    return $result
}
