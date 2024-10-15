function Get-SPSAPIHttpStatus {
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
        class APIHttpStatus {
            [System.String]$Farm
            [System.String]$Title
            [System.String]$Url
            [System.String]$HTTPCode
            [System.String]$Status
            [System.Boolean]$IsInfo
        }
        $collectionWebsURL = New-Object -TypeName System.Collections.ArrayList
        $spWebApplications = Get-SPWebApplication -ErrorAction SilentlyContinue

        if ($null -ne $spWebApplications) {
            #Initialize ArrayList variable
            $tbSPAPIHttpStatus = New-Object -TypeName System.Collections.ArrayList
            foreach ($spWebApplication in $spWebApplications) {
                $getRootSPSite = Get-SPSite ($spWebApplication.url)
                if ($getRootSPSite) {
                    $rootSPSiteUrl = $getRootSPSite.Url
                    $collectionWebsURL = @{
                        RootSite    = @{
                            Url   = "$($rootSPSiteUrl)"
                            Title = 'Root SPSite'
                        }
                        UserProfile = @{
                            Url   = "$($rootSPSiteUrl)/_api/sp.userprofiles.peoplemanager/GetMyProperties"
                            Title = 'User Profile REST'
                        }
                        Search      = @{
                            Url   = "$($rootSPSiteUrl)/_api/search/query?querytext='*'&RowLimit=1"
                            Title = 'Search REST'
                        }
                    }
                    $useragent = [Microsoft.PowerShell.Commands.PSUserAgent]::Chrome
                    $authentUrl = ("$($rootSPSiteUrl)" + '/_windows/default.aspx?ReturnUrl=/_layouts/15/Authenticate.aspx?Source=%2f')
                    Write-Output "Getting webSession by opening $($authentUrl) with Invoke-WebRequest"
                    try {
                        Invoke-WebRequest -Uri $authentUrl `
                            -SessionVariable webSession `
                            -TimeoutSec 90 `
                            -UserAgent $useragent `
                            -UseDefaultCredentials `
                            -UseBasicParsing
                    }
                    catch {
                        Write-Warning -Message $_.Exception.Message
                    }

                    foreach ($collectionKey in $collectionWebsURL.keys) {
                        $exceptionResponse = $null
                        $httpCODE = $null
                        $webUrlStatus = 'Failed'
                        $webUrlPSO = $collectionWebsURL[$collectionKey]
                        $attempt = 1
                        while ($attempt -le 5 -and $httpCODE -ne '200') {
                            try {
                                $webUrlResponse = Invoke-WebRequest -Uri $webUrlPSO.Url `
                                    -WebSession $webSession `
                                    -TimeoutSec 90 `
                                    -UserAgent $useragent `
                                    -UseBasicParsing `
                                    -ErrorAction SilentlyContinue
                            }
                            catch [Net.WebException] {
                                $exceptionResponse = $_.Exception.Message
                            }
                            if ($exceptionResponse) {
                                $httpCODE = $exceptionResponse
                            }
                            else {
                                if ($webUrlResponse.StatusCode -eq 200) {
                                    $webUrlStatus = 'OK'
                                    $httpCODE = '200'
                                    $isMailInfo = $true
                                }
                                else {
                                    $httpCODE = $webUrlResponse.StatusCode
                                    $isMailInfo = $false
                                }
                            }
                            $attempt++
                        }
                        [void]$tbSPAPIHttpStatus.Add([APIHttpStatus]@{
                                Farm     = $params.farm
                                Title    = $webUrlPSO.Title;
                                Url      = $webUrlPSO.Url;
                                HTTPCode = $httpCODE;
                                Status   = $webUrlStatus
                                IsInfo   = $isMailInfo;
                            })
                    }
                }
            }
            return $tbSPAPIHttpStatus
        }
    }
    return $result
}
function Get-SPSSiteHttpStatus {
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
        class SPSiteHttpStatus {
            [System.String]$Farm
            [System.String]$Url
            [System.String]$HTTPCode
            [System.String]$Status
            [System.Boolean]$IsInfo
        }

        $spWebApplications = Get-SPWebApplication -ErrorAction SilentlyContinue
        #Initialize ArrayList variable
        $tbSPSiteHttpStatus = New-Object -TypeName System.Collections.ArrayList
        if ($null -ne $spWebApplications) {
            foreach ($webApp in $spWebApplications) {
                $getRootSPSite = Get-SPSite ($webApp.url)
                $useragent = [Microsoft.PowerShell.Commands.PSUserAgent]::Chrome
                $authentUrl = ("$($getRootSPSite.Url)" + '/_windows/default.aspx?ReturnUrl=/_layouts/15/Authenticate.aspx?Source=%2f')
                Write-Output "Getting webSession by opening $($authentUrl) with Invoke-WebRequest"
                try {
                    Invoke-WebRequest -Uri $authentUrl `
                        -SessionVariable webSession `
                        -TimeoutSec 90 `
                        -UserAgent $useragent `
                        -UseDefaultCredentials  `
                        -UseBasicParsing
                }
                catch {
                    Write-Warning -Message $_.Exception.Message
                }
                $sites = $webApp.sites | Where-Object -FilterScript { $_.url -notmatch "$env:COMPUTERNAME" -and $_.url -notmatch 'sitemaster-' }
                if ($sites.Count -ne 0) {
                    foreach ($site in $sites) {
                        $exceptionResponse = $null
                        $httpCODE = $null
                        $webUrlStatus = 'Failed'
                        $attempt = 1
                        while ($attempt -le 5 -and $httpCODE -ne '200') {
                            try {
                                $webUrlResponse = Invoke-WebRequest -Uri $site.RootWeb.Url `
                                    -WebSession $webSession `
                                    -TimeoutSec 90 `
                                    -UserAgent $useragent  `
                                    -UseBasicParsing `
                                    -ErrorAction SilentlyContinue
                            }
                            catch [Net.WebException] {
                                $exceptionResponse = $_.Exception.Message
                            }

                            if ($exceptionResponse) {
                                $httpCODE = $exceptionResponse
                            }
                            else {
                                if ($webUrlResponse.StatusCode -eq 200) {
                                    $webUrlStatus = 'OK'
                                    $httpCODE = '200'
                                    $isMailInfo = $true
                                }
                                else {
                                    $httpCODE = $webUrlResponse.StatusCode
                                    $isMailInfo = $false
                                }
                            }
                            $attempt++
                        }
                        [void]$tbSPSiteHttpStatus.Add([SPSiteHttpStatus]@{
                                Farm     = $params.Farm;
                                Url      = $site.RootWeb.Url;
                                HTTPCode = $httpCODE;
                                Status   = $webUrlStatus
                                IsInfo   = $isMailInfo;
                            })
                        $site.Dispose()
                    }
                }
            }
        }
        return $tbSPSiteHttpStatus
    }
    return $result
}
function Get-SPSFailedTimerJob {
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
        class FailedTimerJob {
            [System.String]$Farm
            [System.String]$server
            [System.String]$JobDefinitionTitle
            [System.String]$Status
        }
        try {
            $startTime = (Get-Date).AddDays(-1)
            $farm = Get-SPFarm
            $timerService = $farm.TimerService
            $failedJobs = $timerService.JobHistoryEntries | Where-Object -FilterScript {
                $_.Status -eq 'Failed' -and $_.StartTime -gt $startTime
            }

            if ($null -ne $failedJobs) {
                $spFailedJobs = $failedJobs | Select-Object -Property ServerName, JobDefinitionTitle, Status -Unique
                #Initialize ArrayList variable
                $tbfailedJobs = New-Object -TypeName System.Collections.ArrayList
                foreach ($failedJob in $spFailedJobs) {
                    [void]$tbfailedJobs.Add([FailedTimerJob]@{
                            farm               = $params.Farm;
                            server             = $failedJob.ServerName;
                            JobDefinitionTitle = $failedJob.JobDefinitionTitle;
                            Status             = $failedJob.Status
                        })
                }
                return $tbfailedJobs
            }
        }
        catch {
            return $_
        }
    }
    return $result
}
function Get-SPSHealthStatusFromCA {
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
        class HealthAnalyzerInfo {
            [System.String]$farm
            [System.String]$centraladmin
            [System.String]$title
            [System.String]$url
            [System.String]$severity
            [System.String]$category
            [System.String]$lastExecution
        }
        $spWebApplications = Get-SPWebApplication -IncludeCentralAdministration -ErrorAction SilentlyContinue
        if ($null -ne $spWebApplications) {
            $spWebApplication = $spWebApplications | Where-Object -FilterScript {
                $_.IsAdministrationWebApplication
            }
            if ($null -ne $spWebApplication) {
                $spWebCentralAdmin = Get-SPWeb -Identity $spWebApplication.Url -ErrorAction SilentlyContinue
                if ($null -ne $spWebCentralAdmin) {
                    #Get Health Analyzer list on Central Admin site
                    $healthList = $spWebCentralAdmin.GetList('\Lists\HealthReports')
                    $displayFormUrl = $spWebCentralAdmin.Url + ($healthList.Forms | Where-Object -FilterScript { $_.Type -eq "PAGE_DISPLAYFORM" }).ServerRelativeUrl

                    $queryString = "<Where><Neq><FieldRef Name='HealthReportSeverity' /><Value Type='Text'>4 - Success</Value></Neq></Where>"
                    $query = New-Object -TypeName Microsoft.SharePoint.SPQuery
                    $query.Query = $queryString
                    $items = $healthList.GetItems($query)
                    if ($null -ne $items) {

                        #Initialize ArrayList variable
                        $tbhealthListItems = New-Object -TypeName System.Collections.ArrayList

                        #Create HTML body by walking through each item and adding it to a table
                        foreach ($item in $items) {
                            $itemUrl = $displayFormUrl + "?id=" + $item.ID
                            [void]$tbhealthListItems.Add([HealthAnalyzerInfo]@{
                                    farm          = $params.Farm
                                    centraladmin  = $spWebApplication.Url;
                                    title         = $item.Title;
                                    url           = $itemUrl;
                                    severity      = $item["Severity"];
                                    category      = $item["Category"];
                                    lastExecution = $item["Modified"]
                                })
                        }
                        $spWebCentralAdmin.Dispose()
                    }
                }
                else {
                    Throw "The SPweb $($spWebApplication.Url) does not exist"
                }
            }
            else {
                Throw 'The SharePoint Central Administration does not exist in this farm'
            }
        }
        else {
            Throw 'No SPWebApplication object exists in this farm'
        }
        return $tbhealthListItems
    }
    return $result
}
function Get-SPSSolutionStatus {
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
        class WSPDeployment {
            [System.String]$Farm
            [System.String]$SolutionName
            [System.String]$DeploymentState
            [System.String]$LastOperationResult
            [System.String]$LastOperationEndTime
            [System.Boolean]$IsInfo
        }
        $spSolutions = (Get-SPFarm).solutions
        if ($null -ne $spSolutions) {
            #Initialize ArrayList variable
            $tbSPSolutions = New-Object -TypeName System.Collections.ArrayList
            foreach ($spSolution in $spSolutions) {
                if (($spSolution.LastOperationResult -ne [Microsoft.SharePoint.Administration.SPSolutionOperationResult]::DeploymentSucceeded) -and `
                    ($spSolution.LastOperationResult -ne [Microsoft.SharePoint.Administration.SPSolutionOperationResult]::RetractionSucceeded) -and `
                    ($spSolution.LastOperationResult -ne [Microsoft.SharePoint.Administration.SPSolutionOperationResult]::NoOperationPerformed)) {
                    $isMailInfo = $false
                }
                else {
                    $isMailInfo = $true
                }
                [void]$tbSPSolutions.Add([WSPDeployment]@{
                        farm                 = $params.Farm;
                        SolutionName         = $spSolution.Name;
                        DeploymentState      = $spSolution.DeploymentState;
                        LastOperationResult  = $spSolution.LastOperationResult;
                        LastOperationEndTime = $spSolution.LastOperationEndTime;
                        IsInfo               = $isMailInfo;
                    })
            }
            return $tbSPSolutions
        }
    }
    return $result
}
function Get-SPSUpgradeStatus {
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
        class UpgradeStatusInfo {
            [System.String]$farm
            [System.String]$server
            [System.String]$SPBuildVersion
            [System.String]$SPRegVersion
            [System.String]$UpgradeStatus
            [System.Boolean]$IsInfo
        }

        try {
            #Initialize ArrayList variable
            $tbUpgradeListItems = New-Object -TypeName System.Collections.ArrayList
            $spfarm = Get-SPFarm
            $spServers = (Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' })
            $productVersions = [Microsoft.SharePoint.Administration.SPProductVersions]::GetProductVersions($spfarm)
            $buildVersion = $spfarm.BuildVersion -Join '.'

            foreach ($spServer in $spServers) {
                $isMailInfo = $true
                # location in registry to get info about installed software
                $regLoc = Get-ChildItem HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall
                # Get SharePoint Products and language packs
                $programs = $regLoc |  Where-Object -FilterScript {
                    $_.PsPath -like '*\Office*'
                } | ForEach-Object -Process { Get-ItemProperty $_.PsPath }
                # output the info about Products and Language Packs
                $spsVersion = $programs | Where-Object -FilterScript {
                    $_.DisplayName -like '*SharePoint Server*'
                }
                $serverProductInfo = $productVersions.GetServerProductInfo($spServer.Id)
                if ($serverProductInfo.InstallStatus -ne 'NoActionRequired') {
                    $isMailInfo = $false
                }
                [void]$tbUpgradeListItems.Add([UpgradeStatusInfo]@{
                        farm           = $params.Farm
                        server         = $spServer.Address;
                        SPBuildVersion = $buildVersion;
                        SPRegVersion   = $spsVersion.DisplayVersion;
                        UpgradeStatus  = $serverProductInfo.InstallStatus
                        IsInfo         = $isMailInfo;
                    })
            }
            return $tbUpgradeListItems
        }
        catch {
            return $_
        }
    }
    return $result
}
function Get-SPSContentDBStatus {
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
        class SPDatabaseStatusInfo {
            [System.String]$farm
            [System.String]$SQLInstance
            [System.String]$DatabaseName
            [System.String]$Type
            [System.String]$Upgrade
            [System.String]$DiskSize
            [System.Boolean]$IsInfo
        }
        try {
            $spDatabases = Get-SPDatabase

            if ($null -ne $spDatabases) {
                #Initialize ArrayList variable
                $tbSPDatabases = New-Object -TypeName System.Collections.ArrayList
                foreach ($spDatabase in $spDatabases) {
                    $upgradeStatus = 'No Action Required'
                    $isMailInfo = $true
                    if ($null -ne $spDatabase.Server.Address) {
                        $sqlInstance = $spDatabase.Server.Address
                    }
                    else {
                        $sqlInstance = $spDatabase.Server
                    }
                    if ($spDatabase.NeedsUpgrade) {
                        $upgradeStatus = 'Upgrade Required'
                        $isMailInfo = $false
                    }
                    if ($spDatabase.Type.Contains('.')) {
                        $spDatabaseType = ([regex]::Matches($spDatabase.Type, '(?<=\.)[^.]*$')).value
                    }
                    else {
                        $spDatabaseType = $spDatabase.Type
                    }
                    [void]$tbSPDatabases.Add([SPDatabaseStatusInfo]@{
                            farm         = $params.Farm;
                            SQLInstance  = $sqlInstance;
                            DatabaseName = $spDatabase.Name;
                            Type         = $spDatabaseType;
                            Upgrade      = $upgradeStatus;
                            DiskSize     = ([math]::Round($spDatabase.DiskSizeRequired / 1GB, 2)).ToString();
                            IsInfo       = $isMailInfo;
                        })
                }
                return $tbSPDatabases
            }
        }
        catch {
            return $_
        }
    }
    return $result
}

