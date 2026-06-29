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

    if (-not $Servers) { $Servers = @($Server) }

    # One direct CredSSP session per server (single hop) so each node is reached
    # without a second hop from the entry server.
    $tbIISApplicationPoolStatus = New-Object -TypeName System.Collections.ArrayList
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
                Import-Module WebAdministration
                $pools = New-Object -TypeName System.Collections.ArrayList
                $spWebAppStatusList = (Get-WebAppPoolState).SyncRoot | Select-Object -property Value, ITemXPath
                foreach ($spWebAppPool in $spWebAppStatusList) {
                    $isMailInfo = $true
                    $webAppSiteStatus = $spWebAppPool.Value
                    $webAppSiteName = $spWebAppPool.ItemXPath.Split("'")[1]
                    $isSPAPPPool = Get-SPServiceApplicationPool | Where-Object -FilterScript { $_.ID -eq $WebAppSiteName } | Select-Object -ExpandProperty Name
                    if ($isSPAPPPool) { $spAppPoolName = $isSPAPPPool } else { $spAppPoolName = $webAppSiteName }
                    if ($spAppPoolName -eq 'SharePoint Web Services Root') {
                        if ($webAppSiteStatus -ne 'Stopped') { $isMailInfo = $false }
                    }
                    else {
                        if ($webAppSiteStatus -ne 'Started') { $isMailInfo = $false }
                    }
                    [void]$pools.Add([PSCustomObject]@{
                            Farm            = $cfgFarm; Server = $cfgServer;
                            ApplicationPool = $spAppPoolName; Status = $webAppSiteStatus; IsInfo = $isMailInfo;
                        })
                }
                return $pools
            }
            foreach ($r in $rows) { [void]$tbIISApplicationPoolStatus.Add($r) }
        }
        catch {
            [void]$tbIISApplicationPoolStatus.Add([PSCustomObject]@{
                    Farm            = $Farm; Server = $spServer;
                    ApplicationPool = 'Unreachable'; Status = ''; IsInfo = $false;
                })
        }
    }
    return $tbIISApplicationPoolStatus
}
