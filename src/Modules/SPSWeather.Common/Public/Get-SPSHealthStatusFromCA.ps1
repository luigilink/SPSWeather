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
