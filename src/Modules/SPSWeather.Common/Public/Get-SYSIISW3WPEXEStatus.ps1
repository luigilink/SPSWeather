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

    if (-not $Servers) { $Servers = @($Server) }

    # One direct CredSSP session per server (single hop) so each node is reached
    # without a second hop from the entry server.
    $tbIISWorkerProcessStatus = New-Object -TypeName System.Collections.ArrayList
    foreach ($spServer in $Servers) {
        try {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
            if ($remoteServer -notmatch "\.") {
                # DNS returned short name; rebuild FQDN from $spServer to keep its original casing.
                $suffix = if ($Server -match "\.") { $Server.Substring($Server.IndexOf(".") + 1) } else { "" }
                if ($suffix) { $remoteServer = "$spServer.$suffix" }
            }
            $rows = Invoke-SPSCommand -Credential $InstallAccount `
                -Arguments @($Farm, $spServer) `
                -Server $remoteServer `
                -ScriptBlock {
                $cfgFarm = $args[0]; $cfgServer = $args[1]
                $procs = New-Object -TypeName System.Collections.ArrayList
                $w3wpProcess = Get-CimInstance Win32_Process -Filter "name = 'w3wp.exe'" | Sort-Object CommandLine
                foreach ($w3wpProc in $w3wpProcess) {
                    $w3wpProcCmdLine = $w3wpProc.CommandLine.Replace('c:\windows\system32\inetsrv\w3wp.exe -ap "', '')
                    $pos = $w3wpProcCmdLine.IndexOf('"')
                    $appPoolName = $w3wpProcCmdLine.Substring(0, $pos)
                    [void]$procs.Add([PSCustomObject]@{
                            Farm            = $cfgFarm; Server = $cfgServer;
                            CreationDate    = $w3wpProc.CreationDate;
                            Memory          = [Math]::Round($w3wpProc.WorkingSetSize / 1MB);
                            ApplicationPool = $appPoolName;
                        })
                }
                return $procs
            }
            foreach ($r in $rows) { [void]$tbIISWorkerProcessStatus.Add($r) }
        }
        catch {
            [void]$tbIISWorkerProcessStatus.Add([PSCustomObject]@{
                    Farm            = $Farm; Server = $spServer; CreationDate = '';
                    Memory          = ''; ApplicationPool = 'Unreachable';
                })
        }
    }
    return $tbIISWorkerProcessStatus
}
