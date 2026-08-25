function Get-AppFabricStatus {
    <#
        .SYNOPSIS
        Reports the SharePoint Server Subscription Edition Distributed Cache status
        for every server of the farm.

        .DESCRIPTION
        Returns one row per farm server:

        - Cache hosts (SPDistributedCacheServiceInstance) get their real Port /
          Size (MB) / ServiceName / CacheStatus. Get-SPCacheHostConfig only returns
          the full payload when executed locally on the cache host itself after
          Use-SPCacheCluster, so this function opens a per-host CredSSP session
          targeting the FQDN and calls Get-SPCacheHostConfig -HostName
          $env:COMPUTERNAME inside. When the local lookup still fails, the row falls
          back to the SE cluster tier (Small/Medium/Large) suffixed ' (tier)'.
        - Non-cache servers get a green informational row 'Not a cache host'.
          Hosting Distributed Cache on a subset of the farm servers (often a single
          WFE) is a legitimate topology on SE.
    #>
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

    # Pass 1: from the farm entry server, list the Distributed Cache topology
    # (which servers host the cache) and the full server list. We do NOT call
    # Get-SPCacheHostConfig here: the cmdlet only returns a useful payload
    # (Size in MB, ports, ...) when executed locally on the cache host after
    # Use-SPCacheCluster.
    $inventory = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments $Farm `
        -Server $Server `
        -ScriptBlock {
        $localFarm = $args[0]
        $allSPServers = (Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' }).Name
        $dcInstances = Get-SPServiceInstance | Where-Object -FilterScript {
            $_.GetType().Name -eq 'SPDistributedCacheServiceInstance'
        }
        $clusterInfo = Get-SPCacheClusterInfo -ErrorAction SilentlyContinue
        $dcHosts = @()
        foreach ($dc in $dcInstances) {
            $dcHosts += [PSCustomObject]@{
                Farm   = $localFarm
                Server = "$($dc.Server.Address)".Split('.')[0]
                Status = "$($dc.Status)"
            }
        }
        return [PSCustomObject]@{
            AllServers  = @($allSPServers)
            DcHosts     = $dcHosts
            ClusterSize = if ($null -ne $clusterInfo) { "$($clusterInfo.Size)" } else { '' }
        }
    }

    $tbAppFabricStatus = New-Object -TypeName System.Collections.ArrayList

    # FQDN suffix derived from the farm entry server, used to build a single-hop
    # CredSSP target per cache host (avoids 0x80090322 when DNS returns the short
    # name).
    $suffix = if ($Server -match '\.') { $Server.Substring($Server.IndexOf('.') + 1) } else { '' }

    # Pass 2: query Get-SPCacheHostConfig LOCALLY on each cache host. That is
    # where the cmdlet returns the real Size (in MB), ports, etc.
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
                Farm             = $dcHost.Farm
                Server           = $dcHost.Server
                Port             = $port
                ServiceName      = $serviceName
                Size             = $size
                CacheStatus      = $cacheStatus
                SPInstanceStatus = $dcHost.Status
                IsInfo           = $isMailInfo
            })
    }

    # Servers that are not part of the cache cluster: informational row.
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
