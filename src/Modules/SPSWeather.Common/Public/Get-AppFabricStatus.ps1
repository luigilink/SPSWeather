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
            Write-Verbose -Message "Use-CacheCluster' cmdlet not required for SPSE - using newer Get-SPCacheHostConfig"
            $allSPServers = (Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' }).Name
            $dcInstances = Get-SPServiceInstance | Where-Object -FilterScript {
                $_.GetType().Name -eq 'SPDistributedCacheServiceInstance'
            }
            $reportedServers = New-Object -TypeName System.Collections.ArrayList
            foreach ($dcInst in $dcInstances) {
                $isMailInfo = $true
                $hostFqdn = "$($dcInst.Server.Address)"
                $cacheserver = $hostFqdn.Split('.')[0]
                $cacheHostConfig = $null
                $cacheHost = $null
                if ($dcInst.Status -eq 'Online') {
                    # The cluster may store the host as FQDN or as short name; try both.
                    foreach ($tryHost in @($hostFqdn, $cacheserver)) {
                        if ([string]::IsNullOrEmpty($tryHost)) { continue }
                        $cacheHostConfig = Get-SPCacheHostConfig -HostName $tryHost -ErrorAction SilentlyContinue
                        if ($null -ne $cacheHostConfig) { break }
                    }
                    if ($null -ne $cacheHostConfig) {
                        $cacheHost = Get-SPCacheHost -HostName $cacheHostConfig.HostName -CachePort $cacheHostConfig.CachePort -ErrorAction SilentlyContinue
                    }
                    # Fallback: Get-SPCacheHostConfig occasionally returns null on SE
                    # even when the SP service instance is Online. The underlying
                    # AppFabric cmdlets are still installed - use them to recover
                    # Port/Size/ServiceName/CacheStatus.
                    if ($null -eq $cacheHostConfig) {
                        try {
                            Use-CacheCluster -ErrorAction Stop | Out-Null
                            $afHosts = Get-CacheHost -ErrorAction SilentlyContinue
                            $afHost = $afHosts | Where-Object -FilterScript {
                                $_.HostName -eq $hostFqdn -or
                                $_.HostName -eq $cacheserver -or
                                ($_.HostName -like "$cacheserver.*")
                            } | Select-Object -First 1
                            if ($null -ne $afHost) {
                                $cacheHost = $afHost
                                $cacheHostConfig = Get-AFCacheHostConfiguration -ComputerName $afHost.HostName -CachePort $afHost.PortNo -ErrorAction SilentlyContinue
                                if ($null -ne $cacheHostConfig -and -not ($cacheHostConfig.PSObject.Properties.Name -contains 'CachePort')) {
                                    Add-Member -InputObject $cacheHostConfig -NotePropertyName CachePort -NotePropertyValue $afHost.PortNo -Force
                                }
                            }
                        }
                        catch {
                            Write-Verbose -Message "AppFabric fallback failed for '$cacheserver': $($_.Exception.Message)"
                        }
                    }
                }
                if ($null -ne $cacheHost -and $cacheHost.Status -ne 'Up') { $isMailInfo = $false }
                $SPInstanceStatus = $dcInst.Status
                if ($SPInstanceStatus -ne 'Online') { $isMailInfo = $false }
                [void]$tbAppFabricStatus.Add([AppFabricStatus]@{
                        Farm             = $params.Farm
                        Server           = $cacheserver;
                        Port             = $cacheHostConfig.CachePort;
                        ServiceName      = $cacheHost.ServiceName;
                        Size             = $cacheHostConfig.Size;
                        CacheStatus      = $cacheHost.Status;
                        SPInstanceStatus = $SPInstanceStatus;
                        IsInfo           = $isMailInfo;
                    })
                [void]$reportedServers.Add($cacheserver)
            }
            # SP servers that are not part of the cache cluster: report them as
            # informational (IsInfo=$true) instead of red alerts, since hosting
            # Distributed Cache on a subset of servers is a legitimate topology.
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
