function Get-SYSDOTNETVersion {
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
    $tbSYSDOTNETVersion = New-Object -TypeName System.Collections.ArrayList
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
                $resultReg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
                [System.Boolean]$NetRequiredBool = ($resultReg.Release -ge 528040)
                return [PSCustomObject]@{
                    Farm               = $args[0];
                    Server             = $args[1];
                    NetVersion         = "$($resultReg.Version)";
                    NetRequiredVersion = $NetRequiredBool;
                }
            }
            [void]$tbSYSDOTNETVersion.Add($row)
        }
        catch {
            [void]$tbSYSDOTNETVersion.Add([PSCustomObject]@{
                    Farm               = $Farm;
                    Server             = $spServer;
                    NetVersion         = 'Unreachable';
                    NetRequiredVersion = $false;
                })
        }
    }
    return $tbSYSDOTNETVersion
}