function Get-SPSVersion {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    Write-Verbose "Getting SharePoint Version of Farm '$Server'"
    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments $PSBoundParameters `
        -Server $Server `
        -ScriptBlock {
        # location in registry to get info about installed software
        $regLoc = Get-ChildItem HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall
        # Get SharePoint Products and language packs
        $programs = $regLoc |  Where-Object -FilterScript {
            $_.PsPath -like '*\Office*'
        } | ForEach-Object -Process { Get-ItemProperty $_.PsPath }
        # output the info about Products and Language Packs
        $spsVersion = $programs | Where-Object -FilterScript {
            $_.DisplayName -like '*SharePoint Server*'
        }
        # Return SharePoint version
        return $spsVersion.DisplayVersion
    }
    return $result
}
function Get-USPAudienceStatus {
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
        class USPAudienceStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$StartTime
            [System.String]$EndTime
            [System.String]$Duration
            [System.String]$Status
        }

        $serviceAppUSP = Get-SPServiceApplication -ErrorAction SilentlyContinue | Where-Object -FilterScript {
            $_.GetType().FullName -eq 'Microsoft.Office.Server.Administration.UserProfileApplication'
        }

        if ($null -ne $serviceAppUSP) {
            $tbUSPAudienceStatus = New-Object -TypeName System.Collections.ArrayList
            $timerJob = Get-SPTimerJob | Where-Object -FilterScript { $_.Name -like '*_AudienceCompilationJob*' }
            if ($null -ne $timerJob) {
                $currentTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById([System.TimeZoneInfo]::Local.Id)
                $lastEntries = $timerJob.HistoryEntries | Where-Object -FilterScript { $_.StartTime -gt (Get-Date).AddDays(-1) }
                foreach ($lastEntry in $lastEntries) {
                    if ($null -ne $lastEntry.StartTime) {
                        $startTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($lastEntry.StartTime, $currentTimeZone)
                    }
                    if ($null -ne $lastEntry.EndTime) {
                        $endTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($lastEntry.EndTime, $currentTimeZone)
                    }
                    if (($null -ne $startTime) -and ($null -ne $endTime)) {
                        $duration = [math]::Round(($endTime - $startTime).TotalSeconds)
                    }
                    $supAudienceStatus = $lastEntry.Status
                    [void]$tbUSPAudienceStatus.Add([USPAudienceStatus]@{
                            Farm      = $params.Farm;
                            Server    = $lastEntry.ServerName;
                            StartTime = $startTime;
                            EndTime   = $endTime;
                            Duration  = $duration;
                            Status    = $supAudienceStatus;
                        })
                }
                return $tbUSPAudienceStatus
            }
        }
    }
    return $result
}
