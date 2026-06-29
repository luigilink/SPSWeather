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

    # Pass 1: from the farm entry server, detect SharePoint version and the
    # Distributed Cache topology (which servers host the cache + the full server
    # list). On SE we do NOT call Get-SPCacheHostConfig here: the cmdlet only
    # returns a useful payload (Size in MB, ports, ...) when executed locally on
    # the cache host after Use-SPCacheCluster. The 2016/2019 (AppFabric) branch
    # keeps its original logic, unchanged.
    $inventory = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments $Farm `
        -Server $Server `
        -ScriptBlock {
        $localFarm = $args[0]
        $pathToSearch = 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions\*\ISAPI\Microsoft.SharePoint.dll'
        $fullPath = Get-Item $pathToSearch -ErrorAction SilentlyContinue | Sort-Object { $_.Directory } -Descending | Select-Object -First 1
        if ($null -eq $fullPath) {
            throw 'SharePoint path {C:\Program Files\Common Files\microsoft shared\Web Server Extensions} does not exist'
        }
        $productVersion = (Get-Command $fullPath).FileVersionInfo
        $isSE = ($productVersion.FileMajorPart -eq 16 -and $productVersion.FileBuildPart -gt 13000)

        if ($isSE) {
            $allSPServers = (Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' }).Name
            $dcInstances = Get-SPServiceInstance | Where-Object -FilterScript {
                $_.GetType().Name -eq 'SPDistributedCacheServiceInstance'
            }
            $clusterInfo = Get-SPCacheClusterInfo -ErrorAction SilentlyContinue
            $hosts = @()
            foreach ($dc in $dcInstances) {
                $hosts += [PSCustomObject]@{
                    Farm        = $localFarm
                    Server      = "$($dc.Server.Address)".Split('.')[0]
                    Status      = "$($dc.Status)"
                }
            }
            return [PSCustomObject]@{
                IsSE        = $true
                AllServers  = @($allSPServers)
                DcHosts     = $hosts
                ClusterSize = if ($null -ne $clusterInfo) { "$($clusterInfo.Size)" } else { '' }
            }
        }
        else {
            return [PSCustomObject]@{ IsSE = $false }
        }
    }

    $tbAppFabricStatus = New-Object -TypeName System.Collections.ArrayList

    if ($inventory.IsSE) {
        # FQDN suffix derived from the farm entry server, used to build a
        # single-hop CredSSP target per cache host (avoids 0x80090322 when DNS
        # returns the short name).
        $suffix = if ($Server -match '\.') { $Server.Substring($Server.IndexOf('.') + 1) } else { '' }

        # Pass 2 (SE): query Get-SPCacheHostConfig LOCALLY on each cache host.
        # That is where the cmdlet returns the real Size (in MB), ports, etc.
        foreach ($dcHost in $inventory.DcHosts) {
            $remoteTarget = if ($suffix) { "$($dcHost.Server).$suffix" } else { $dcHost.Server }
            $hostConfig = $null
            try {
                $hostConfig = Invoke-SPSCommand -Credential $InstallAccount `
                    -Server $remoteTarget `
                    -ScriptBlock {
                    Use-SPCacheCluster -ErrorAction SilentlyContinue
                    $cfg = Get-SPCacheHostConfig -HostName $env:COMPUTERNAME -ErrorAction SilentlyContinue
                    if ($null -eq $cfg) { return $null }
                    return [PSCustomObject]@{
                        HostName    = "$($cfg.HostName)"
                        CachePort   = "$($cfg.CachePort)"
                        Size        = "$($cfg.Size)"
                        ServiceName = "$($cfg.ServiceName)"
                    }
                }
            }
            catch {
                Write-Verbose -Message "Get-SPCacheHostConfig failed on '$($dcHost.Server)': $($_.Exception.Message)"
            }

            $port        = if ($null -ne $hostConfig) { $hostConfig.CachePort } else { '22233' }
            $size        = if ($null -ne $hostConfig) { $hostConfig.Size }
                           elseif ($inventory.ClusterSize) { "$($inventory.ClusterSize) (tier)" }
                           else { '' }
            $serviceName = if ($null -ne $hostConfig) { $hostConfig.ServiceName } else { 'AppFabricCachingService' }
            $cacheStatus = if ($dcHost.Status -eq 'Online') { 'Up' } else { 'Unknown' }
            $isMailInfo  = ($dcHost.Status -eq 'Online' -and $cacheStatus -eq 'Up')

            [void]$tbAppFabricStatus.Add([PSCustomObject]@{
                    Farm             = $inventory.DcHosts[0].Farm
                    Server           = $dcHost.Server
                    Port             = $port
                    ServiceName      = $serviceName
                    Size             = $size
                    CacheStatus      = $cacheStatus
                    SPInstanceStatus = $dcHost.Status
                    IsInfo           = $isMailInfo
                })
        }
        $reportedServers = @($inventory.DcHosts | ForEach-Object { $_.Server })
        foreach ($srv in $inventory.AllServers) {
            if ($reportedServers -notcontains $srv) {
                [void]$tbAppFabricStatus.Add([PSCustomObject]@{
                        Farm             = $Farm
                        Server           = $srv
                        Port             = ''
                        ServiceName      = ''
                        Size             = ''
                        CacheStatus      = ''
                        SPInstanceStatus = 'Not a cache host'
                        IsInfo           = $true
                    })
            }
        }
        return $tbAppFabricStatus
    }

    # SharePoint 2016 / 2019 branch: original AppFabric-based logic, unchanged.
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
                        Server           = $cacheserver
                        Port             = $cacheHost.PortNo
                        ServiceName      = $cacheHost.ServiceName
                        Size             = $cacheHostConfig.Size
                        CacheStatus      = $cacheHost.Status
                        SPInstanceStatus = $SPInstanceStatus
                        IsInfo           = $isMailInfo
                    })
            }
            return $tbAppFabricStatus
        }
    }
    return $result
}
