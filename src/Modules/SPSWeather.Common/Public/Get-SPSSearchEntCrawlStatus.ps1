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
            #Initialize ArrayList variable
            $tbSPSSearchEntCrawlStatus = New-Object -TypeName System.Collections.ArrayList
            try {
                $spSchContentSources = Get-SPEnterpriseSearchCrawlContentSource -SearchApplication $spSearchEntSvc -ErrorAction Stop
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
            }
            catch {
                [void]$tbSPSSearchEntCrawlStatus.Add([SearchContentLastCrawl]@{
                    Farm           = $params.Farm;
                    SearchService  = $spSearchEntSvc.Name;
                    ContentSource  = 'Search unavailable';
                    CrawlState     = $_.Exception.Message;
                    Duration       = 'Error';
                    CrawlStarted   = '';
                    CrawlCompleted = '';
                    IsInfo         = $false;
                })
            }
            return $tbSPSSearchEntCrawlStatus
        }
    }
    return $result
}
