function Get-AppFabricStatus {
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
        $Farm = 'SPS'
    )
    $result = Invoke-SPSCommand -Credential $InstallAccount `
                                -Arguments $PSBoundParameters `
                                -Server $Server `
                                -ScriptBlock {

        $params = $args[0]
        class AppFabricStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$Port
            [System.String]$ServiceName
            [System.String]$Size
            [System.String]$CacheStatus
            [System.String]$SPInstanceStatus
            [System.Boolean]$IsInfo
        }
        $tbAppFabricStatus = New-Object -TypeName System.Collections.ArrayList
        $pathToSearch = 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions\*\ISAPI\Microsoft.SharePoint.dll'
        $fullPath = Get-Item $pathToSearch -ErrorAction SilentlyContinue | Sort-Object { $_.Directory } -Descending | Select-Object -First 1
        if ($null -eq $fullPath) {
            $message = 'SharePoint path {C:\Program Files\Common Files\microsoft shared\Web Server Extensions} does not exist'
            throw $message
        }
        else {
            $productVersion = (Get-Command $fullPath).FileVersionInfo
        }
        if ($productVersion.FileMajorPart -eq 16 -and $productVersion.FileBuildPart -gt 13000) {
            Write-Verbose -Message 'Subscription Edition: using Get-SPCacheClusterHealth/Info as the source of truth'
            $allSPServers = (Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' }).Name
            $dcInstances = @(Get-SPServiceInstance | Where-Object -FilterScript {
                    $_.GetType().Name -eq 'SPDistributedCacheServiceInstance'
                })
            # Canonical host list (FQDNs) and cluster Size come from the SE-native cmdlets.
            $clusterHealth = Get-SPCacheClusterHealth -ErrorAction SilentlyContinue
            $clusterInfo   = Get-SPCacheClusterInfo -ErrorAction SilentlyContinue
            $clusterSize   = if ($null -ne $clusterInfo) { "$($clusterInfo.Size)" } else { '' }
            $clusterHosts  = @()
            if ($null -ne $clusterHealth -and $null -ne $clusterHealth.Hosts) {
                $clusterHosts = @($clusterHealth.Hosts | ForEach-Object { "$_" })
            }
            $reportedServers = New-Object -TypeName System.Collections.ArrayList
            foreach ($clusterFqdn in $clusterHosts) {
                $cacheserver = $clusterFqdn.Split('.')[0]
                # Match the SP service instance for this host (Server.Address is short)
                $dcInst = $dcInstances | Where-Object -FilterScript {
                    "$($_.Server.Address)" -eq $cacheserver -or
                    "$($_.Server.Address)" -eq $clusterFqdn
                } | Select-Object -First 1
                $SPInstanceStatus = if ($null -ne $dcInst) { "$($dcInst.Status)" } else { 'Unknown' }
                # Try Get-SPCacheHostConfig with the FQDN; degrade gracefully if it
                # returns null (some SE builds cannot resolve the host name).
                $cacheHostConfig = Get-SPCacheHostConfig -HostName $clusterFqdn -ErrorAction SilentlyContinue
                $cacheHost = $null
                if ($null -ne $cacheHostConfig) {
                    $cacheHost = Get-SPCacheHost -HostName $cacheHostConfig.HostName -CachePort $cacheHostConfig.CachePort -ErrorAction SilentlyContinue
                }
                $port        = if ($null -ne $cacheHostConfig) { "$($cacheHostConfig.CachePort)" } else { '22233' }
                $size        = if ($null -ne $cacheHostConfig) { "$($cacheHostConfig.Size)" } else { $clusterSize }
                $serviceName = if ($null -ne $cacheHost) { "$($cacheHost.ServiceName)" } else { 'AppFabricCachingService' }
                $cacheStatus = if ($null -ne $cacheHost) { "$($cacheHost.Status)" }
                               elseif ($SPInstanceStatus -eq 'Online') { 'Up' }
                               else { 'Unknown' }
                $isMailInfo = ($SPInstanceStatus -eq 'Online' -and $cacheStatus -eq 'Up')
                [void]$tbAppFabricStatus.Add([AppFabricStatus]@{
                        Farm             = $params.Farm
                        Server           = $cacheserver;
                        Port             = $port;
                        ServiceName      = $serviceName;
                        Size             = $size;
                        CacheStatus      = $cacheStatus;
                        SPInstanceStatus = $SPInstanceStatus;
                        IsInfo           = $isMailInfo;
                    })
                [void]$reportedServers.Add($cacheserver)
            }
            # Servers that are not part of the cache cluster: informational row
            # (legitimate topology to host Distributed Cache on a subset of servers).
            foreach ($srv in $allSPServers) {
                if ($reportedServers -notcontains $srv) {
                    [void]$tbAppFabricStatus.Add([AppFabricStatus]@{
                            Farm             = $params.Farm
                            Server           = $srv;
                            Port             = '';
                            ServiceName      = '';
                            Size             = '';
                            CacheStatus      = '';
                            SPInstanceStatus = 'Not a cache host';
                            IsInfo           = $true;
                        })
                }
            }
            return $tbAppFabricStatus
        }
        else {
            Use-CacheCluster -ErrorAction SilentlyContinue
            $cacheHosts = Get-CacheHost -ErrorAction SilentlyContinue
            if ($null -ne $cacheHosts) {
                foreach ($cacheHost in $cacheHosts) {
                    $isMailInfo      = $true
                    $cacheHostConfig = Get-AFCacheHostConfiguration -ComputerName $cacheHost.HostName `
                                                                    -CachePort $cacheHost.PortNo `
                                                                    -ErrorAction SilentlyContinue
                    $hostName        = $cacheHost.HostName
                    $cacheserver     = $hostName.Split('.')[0]
                    $spCacheSvc      = Get-SPServiceInstance -Server $cacheserver | Where-Object -FilterScript {
                        $_.GetType().Name -eq 'SPDistributedCacheServiceInstance'
                    }
                    if ($cacheHost.Status -ne 'Up') {
                        $isMailInfo = $false
                    }
                    if ($null -ne $spCacheSvc) {
                        $SPInstanceStatus = $spCacheSvc.Status
                        if ($SPInstanceStatus -ne 'Online') {
                            $isMailInfo = $false
                        }
                    }
                    else {
                        $SPInstanceStatus = 'SPService Not Found'
                        $isMailInfo = $false
                    }
                    [void]$tbAppFabricStatus.Add([AppFabricStatus]@{
                        Farm             = $params.Farm
                        Server           = $cacheserver;
                        Port             = $cacheHost.PortNo;
                        ServiceName      = $cacheHost.ServiceName;
                        Size             = $cacheHostConfig.Size;
                        CacheStatus      = $cacheHost.Status;
                        SPInstanceStatus = $SPInstanceStatus;
                        IsInfo           = $isMailInfo;
                    })
                }
                return $tbAppFabricStatus
            }
        }
    }
    return $result
}
