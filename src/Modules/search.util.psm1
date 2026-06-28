function Get-SPSSearchEntCrawlStatus {
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
        class SearchContentLastCrawl {
            [System.String]$Farm
            [System.String]$SearchService
            [System.String]$ContentSource
            [System.String]$CrawlState
            [System.String]$Duration
            [System.String]$CrawlStarted
            [System.String]$CrawlCompleted
            [System.Boolean]$IsInfo
        }
        $spSearchEntSvc = Get-SPEnterpriseSearchServiceApplication -ErrorAction SilentlyContinue
        if ($null -ne $spSearchEntSvc) {
            $spSchContentSources = Get-SPEnterpriseSearchCrawlContentSource -SearchApplication $spSearchEntSvc
            if ($null -ne $spSchContentSources) {
                #Initialize ArrayList variable
                $tbSPSSearchEntCrawlStatus = New-Object -TypeName System.Collections.ArrayList

                foreach ($contentSource in $spSchContentSources) {
                    $spCrawlDuration = 'OK'
                    $isMailInfo = $true
                    if ($contentSource.CrawlState -ne 'Idle' -and `
                            $contentSource.CrawlStarted -lt ((Get-Date).AddHours(-2)) -and `
                            $contentSource.LevelHighErrorCount -gt '0') {
                        $spCrawlDuration = 'Error'
                        $isMailInfo = $false
                    }
                    [void]$tbSPSSearchEntCrawlStatus.Add([SearchContentLastCrawl]@{
                        Farm           = $params.Farm;
                        SearchService  = $spSearchEntSvc.Name;
                        ContentSource  = $contentSource.Name;
                        CrawlState     = $contentSource.CrawlState;
                        Duration       = $spCrawlDuration;
                        CrawlStarted   = $contentSource.CrawlStarted;
                        CrawlCompleted = $contentSource.CrawlCompleted;
                        IsInfo         = $isMailInfo;
                    })
                }
                return $tbSPSSearchEntCrawlStatus
            }
        }
    }
    return $result
}
function Get-SPSSearchEntCrawlLogs {
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
        class SearchContentCrawlLog {
            [System.String]$Farm
            [System.String]$SearchService
            [System.String]$ContentSource
            [System.String]$ErrorID
            [System.String]$Message
            [System.String]$Count
        }
        $spSearchEntSvc = Get-SPEnterpriseSearchServiceApplication -ErrorAction SilentlyContinue
        if ($null -ne $spSearchEntSvc) {
            $spSchContentSources = Get-SPEnterpriseSearchCrawlContentSource -SearchApplication $spSearchEntSvc
            if ($null -ne $spSchContentSources) {
                $spSchCrawlLogPso = New-Object Microsoft.Office.Server.Search.Administration.CrawlLog $spSearchEntSvc
                $tbSPSSearchEntCrawlLogs = New-Object -TypeName System.Collections.ArrayList

                foreach ($contentSource in $spSchContentSources) {
                    $getSPCrawlErrors = $spSchCrawlLogPso.GetCrawlErrors($contentSource.ID, -1)
                    if ($getSPCrawlErrors.Rows.Count -ne 0) {
                        foreach ($getSPCrawlError in $getSPCrawlErrors) {
                            [void]$tbSPSSearchEntCrawlLogs.Add([SearchContentCrawlLog]@{
                                Farm          = $params.Farm;
                                SearchService = $spSearchEntSvc.Name;
                                ContentSource = $contentSource.Name;
                                ErrorID       = $getSPCrawlError.ErrorID;
                                Message       = $getSPCrawlError.ErrorMessage;
                                Count         = $getSPCrawlError.ErrorCount;
                            })
                        }
                    }
                }
                return $tbSPSSearchEntCrawlLogs
            }
        }
    }
    return $result
}
function Get-SPSSearchEntTopology {
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
        class SearchTopologyStatus {
            [System.String]$Farm
            [System.String]$SearchService
            [System.String]$ComponentHost
            [System.String]$ComponentName
            [System.String]$State
            [System.Boolean]$IsInfo
        }
        $spSearchEntSvc = Get-SPEnterpriseSearchServiceApplication -ErrorAction SilentlyContinue
        if ($null -ne $spSearchEntSvc) {
            $getSchStatus = Get-SPEnterpriseSearchStatus -SearchApplication $spSearchEntSvc -Detailed
            if ($null -ne $getSchStatus) {
                $tbSearchTopologyStatus = New-Object -TypeName System.Collections.ArrayList
                foreach ($compoSch in $getSchStatus) {
                    $isMailInfo = $True
                    if ($compoSch.State -ne 'Active') {
                        $isMailInfo = $false
                    }
                    if ($null -eq $compoSch.Details['Host']) {
                        $spComponentServer = 'NotApplicable'
                    }
                    else {
                        $spComponentServer = $($compoSch.Details['Host']).ToUpper()
                    }
                    [void]$tbSearchTopologyStatus.Add([SearchTopologyStatus]@{
                        Farm             = $params.Farm;
                        SearchService    = $spSearchEntSvc.Name;
                        ComponentHost    = $spComponentServer;
                        ComponentName    = $compoSch.Name;
                        State            = $compoSch.State;
                        IsInfo           = $isMailInfo;
                    })
                }
                return $tbSearchTopologyStatus
            }
        }
    }
    return $result
}
