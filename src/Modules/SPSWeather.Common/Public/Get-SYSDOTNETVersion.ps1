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

    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments $PSBoundParameters `
        -Server $Server `
        -ScriptBlock {
        $params = $args[0]
        class SYSDOTNETVersion {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$NetVersion
            [System.Boolean]$NetRequiredVersion
        }
        $tbSYSDOTNETVersion = New-Object -TypeName System.Collections.ArrayList
        foreach ($spServer in $params.Servers) {
            try {
                [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
                $resultReg = Invoke-Command -ComputerName $remoteServer -ErrorAction Stop -ScriptBlock {
                    try {
                        $getItemProperty = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
                    }
                    catch {
                        $null = $getItemProperty
                    }
                    return $getItemProperty
                }
                if ($null -ne $resultReg) {
                    [System.Boolean]$NetRequiredBool = ($resultReg.Release -ge 528040)
                    [void]$tbSYSDOTNETVersion.Add([SYSDOTNETVersion]@{
                            Farm               = $params.Farm;
                            Server             = $spServer;
                            NetVersion         = "$($resultReg.Version)";
                            NetRequiredVersion = $NetRequiredBool;
                        })
                }
                else {
                    [void]$tbSYSDOTNETVersion.Add([SYSDOTNETVersion]@{
                            Farm               = $params.Farm;
                            Server             = $spServer;
                            NetVersion         = $null;
                            NetRequiredVersion = $null;
                        })
                }
            }
            catch {
                [void]$tbSYSDOTNETVersion.Add([SYSDOTNETVersion]@{
                        Farm               = $params.Farm;
                        Server             = $spServer;
                        NetVersion         = 'Unreachable';
                        NetRequiredVersion = $false;
                    })
            }
        }
        return $tbSYSDOTNETVersion
    }
    return $result
}
