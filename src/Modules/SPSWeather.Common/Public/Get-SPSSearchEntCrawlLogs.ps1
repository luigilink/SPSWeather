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
