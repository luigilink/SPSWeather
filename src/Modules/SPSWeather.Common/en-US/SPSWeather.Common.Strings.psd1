# SPSWeather.Common - display strings (en-US, the reference culture).
#
# One file per culture, in <module>\<culture>\ (see the wiki page 'Localization').
# - Keys are stable identifiers: never rename one without updating the code that uses it.
# - Values are plain text, never HTML: the renderers HTML-encode them.
# - {0}, {1}... are placeholders filled by the code; keep them all, in any order.
# - Only the display is translated. Collector values (Unreachable, Failed, notes...), the
#   detail-table column headers and the email subject tags stay in English on purpose: the
#   severity model and the history rely on them.
# - Save as UTF-8 with BOM (Windows PowerShell 5.1 needs it to read accented characters).
# - An apostrophe inside a value is written '' (two ASCII quotes): PowerShell treats typographic
#   apostrophes as string delimiters, so never use them in a value.

@{
    # Culture metadata
    Culture  = 'en-US'
    HtmlLang = 'en'

    # Dashboard: header, donut and run history
    DashboardTitle = 'SPSWeather Dashboard'
    FarmLabel      = 'Farm'
    Generated      = 'Generated'
    NeedAttention  = '{0} item(s) need attention'
    OverallHealth  = 'Overall health'
    Healthy        = 'healthy'
    Percent = '{0}%'
    ShortOk        = 'OK'
    ShortWarn      = 'Warn'
    ShortFail      = 'Fail'
    RunHistory     = 'Run history'
    LastRunsMany       = 'last {0} runs'
    LastRunsOne = 'last run'
    LegendWarning  = 'Warning'
    LegendFailure  = 'Failure'
    HoverBar       = 'hover a bar for the run totals'
    HistoryDateFormat = 'MM-dd'
    NowSuffix      = ' (now)'
    BarTip         = '{0}: {1} OK / {2} warn / {3} fail'

    # Dashboard: areas, detail and footer
    HealthByArea = 'Health by area'
    Detail       = 'Detail'
    ExpandAll    = 'Expand all'
    CollapseAll  = 'Collapse all'
    ViewDetail   = 'View detail'
    PillFailed   = '{0} failed'
    PillWarning  = '{0} warning'
    RowAlert     = '{0} alert'
    RowWarn      = '{0} warn'
    RowOk        = '{0} OK'
    RowInfo      = '{0} info'
    ExecutedBy   = 'Executed by'

    # Weather
    WeatherLabel  = 'Weather'
    WeatherSunny  = 'Sunny'
    WeatherFair   = 'Fair'
    WeatherCloudy = 'Cloudy'
    WeatherStormy = 'Stormy'

    # Alert email
    ItemCountOne     = '{0} item'
    ItemCountMany    = '{0} items'
    FailureOne       = '{0} failure'
    FailureMany      = '{0} failures'
    WarningOne       = '{0} warning'
    WarningMany      = '{0} warnings'
    MoreItems        = '+ {0} more ({1})'
    MoreSeeDashboard = 'see the dashboard for the full list'
    AllClearTitle    = 'All clear.'
    AllClearText     = 'No item needs attention on this farm.'
    IntroAttention   = '{0} need your attention on {1}. Full detail is in the dashboard.'
    IntroClear       = 'No item needs attention on {0}.'
    KpiFailures      = 'Failures'
    KpiWarnings      = 'Warnings'
    KpiChecksOk      = 'Checks OK'
    OpenDashboard    = 'Open full dashboard'
    FooterExecutedBy = 'executed by'
    FooterRun        = 'run'
    CountsSummary    = '{0} OK / {1} warn / {2} fail'
    FreePercent      = '{0}% free'

    # Consolidated email (all the farms of an environment in one message)
    FarmCountOne       = '{0} farm'
    FarmCountMany      = '{0} farms'
    FarmStatusAlert    = 'ALERT'
    FarmStatusWarn     = 'WARNING'
    FarmStatusOk       = 'HEALTHY'
    FarmStatusDown     = 'UNREACHABLE'
    FarmHealth         = '{0} healthy'
    FarmAttentionTitle = 'Needs attention'
    UnreachableTitle   = 'The farm could not be reached.'
    UnreachableText    = 'No check was run. See the SPSWeather Event Log (ID 3001).'
    FarmsOfTotalOne    = '{0} farm of {1}'
    FarmsOfTotalMany   = '{0} farms of {1}'
    IntroFarmsOne      = '{0} needs your attention on {1}. Full detail is in the dashboard of each farm.'
    IntroFarmsMany     = '{0} need your attention on {1}. Full detail is in the dashboard of each farm.'
    FooterFarmsQueried = 'farms queried: {0} of {1}'

    # Functional areas (dashboard cards and email groups)
    Area_FarmUpgrade        = 'Farm & Upgrade'
    Area_TrustFarm          = 'Trust Farm (REST)'
    Area_Search             = 'Search'
    Area_DistributedCache   = 'Distributed Cache'
    Area_TimerJobsSolutions = 'Timer Jobs & Solutions'
    Area_TimerJobs          = 'Timer Jobs'
    Area_Solutions          = 'Solutions'
    Area_UserProfiles       = 'User Profiles'
    Area_HealthAnalyzer     = 'Health Analyzer'
    Area_IIS                = 'IIS'
    Area_System             = 'System'
    Area_SQL                = 'SQL Server'

    # Section labels (one per report section)
    Section_SPHealthAnalyzer         = 'Health Analyzer'
    Section_SPUpgradeStatus          = 'Upgrade Status'
    Section_SPAPIHttpStatus          = 'Trust Farm (REST)'
    Section_SPSSitesHttpStatus       = 'Site HTTP Status'
    Section_SPFailedTimerJobs        = 'Failed Timer Jobs'
    Section_SPSolutionDeployment     = 'Solution Deployment'
    Section_SPSearchLastCrawlStatus  = 'Search - Last Crawl'
    Section_SPSearchCrawlLogs        = 'Search - Crawl Logs'
    Section_SPSSearchEntTopology     = 'Search - Topology'
    Section_AppFabricStatus          = 'Distributed Cache'
    Section_USPAudienceStatus        = 'User Profile Audiences'
    Section_IISApplicationPoolStatus = 'IIS - Application Pools'
    Section_IISWorkerProcessStatus   = 'IIS - Worker Processes'
    Section_IISWebSiteCertStatus     = 'IIS - SSL Certificates'
    Section_SYSEventViewerAppErrors  = 'System - Event Log Errors'
    Section_SYSDiskUsageStatus       = 'System - Disk Usage'
    Section_SYSLastRebootStatus      = 'System - Last Reboot'
    Section_SYSDOTNETVersion         = 'System - .NET Framework'
    Section_SPSContentDBStatus       = 'Content Databases'
    Section_SQLInstanceStatus        = 'SQL - Instances'
    Section_SQLDatabaseStatus        = 'SQL - Databases'
    Section_SQLDiskStatus            = 'SQL - Disk Volumes'
    Section_SQLAvailabilityStatus    = 'SQL - Availability Groups'
    Section_SQLAliasStatus           = 'SQL - Alias Mapping'
}
