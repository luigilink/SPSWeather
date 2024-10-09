# Initialize HTML Head
$htmlHEADER =
@"
<!DOCTYPE html>
<html lang="fr" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="x-apple-disable-message-reformatting">
    <title>CAGIP - SPWeather</title>
    <!--[if mso]> <xml> <o:OfficeDocumentSettings>  <o:AllowPNG/> <o:PixelsPerInch>96</o:PixelsPerInch> </o:OfficeDocumentSettings> </xml> <![endif]-->
    <!--[if lte mso 11]> <style type="text/css"> .mj-outlook-group-fix { width:100% !important; } </style> <![endif]-->
    <style>
        body {margin: 0;padding: 0;-webkit-text-size-adjust: 100%;-ms-text-size-adjust: 100%;background-color:#ffffff;}
        #spweathermain {margin:0px auto;max-width:777px;text-align: center;background-color:#ffffff;}
        table,td {border-collapse: collapse;border: 2px solid #000000 !important}
        table {width: 100%;border-collapse: collapse;border: 1px solid #cccccc;border-spacing: 0;text-align: left;}
        img {border: 0;height: auto;line-height: 100%;outline: none;text-decoration: none;-ms-interpolation-mode:bicubic;}
        .tdheader {padding: 0;background: #70bbd9;}
        .tddefault {padding: 0;}
        .tditalic {padding: 0;font-style: italic;}
        .tdfailed {padding: 0;background: #ff6464;}
        .tdwarning {padding: 0;background: #ff9966;}
        .tdsuccess {padding: 0;background: #bfff80;}
        table,td,div,h1,h2,p {font-family: Arial, sans-serif;}
    </style>
</head>
<body>
<div id="spweathermain">
"@

$htmlFOOTER =
@"
</div>
</body>
</html>
"@

function Join-HtmlTable {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param (
        [Parameter()]
        [System.String]
        $TitleH1,

        [Parameter()]
        [System.String]
        $TableRole,

        [Parameter()]
        [System.String[]]
        $TableHeaders,

        [Parameter()]
        $TableRows
    )

    $bodyToMerge =
@"
<h1>$TitleH1</h1>
<table role="$TableRole"><tr>
"@

    foreach ($tableHeader in $TableHeaders) {
        $bodyToMerge += "<td class=`"tdheader`">$tableHeader</td>"
    }
    $bodyToMerge += "</tr>$TableRows</table>"

    return $bodyToMerge
}
function Join-HtmlBodyFromPSo {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param (
        [Parameter()]
        $PSObjectFromJson
    )

    $htmlBodyMerge = @()
    if (($PSObjectFromJson.SPWeatherListInfo).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPWeatherListInfoItem in ($PSObjectFromJson.SPWeatherListInfo)) {
            $htmlTableRows += "<tr><td align=`"center`" class=`"tddefault`">$($SPWeatherListInfoItem.PSVersion)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SPWeatherListInfoItem.UserAccount)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SPWeatherListInfoItem.DateStarted)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SPWeatherListInfoItem.DateEnded)</td></tr>"
            $htmltTitle     = "SPWeather V$($SPWeatherListInfoItem.Version) - $($SPWeatherListInfoItem.Application) - $($SPWeatherListInfoItem.Environment)"
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 $htmltTitle `
                                         -TableRole 'SPWeatherListInfo' `
                                         -TableHeaders @('PowerShell Version','Executed By','Started','Finished') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SPSiteHttpStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPSiteHttpStatusItem in ($PSObjectFromJson.SPSiteHttpStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SPSiteHttpStatusItem.Server)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSiteHttpStatusItem.Url)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SPSiteHttpStatusItem.HTTPCode)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SPSiteHttpStatusItem.Time)</td>"
            if ($SPSiteHttpStatusItem.Status -ne 'OK') {
                $htmlTableRows += "<td align=`"center`" class=`"tdfailed`">$($SPSiteHttpStatusItem.Status)</td></tr>"
            }
            else{
                $htmlTableRows += "<td align=`"center`" class=`"tdsuccess`">$($SPSiteHttpStatusItem.Status)</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SharePoint Sites Web Request Status' `
                                         -TableRole 'SharePointSiteStatus' `
                                         -TableHeaders @('Server','Url','HTTP Code','Time (seconds)','Status') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SPAPIHttpStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPAPIHttpStatusItem in ($PSObjectFromJson.SPAPIHttpStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SPAPIHttpStatusItem.Farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPAPIHttpStatusItem.Title)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPAPIHttpStatusItem.Url)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SPAPIHttpStatusItem.HTTPCode)</td>"
            if ($SPAPIHttpStatusItem.Status -ne 'OK') {
                $htmlTableRows += "<td align=`"center`" class=`"tdfailed`">$($SPAPIHttpStatusItem.Status)</td></tr>"
            }
            else{
                $htmlTableRows += "<td align=`"center`" class=`"tdsuccess`">$($SPAPIHttpStatusItem.Status)</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SharePoint Trust Farm Status' `
                                         -TableRole 'SharePointAPIStatus' `
                                         -TableHeaders @('Farm','Title','Url','HTTP Code','Status') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SPSSitesHttpStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPSSitesHttpStatusItem in ($PSObjectFromJson.SPSSitesHttpStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SPSSitesHttpStatusItem.Farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSSitesHttpStatusItem.Url)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SPSSitesHttpStatusItem.HTTPCode)</td>"
            if ($SPSSitesHttpStatusItem.Status -ne 'OK') {
                $htmlTableRows += "<td align=`"center`" class=`"tdfailed`">$($SPSSitesHttpStatusItem.Status)</td></tr>"
            }
            else{
                $htmlTableRows += "<td align=`"center`" class=`"tdsuccess`">$($SPSSitesHttpStatusItem.Status)</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SharePoint Site Collection Status' `
                                         -TableRole 'SharePointSPSiteStatus' `
                                         -TableHeaders @('Farm','Url','HTTP Code','Status') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SPUpgradeStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPUpgradeStatusItem in ($PSObjectFromJson.SPUpgradeStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SPUpgradeStatusItem.farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPUpgradeStatusItem.server)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPUpgradeStatusItem.SPBuildVersion)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPUpgradeStatusItem.SPRegVersion)</td>"
            if ($SPUpgradeStatusItem.UpgradeStatus -ne "NoActionRequired") {
                $htmlTableRows += "<td class=`"tdfailed`">Action Required</td></tr>"
            }
            else{
                $htmlTableRows += "<td class=`"tdsuccess`">No Action Required</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SharePoint Upgrade Status' `
                                         -TableRole 'SPUpgradeStatus' `
                                         -TableHeaders @('Farm','Server Name','SP Build Version','SP Version from Registry','Upgrade Status') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SPSContentDBStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPSContentDBStatusItem in ($PSObjectFromJson.SPSContentDBStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SPSContentDBStatusItem.farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSContentDBStatusItem.SQLInstance)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSContentDBStatusItem.DatabaseName)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSContentDBStatusItem.Type)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSContentDBStatusItem.DiskSize)</td>"
            if ($SPSContentDBStatusItem.Upgrade -ne 'No Action Required') {
                $htmlTableRows += "<td class=`"tdfailed`">Upgrade Required</td></tr>"
            }
            else{
                $htmlTableRows += "<td class=`"tdsuccess`">No Action Required</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SharePoint Database Status' `
                                         -TableRole 'SPSContentDBStatus' `
                                         -TableHeaders @('Farm','SQL Instance','Database Name','Type','Size (GB)','Upgrade Status') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SPHealthAnalyzer).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPHealthAnalyzerItem in ($PSObjectFromJson.SPHealthAnalyzer)) {
            if ($null -ne $SPHealthAnalyzerItem) {
                $htmlTableRows += "<tr><td class=`"tddefault`">$($SPHealthAnalyzerItem.farm)</td>"
                $htmlTableRows += "<td class=`"tddefault`">$($SPHealthAnalyzerItem.centraladmin)</td>"
                $htmlTableRows += "<td class=`"tddefault`"><a href=`"" + $($SPHealthAnalyzerItem.url) + "`">" + $SPHealthAnalyzerItem.Title + "</a></td>"
                if ($SPHealthAnalyzerItem.severity -like '*Error*'){
                    $htmlTableRows += "<td class=`"tdfailed`">$($SPHealthAnalyzerItem.severity)</td>"
                }
                elseif ($SPHealthAnalyzerItem.severity -like '*Warning*'){
                    $htmlTableRows += "<td class=`"tdwarning`">$($SPHealthAnalyzerItem.severity)</td>"
                }
                else {
                    $htmlTableRows += "<td class=`"tddefault`">$($SPHealthAnalyzerItem.severity)</td>"
                }
                $htmlTableRows += "<td class=`"tddefault`">$($SPHealthAnalyzerItem.category)</td>"
                $htmlTableRows += "<td class=`"tddefault`">$($SPHealthAnalyzerItem.lastExecution)</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'Health Analyzer Review' `
                                         -TableRole 'HealthAnalyzerReview' `
                                         -TableHeaders @('Farm','Central Admin','Title','Severity','Category','Last Execution') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SPFailedTimerJobs).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPFailedTimerJobsItem in ($PSObjectFromJson.SPFailedTimerJobs)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SPFailedTimerJobsItem.Farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPFailedTimerJobsItem.server)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPFailedTimerJobsItem.JobDefinitionTitle)</td>"
            $htmlTableRows += "<td class=`"tdfailed`">$($SPFailedTimerJobsItem.Status)</td></tr>"
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SharePoint Failed Timer Jobs Status last 24h' `
                                         -TableRole 'SPFailedTimerJobStatus' `
                                         -TableHeaders @('Farm','Server Name','Job Definition Title','Status') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.AppFabricStatus).Count -ne 0){
        $htmlTableRows = @()
        foreach ($AppFabricStatusItem in ($PSObjectFromJson.AppFabricStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($AppFabricStatusItem.Farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($AppFabricStatusItem.server)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($AppFabricStatusItem.Port)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($AppFabricStatusItem.ServiceName)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($AppFabricStatusItem.Size)</td>"
            if ($AppFabricStatusItem.CacheStatus -ne 'Up') {
                $htmlTableRows += "<td align=`"center`" class=`"tdfailed`">$($AppFabricStatusItem.CacheStatus)</td>"
            }
            else{
                $htmlTableRows += "<td align=`"center`" class=`"tdsuccess`">$($AppFabricStatusItem.CacheStatus)</td>"
            }
            if ($AppFabricStatusItem.SPInstanceStatus -ne 'Online') {
                $htmlTableRows += "<td align=`"center`" class=`"tdfailed`">$($AppFabricStatusItem.SPInstanceStatus)</td></tr>"
            }
            else{
                $htmlTableRows += "<td align=`"center`" class=`"tdsuccess`">$($AppFabricStatusItem.SPInstanceStatus)</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SharePoint Distributed Cache Status' `
                                         -TableRole 'AppFabricStatus' `
                                         -TableHeaders @('Farm','Server','Port','Service Name','Size (MB)','Status','SP Instance') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SPSolutionDeployment).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPSolutionDeploymentItem in ($PSObjectFromJson.SPSolutionDeployment)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SPSolutionDeploymentItem.Farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSolutionDeploymentItem.SolutionName)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSolutionDeploymentItem.DeploymentState)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSolutionDeploymentItem.LastOperationResult)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSolutionDeploymentItem.LastOperationEndTime)</td></tr>"
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SharePoint Deployment Solution Status' `
                                         -TableRole 'SPSolutionStatus' `
                                         -TableHeaders @('Farm','Solution Name','Deployment State','Last Operation Result','Last Operation End Time') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.USPAudienceStatus).Count -ne 0){
        $htmlTableRows = @()
        foreach ($USPAudienceStatusItem in ($PSObjectFromJson.USPAudienceStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($USPAudienceStatusItem.Server)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($USPAudienceStatusItem.StartTime)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($USPAudienceStatusItem.endTime)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($USPAudienceStatusItem.duration)</td>"
            if ($USPAudienceStatusItem.Status -ne 'Succeeded') {
                $htmlTableRows += "<td align=`"center`" class=`"tdfailed`">$($USPAudienceStatusItem.Status)</td></tr>"
            }
            else{
                $htmlTableRows += "<td align=`"center`" class=`"tdsuccess`">$($USPAudienceStatusItem.Status)</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'User Profile Audience Compilation Status last 24h' `
                                         -TableRole 'USPAudienceStatus' `
                                         -TableHeaders @('Server','Start Time','End Time','Duration (seconds)','Status') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SPSSearchEntTopology).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPSSearchEntTopologyItem in ($PSObjectFromJson.SPSSearchEntTopology)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SPSSearchEntTopologyItem.SearchService)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSSearchEntTopologyItem.ComponentHost)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSSearchEntTopologyItem.ComponentName)</td>"
            if ($SPSSearchEntTopologyItem.State -ne 'Active') {
                $htmlTableRows += "<td align=`"center`" class=`"tdfailed`">$($SPSSearchEntTopologyItem.State)</td></tr>"
            }
            else{
                $htmlTableRows += "<td align=`"center`" class=`"tdsuccess`">$($SPSSearchEntTopologyItem.State)</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'Search - Component Topology Status' `
                                         -TableRole 'SearchEntTopologyStatus' `
                                         -TableHeaders @('Search Service','Server','Component','Status') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SPSearchLastCrawlStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPSearchLastCrawlItem in ($PSObjectFromJson.SPSearchLastCrawlStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SPSearchLastCrawlItem.SearchService)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSearchLastCrawlItem.ContentSource)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSearchLastCrawlItem.CrawlState)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSearchLastCrawlItem.Duration)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSearchLastCrawlItem.CrawlStarted)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SPSearchLastCrawlItem.CrawlCompleted)</td></tr>"
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'Search - Content Last Crawl Status' `
                                         -TableRole 'SearchContentLastCrawl' `
                                         -TableHeaders @('Search Service','Content source','Crawl State','Duration','Crawl Started','Crawl Completed') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SPSearchCrawlLogs).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SPSearchCrawlLogsItem in ($PSObjectFromJson.SPSearchCrawlLogs)) {
            if ($null -ne $SPSearchCrawlLogsItem) {
                $htmlTableRows += "<tr><td class=`"tddefault`">$($SPSearchCrawlLogsItem.SearchService)</td>"
                $htmlTableRows += "<td class=`"tddefault`">$($SPSearchCrawlLogsItem.ContentSource)</td>"
                $htmlTableRows += "<td class=`"tddefault`">$($SPSearchCrawlLogsItem.ErrorID)</td>"
                $htmlTableRows += "<td class=`"tddefault`">$($SPSearchCrawlLogsItem.Message)</td>"
                $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SPSearchCrawlLogsItem.Count)</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'Search - Content Crawl Logs' `
                                         -TableRole 'SearchContentCrawlLogs' `
                                         -TableHeaders @('Search Service','Content source','Error ID','Message','Count') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.IISApplicationPoolStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($IISApplicationPoolItem in ($PSObjectFromJson.IISApplicationPoolStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($IISApplicationPoolItem.Farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($IISApplicationPoolItem.Server)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($IISApplicationPoolItem.ApplicationPool)</td>"

            if ($IISApplicationPoolItem.ApplicationPool -eq 'SharePoint Web Services Root'){
                $htmlTableRows += "<td align=`"center`" class=`"tddefault`">Stopped</td>"
                if ($IISApplicationPoolItem.Status -eq 'Stopped'){
                    $htmlTableRows += "<td align=`"center`" class=`"tdsuccess`">$($IISApplicationPoolItem.Status)</td></tr>"
                }
                else{
                    $htmlTableRows += "<td align=`"center`" class=`"tdfailed`">$($IISApplicationPoolItem.Status)</td></tr>"
                }
            }
            else{
                $htmlTableRows += "<td align=`"center`" class=`"tddefault`">Started</td>"
                if ($IISApplicationPoolItem.Status -eq 'Started'){
                    $htmlTableRows += "<td align=`"center`" class=`"tdsuccess`">$($IISApplicationPoolItem.Status)</td></tr>"
                }
                else{
                    $htmlTableRows += "<td align=`"center`" class=`"tdfailed`">$($IISApplicationPoolItem.Status)</td></tr>"
                }
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'IIS - Application Pool Status' `
                                         -TableRole 'IISApplicationPoolStatus' `
                                         -TableHeaders @('Farm','Server','Application Pool','Desired Status','Status') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.IISWorkerProcessStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($IISWorkerProcessItem in ($PSObjectFromJson.IISWorkerProcessStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($IISWorkerProcessItem.Farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($IISWorkerProcessItem.Server)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($IISWorkerProcessItem.ApplicationPool)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($IISWorkerProcessItem.Memory)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($IISWorkerProcessItem.CreationDate)</td></tr>"
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'IIS - Worker Process Status' `
                                         -TableRole 'IISWorkerProcessStatus' `
                                         -TableHeaders @('Farm','Server','Application Pool','Memory (MB)','Creation Date') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.IISWebSiteCertStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($IISWebSiteCertStatusItem in ($PSObjectFromJson.IISWebSiteCertStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($IISWebSiteCertStatusItem.Farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($IISWebSiteCertStatusItem.Server)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($IISWebSiteCertStatusItem.WebSiteName)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($IISWebSiteCertStatusItem.ExpirationDate)</td>"
            if ($IISWebSiteCertStatusItem.Status -eq 'OK'){
                $htmlTableRows += "<td align=`"center`" class=`"tdsuccess`">$($IISWebSiteCertStatusItem.Status)</td></tr>"
            }
            else{
                $htmlTableRows += "<td align=`"center`" class=`"tdfailed`">$($IISWebSiteCertStatusItem.Status)</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'IIS - SSL Certificates Expiration Status' `
                                         -TableRole 'IISWebSiteCertStatus' `
                                         -TableHeaders @('Farm','Server','Web Site Name','Expiration Date','Status') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SYSLastRebootStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SYSLastRebootStatusItem in ($PSObjectFromJson.SYSLastRebootStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SYSLastRebootStatusItem.Farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SYSLastRebootStatusItem.Server)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SYSLastRebootStatusItem.OSName)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SYSLastRebootStatusItem.OSVersion)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SYSLastRebootStatusItem.LastRebootTime)</td></tr>"
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SYSTEM - Last Reboot Status' `
                                         -TableRole 'LastRebootStatus' `
                                         -TableHeaders @('Farm','Server','OS Name','OS Version','Last Reboot Time') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SYSDOTNETVersion).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SYSDOTNETVersionItem in ($PSObjectFromJson.SYSDOTNETVersion)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SYSDOTNETVersionItem.Farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SYSDOTNETVersionItem.Server)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SYSDOTNETVersionItem.NetVersion)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SYSDOTNETVersionItem.NetRequiredVersion)</td></tr>"
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SYSTEM - .NET Framework Version' `
                                         -TableRole 'SYSDOTNETVersion' `
                                         -TableHeaders @('Farm','Server','Net Version','Required Version') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SYSEventViewerAppErrors).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SYSEventViewerAppError in ($PSObjectFromJson.SYSEventViewerAppErrors)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SYSEventViewerAppError.Server)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SYSEventViewerAppError.Server)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SYSEventViewerAppError.ID)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SYSEventViewerAppError.Severity)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SYSEventViewerAppError.Name)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SYSEventViewerAppError.Count)</td></tr>"
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SYSTEM - Event Viewer Application last 24h' `
                                         -TableRole 'EventViewerApplicationErrors' `
                                         -TableHeaders @('Farm','Server','ID','Severity','Name','Count') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SYSDiskUsageStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SYSDiskUsageStatusItem in ($PSObjectFromJson.SYSDiskUsageStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SYSDiskUsageStatusItem.Farm)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SYSDiskUsageStatusItem.Server)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SYSDiskUsageStatusItem.DriveLetter)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SYSDiskUsageStatusItem.Size)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SYSDiskUsageStatusItem.FreeSpace)</td>"
            if ($SYSDiskUsageStatusItem.Status -eq 'OK'){
                $htmlTableRows += "<td align=`"center`" class=`"tdsuccess`">$($SYSDiskUsageStatusItem.Status)</td></tr>"
            }
            else{
                $htmlTableRows += "<td align=`"center`" class=`"tdfailed`">$($SYSDiskUsageStatusItem.Status)</td></tr>"
            }
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SYSTEM - Server Disks Usage Status' `
                                         -TableRole 'DiskUsageStatus' `
                                         -TableHeaders @('Farm','Server','DriveLetter','Size (GB)','Free Space (GB)','Status') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SQLInstancesStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SQLInstancesStatusItem in ($PSObjectFromJson.SQLInstancesStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SQLInstancesStatusItem.Server)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SQLInstancesStatusItem.InstanceName)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SQLInstancesStatusItem.Version)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SQLInstancesStatusItem.ProductLevel)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SQLInstancesStatusItem.UpdateLevel)</td>"
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SQL - Instance Status' `
                                         -TableRole 'SQLInstanceStatus' `
                                         -TableHeaders @('Server','InstanceName','Version','ProductLevel','UpdateLevel') `
                                         -TableRows $htmlTableRows
    }
    if (($PSObjectFromJson.SQLDatabasesStatus).Count -ne 0) {
        $htmlTableRows = @()
        foreach ($SQLDatabasesStatusItem in ($PSObjectFromJson.SQLDatabasesStatus)) {
            $htmlTableRows += "<tr><td class=`"tddefault`">$($SQLDatabasesStatusItem.Server)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SQLDatabasesStatusItem.Instance)</td>"
            $htmlTableRows += "<td class=`"tddefault`">$($SQLDatabasesStatusItem.Name)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SQLDatabasesStatusItem.Status)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SQLDatabasesStatusItem.Size)</td>"
            $htmlTableRows += "<td align=`"center`" class=`"tddefault`">$($SQLDatabasesStatusItem.SpaceAvailable)</td>"
        }
        $htmlBodyMerge += Join-HtmlTable -TitleH1 'SQL - Database Status' `
                                         -TableRole 'SQLDatabaseStatus' `
                                         -TableHeaders @('Server','Instance','Database','Status','Size (GB)','SpaceAvailable (MB)') `
                                         -TableRows $htmlTableRows
    }
    $htmlBody = $htmlHEADER + $htmlBodyMerge +$htmlFOOTER
    return $htmlBody
}
