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
function Get-SYSDiskUsageStatus {
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
        $WarningPercentage
    )

    $result = Invoke-SPSCommand -Credential $InstallAccount `
                                -Arguments $PSBoundParameters `
                                -Server $Server `
                                -ScriptBlock {
        $params = $args[0]
        class SYSDiskUsageStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$DriveLetter
            [System.String]$Size
            [System.String]$FreeSpace
            [System.String]$Status
            [System.Boolean]$IsInfo
        }
        $tbSYSDiskUsageStatus = New-Object -TypeName System.Collections.ArrayList
        foreach ($spServer in $params.Servers) {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
            $getDrives = Invoke-Command -ComputerName $remoteServer { Get-Volume | Where-Object -FilterScript { $_.DriveType -eq 'Fixed' -and $null -ne $_.DriveLetter } }
            foreach ($getDrive in $getDrives) {
                $driveSize = [math]::Round($($getDrive.Size) / 1073741824, 2)
                $driveFree = [math]::Round($($getDrive.SizeRemaining) / 1073741824, 2)
                $perFreeSpace = ($getDrive.SizeRemaining / $getDrive.Size) * 100
                if ($perFreeSpace -gt $params.WarningPercentage) {
                    $freeSpaceStatus = 'OK'
                    $isMailInfo      = $true
                }
                else {
                    $freeSpaceStatus = "Less than $WarningPercentage %"
                    $isMailInfo      = $false
                }
                [void]$tbSYSDiskUsageStatus.Add([SYSDiskUsageStatus]@{
                        Farm        = $params.Farm;
                        Server      = $spServer;
                        DriveLetter = $getDrive.DriveLetter;
                        Size        = $driveSize;
                        FreeSpace   = $driveFree;
                        Status      = $freeSpaceStatus;
                        IsInfo      = $isMailInfo
                    })
            }
        }
        return $tbSYSDiskUsageStatus
    }
    return $result
}
function Get-SYSEvtAppErrors {
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
        class SYSEventViewerAppError {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$ID
            [System.String]$Severity
            [System.String]$Name
            [System.String]$Count
        }
        $tbSYSEventViewerAppErrors = New-Object -TypeName System.Collections.ArrayList
        foreach ($pSserver in $params.Servers) {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($pSserver).HostName
            try {
                $appErrors = Invoke-Command -ComputerName $remoteServer -ScriptBlock {
                    Get-WinEvent -FilterHashTable @{LogName = 'Application'; Level = 2; StartTime = ((Get-Date) - (New-TimeSpan -Days 1)) } `
                                 -ErrorAction SilentlyContinue
                }
                if ($null -eq $appErrors) {
                    [void]$tbSYSEventViewerAppErrors.Add([SYSEventViewerAppError]@{
                        Farm     = $params.Farm
                        Server   = $pSserver;
                        ID       = 'Non Applicable';
                        Severity = 'Non Applicable';
                        Name     = 'No error found the last 24h';
                        Count    = '0';
                    })
                }
                else {
                    $grpAppErrors = $appErrors | Group-Object Id | Select-Object -Property Count, Name
                    foreach ($grpAppError in $grpAppErrors) {
                        $currentAppError = $appErrors | Where-Object -FilterScript { $_.ID -eq $grpAppError.Name } | Get-Unique
                        [void]$tbSYSEventViewerAppErrors.Add([SYSEventViewerAppError]@{
                            Farm     = $params.Farm
                            Server   = $pSserver;
                            ID       = $currentAppError.Id;
                            Severity = $currentAppError.LevelDisplayName;
                            Name     = $currentAppError.ProviderName;
                            Count    = $grpAppError.Count;
                        })
                    }
                }
            }
            catch {
                return $_
            }
        }
        return $tbSYSEventViewerAppErrors
    }
    return $result
}
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
function Get-SYSIISW3WPEXEStatus {
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
        class IISWorkerProcessStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$CreationDate
            [System.String]$Memory
            [System.String]$ApplicationPool
        }
        $tbIISWorkerProcessStatus = New-Object -TypeName System.Collections.ArrayList
        foreach ($spServer in $params.Servers) {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
            $w3wpProcess = Invoke-Command -ComputerName $remoteServer -ScriptBlock {
                Get-CimInstance Win32_Process -Filter "name = 'w3wp.exe'" | Sort-Object CommandLine
            }
            foreach ($w3wpProc in $w3wpProcess) {
                $w3wpProcCmdLine = $w3wpProc.CommandLine.Replace('c:\windows\system32\inetsrv\w3wp.exe -ap "', '')
                $pos = $w3wpProcCmdLine.IndexOf('"')
                $appPoolName = $w3wpProcCmdLine.Substring(0, $pos)
                $w3wpMemoryUsage = [Math]::Round($w3wpProc.WorkingSetSize / 1MB)
                [void]$tbIISWorkerProcessStatus.Add([IISWorkerProcessStatus]@{
                        Farm            = $params.Farm
                        Server          = $spServer;
                        CreationDate    = $w3wpProc.CreationDate;
                        Memory          = $w3wpMemoryUsage;
                        ApplicationPool = $appPoolName;
                    })
            }
        }
        return $tbIISWorkerProcessStatus
    }
    return $result
}
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
        return $tbIISSiteCertStatus
    }
    return $result
}
function Get-SYSLastRebootStatus {
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
        class SYSLastRebootStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$OSName
            [System.String]$OSVersion
            [System.String]$LastRebootTime
        }
        $tbSYSLastRebootStatus = New-Object -TypeName System.Collections.ArrayList
        foreach ($spServer in $params.Servers) {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
            $cimWin32_OS = Get-CimInstance -ComputerName $remoteServer -ClassName win32_operatingsystem
            [void]$tbSYSLastRebootStatus.Add([SYSLastRebootStatus]@{
                    Farm           = $params.Farm;
                    Server         = $spServer;
                    OSName         = $cimWin32_OS.Caption;
                    OSVersion      = $cimWin32_OS.Version;
                    LastRebootTime = $cimWin32_OS.LastBootUpTime;
                })
        }
        return $tbSYSLastRebootStatus
    }
    return $result
}
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
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
            $resultReg = Invoke-Command -ComputerName $remoteServer -ScriptBlock {
                try {
                    $getItemProperty = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
                }
                catch {
                    $null = $getItemProperty
                }
                return $getItemProperty
            }
            if ($nulll -ne $resultReg){
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
        return $tbSYSDOTNETVersion
    }
    return $result
}
