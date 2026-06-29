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

    $result = Invoke-SPSCommand -Credential $InstallAccount `
                                -Arguments $PSBoundParameters `
                                -Server $Server `
                                -ScriptBlock {
        $params = $args[0]
        class IISWebSiteCertStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$WebSiteName
            [System.String]$ExpirationDate
            [System.String]$Status
            [System.Boolean]$IsInfo
        }

        $tbIISSiteCertStatus = New-Object -TypeName System.Collections.ArrayList
        $expirationDate = (Get-Date).AddDays($params.Expiration)
        foreach ($spServer in $params.Servers) {
            try {
                [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
                $spSvcInstanceIIS = Get-SPServiceInstance -Server $spServer | Where-Object -FilterScript {
                    $_.Status -eq 'Online' -and $_.GetType().Name -eq 'SPWebServiceInstance'
                }

                if ($null -ne $spSvcInstanceIIS) {
                    $getWebBindings = Invoke-Command -ComputerName $remoteServer { Get-WebBinding }
                    $getSSLBindings = $getWebBindings | Where-Object -FilterScript {
                        $_.protocol -eq 'https' -and $_.bindingInformation -like '*443*'
                    }
                    if ($getSSLBindings) {
                        foreach ($binding in $getSSLBindings) {
                            $iisSiteName = (($binding.ItemXPath -split ([RegEx]::Escape("[@name='")))[1]).split("'")[0]

                            $getCertMyStore = Invoke-Command -ComputerName $remoteServer { Get-ChildItem 'Cert:LocalMachine\My' }
                            $getCertificate = $getCertMyStore | Where-Object -FilterScript {
                                $_.Thumbprint -eq $binding.certificateHash
                            }
                            $certExpiration = $getCertificate.NotAfter
                            if ($certExpiration -gt $expirationDate) {
                                $certStatus    = 'OK'
                                $isMailInfo    = $true
                            }
                            else {
                                $certStatus    = 'Renew cert'
                                $isMailInfo    = $false
                            }
                            [void]$tbIISSiteCertStatus.Add([IISWebSiteCertStatus]@{
                                Farm           = $params.Farm;
                                Server         = $spServer;
                                WebSiteName    = $iisSiteName;
                                ExpirationDate = $certExpiration;
                                Status         = $certStatus;
                                IsInfo         = $isMailInfo;
                            })
                        }
                    }
                }
            }
            catch {
                [void]$tbIISSiteCertStatus.Add([IISWebSiteCertStatus]@{
                    Farm           = $params.Farm;
                    Server         = $spServer;
                    WebSiteName    = '';
                    ExpirationDate = '';
                    Status         = 'Unreachable';
                    IsInfo         = $false;
                })
            }
        }
        return $tbIISSiteCertStatus
    }
    return $result
}
