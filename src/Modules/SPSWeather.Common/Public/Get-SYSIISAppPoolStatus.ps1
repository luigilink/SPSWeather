function Get-SYSIISAppPoolStatus {
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
        class IISApplicationPoolStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$ApplicationPool
            [System.String]$Status
            [System.Boolean]$IsInfo
        }
        $tbIISApplicationPoolStatus = New-Object -TypeName System.Collections.ArrayList
        foreach ($spServer in $params.Servers) {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
            $spWebAppStatus = Invoke-Command -ComputerName $remoteServer -ScriptBlock {
                Import-Module WebAdministration; Get-WebAppPoolState
            }
            $spWebAppStatusList = $spWebAppStatus.SyncRoot | Select-Object -property Value, ITemXPath
            if ($spWebAppStatusList) {
                foreach ($spWebAppPool in $spWebAppStatusList) {
                    $isMailInfo       = $true
                    $webAppSiteStatus = $spWebAppPool.Value
                    $webAppSiteName   = $spWebAppPool.ItemXPath.Split("'")[1]
                    $isSPAPPPool      = Get-SPServiceApplicationPool | Where-Object -FilterScript { $_.ID -eq $WebAppSiteName } | Select-Object -ExpandProperty Name
                    if ($isSPAPPPool) {
                        $spAppPoolName = $isSPAPPPool
                    }
                    else {
                        $spAppPoolName = $webAppSiteName
                    }
                    if ($spAppPoolName -eq 'SharePoint Web Services Root') {
                        if ($webAppSiteStatus -ne 'Stopped') {
                            $isMailInfo      = $false
                        }
                    }
                    else {
                        if ($webAppSiteStatus -ne 'Started') {
                            $isMailInfo      = $false
                        }
                    }
                    [void]$tbIISApplicationPoolStatus.Add([IISApplicationPoolStatus]@{
                            Farm            = $params.Farm
                            Server          = $spServer;
                            ApplicationPool = $spAppPoolName;
                            Status          = $webAppSiteStatus;
                            IsInfo          = $isMailInfo;
                        })
                }
            }
        }
        return $tbIISApplicationPoolStatus
    }
    return $result
}
