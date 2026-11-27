@{
    RootModule        = 'SPSWeather.Common.psm1'
    ModuleVersion     = '3.5.0'
    GUID              = 'c39bd612-8520-4e65-9037-80060894d654'
    Author            = 'Jean-Cyril DROUHIN'
    CompanyName       = 'luigilink'
    Copyright         = '(c) Jean-Cyril DROUHIN. All rights reserved.'
    Description       = 'Shared functions for the SPSWeather toolkit (SharePoint Server farm health checks: SharePoint, search, system/IIS, SQL and HTML report helpers).'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Add-SPSSheduledTask'
        'Add-SPSWeatherEvent'
        'Add-SPSWeatherRunJournalEntry'
        'Backup-SPSWeatherJsonFile'
        'Clear-SPSLog'
        'Compare-SPSWeatherSnapshots'
        'ConvertTo-SPSWeatherConsolidatedEmail'
        'ConvertTo-SPSWeatherEmailBody'
        'ConvertTo-SPSWeatherReport'
        'Export-SPSWeatherCockpit'
        'Export-SPSWeatherReport'
        'Get-AppFabricStatus'
        'Get-SPSAPIHttpStatus'
        'Get-SPSContentDBStatus'
        'Get-SPSFailedTimerJob'
        'Get-SPSHealthStatusFromCA'
        'Get-SPSInstalledProductVersion'
        'Get-SPSScheduledTaskSmtpCheck'
        'Get-SPSSearchEntCrawlLogs'
        'Get-SPSSearchEntCrawlStatus'
        'Get-SPSSearchEntTopology'
        'Get-SPSSecret'
        'Get-SPSServer'
        'Get-SPSSiteHttpStatus'
        'Get-SPSSolutionStatus'
        'Get-SPSSqlStatus'
        'Get-SPSTimerServiceStatus'
        'Get-SPSUpgradeStatus'
        'Get-SPSVersion'
        'Get-SPSWeatherHistory'
        'Get-SPSWeatherRunSetting'
        'Get-SPSWeatherTaskName'
        'Get-SPWeatherListInfo'
        'Get-SYSDiskUsageStatus'
        'Get-SYSDOTNETVersion'
        'Get-SYSEvtAppErrors'
        'Get-SYSIISAppPoolStatus'
        'Get-SYSIISSiteCertStatus'
        'Get-SYSIISW3WPEXEStatus'
        'Get-SYSLastRebootStatus'
        'Get-USPAudienceStatus'
        'Import-SPSSharePointCommand'
        'Remove-SPSSheduledTask'
        'Resolve-SPSCockpitSetting'
        'Resolve-SPSSmtpSetting'
        'Resolve-SPSSqlAlias'
        'Resolve-SPSWeatherLanguage'
        'Set-SPSCredSSPClient'
        'Set-SPSSecret'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('SharePoint', 'SharePointServer', 'HealthCheck', 'Monitoring', 'IIS', 'SQL')
            LicenseUri   = 'https://github.com/luigilink/SPSWeather/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/luigilink/SPSWeather'
            ReleaseNotes = 'https://github.com/luigilink/SPSWeather/blob/main/RELEASE-NOTES.md'
        }
    }
}
