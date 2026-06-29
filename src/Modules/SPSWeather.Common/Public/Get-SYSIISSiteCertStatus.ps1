function Get-SYSIISSiteCertStatus {
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
        $Servers,

        [Parameter()]
        [System.UInt32]
        $Expiration
    )

    if (-not $Servers) { $Servers = @($Server) }

    # One direct CredSSP session per server (single hop) so each node is reached
    # without a second hop from the entry server.
    $tbIISSiteCertStatus = New-Object -TypeName System.Collections.ArrayList
    foreach ($spServer in $Servers) {
        try {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
            $rows = Invoke-SPSCommand -Credential $InstallAccount `
                -Arguments @($Farm, $spServer, $Expiration) `
                -Server $remoteServer `
                -ScriptBlock {
                $cfgFarm = $args[0]; $cfgServer = $args[1]; $cfgExpiration = $args[2]
                $certs = New-Object -TypeName System.Collections.ArrayList
                $expirationDate = (Get-Date).AddDays($cfgExpiration)
                $spSvcInstanceIIS = Get-SPServiceInstance -Server $cfgServer | Where-Object -FilterScript {
                    $_.Status -eq 'Online' -and $_.GetType().Name -eq 'SPWebServiceInstance'
                }
                if ($null -ne $spSvcInstanceIIS) {
                    $getSSLBindings = Get-WebBinding | Where-Object -FilterScript {
                        $_.protocol -eq 'https' -and $_.bindingInformation -like '*443*'
                    }
                    foreach ($binding in $getSSLBindings) {
                        $iisSiteName = (($binding.ItemXPath -split ([RegEx]::Escape("[@name='")))[1]).split("'")[0]
                        $getCertificate = Get-ChildItem 'Cert:LocalMachine\My' | Where-Object -FilterScript { $_.Thumbprint -eq $binding.certificateHash }
                        $certExpiration = $getCertificate.NotAfter
                        if ($certExpiration -gt $expirationDate) { $certStatus = 'OK'; $isMailInfo = $true }
                        else { $certStatus = 'Renew cert'; $isMailInfo = $false }
                        [void]$certs.Add([PSCustomObject]@{
                                Farm           = $cfgFarm; Server = $cfgServer; WebSiteName = $iisSiteName;
                                ExpirationDate = $certExpiration; Status = $certStatus; IsInfo = $isMailInfo;
                            })
                    }
                }
                return $certs
            }
            foreach ($r in $rows) { [void]$tbIISSiteCertStatus.Add($r) }
        }
        catch {
            [void]$tbIISSiteCertStatus.Add([PSCustomObject]@{
                    Farm           = $Farm; Server = $spServer; WebSiteName = '';
                    ExpirationDate = ''; Status = 'Unreachable'; IsInfo = $false;
                })
        }
    }
    return $tbIISSiteCertStatus
}
