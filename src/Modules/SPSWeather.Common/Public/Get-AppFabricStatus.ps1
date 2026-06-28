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
            Write-Verbose -Message 'Get list of SharePoint Servers'
            $listSPServer = (Get-SPServer | Where-Object -FilterScript {$_.Role -ne 'Invalid'}).Name
            Write-Verbose -Message "'Use-CacheCluster' cmdlet not required for SPSE"
            Write-Verbose -Message "Using newer 'Get-SPCacheHostConfig' cmdlet for SPSE"
            foreach ($cacheserver in $listSPServer) {
                $cacheHostConfig = Get-SPCacheHostConfig -HostName $cacheserver -ErrorAction SilentlyContinue
                if ($null -ne $cacheHostConfig) {
                    $isMailInfo  = $true
                    $cacheHost   = Get-SPCacheHost -HostName $cacheHostConfig.HostName -CachePort $cacheHostConfig.CachePort
                }
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
                    Port             = $cacheHostConfig.CachePort;
                    ServiceName      = $cacheHost.ServiceName;
                    Size             = $cacheHostConfig.Size;
                    CacheStatus      = $cacheHost.Status;
                    SPInstanceStatus = $SPInstanceStatus;
                    IsInfo           = $isMailInfo;
                })
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
