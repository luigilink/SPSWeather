function Get-SPSWeatherEmailAreaMap {
    <#
        .SYNOPSIS
        Maps the report sections to the functional areas shown in the emails.

        .DESCRIPTION
        Returns Map (section name -> icon and area id; the area name is the Area_<id> resource)
        and Order (the order in which the areas are listed). A section that is not in the map is
        counted in the totals but not listed under an area. Shared by ConvertTo-SPSWeatherEmailBody
        and ConvertTo-SPSWeatherConsolidatedEmail so that both group the checks the same way.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param()

    $areaOf = @{
        SPUpgradeStatus = @('&#127970;', 'FarmUpgrade'); SPAPIHttpStatus = @('&#127760;', 'TrustFarm'); SPSSitesHttpStatus = @('&#127760;', 'TrustFarm')
        SPSearchLastCrawlStatus = @('&#128269;', 'Search'); SPSearchCrawlLogs = @('&#128269;', 'Search'); SPSSearchEntTopology = @('&#128269;', 'Search')
        AppFabricStatus = @('&#9889;', 'DistributedCache'); SPTimerServiceStatus = @('&#9201;', 'TimerJobs'); SPFailedTimerJobs = @('&#9201;', 'TimerJobs'); SPSolutionDeployment = @('&#9201;', 'Solutions'); USPAudienceStatus = @('&#9201;', 'UserProfiles')
        SPHealthAnalyzer = @('&#129657;', 'HealthAnalyzer'); IISApplicationPoolStatus = @('&#128421;', 'IIS'); IISWorkerProcessStatus = @('&#128421;', 'IIS'); IISWebSiteCertStatus = @('&#128421;', 'IIS')
        SYSDiskUsageStatus = @('&#129513;', 'System'); SYSLastRebootStatus = @('&#129513;', 'System'); SYSEventViewerAppErrors = @('&#129513;', 'System')
        SPSContentDBStatus = @('&#128451;', 'SQL'); SQLInstanceStatus = @('&#128451;', 'SQL'); SQLDatabaseStatus = @('&#128451;', 'SQL'); SQLDiskStatus = @('&#128451;', 'SQL'); SQLAvailabilityStatus = @('&#128451;', 'SQL'); SQLAliasStatus = @('&#128451;', 'SQL')
    }
    $areaOrder = @('FarmUpgrade', 'TrustFarm', 'Search', 'DistributedCache', 'TimerJobs', 'Solutions', 'UserProfiles', 'HealthAnalyzer', 'IIS', 'System', 'SQL')

    return [PSCustomObject]@{ Map = $areaOf; Order = $areaOrder }
}
