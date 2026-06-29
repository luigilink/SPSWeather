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
            $tbSPSSearchEntCrawlLogs = New-Object -TypeName System.Collections.ArrayList
            try {
                $spSchContentSources = Get-SPEnterpriseSearchCrawlContentSource -SearchApplication $spSearchEntSvc -ErrorAction Stop
                $spSchCrawlLogPso = New-Object Microsoft.Office.Server.Search.Administration.CrawlLog $spSearchEntSvc
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
            }
            catch {
                [void]$tbSPSSearchEntCrawlLogs.Add([SearchContentCrawlLog]@{
                    Farm          = $params.Farm;
                    SearchService = $spSearchEntSvc.Name;
                    ContentSource = 'Search unavailable';
                    ErrorID       = '503';
                    Message       = $_.Exception.Message;
                    Count         = '0';
                })
            }
            return $tbSPSSearchEntCrawlLogs
        }
    }
    return $result
}
