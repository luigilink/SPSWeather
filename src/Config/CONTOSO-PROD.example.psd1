@{
    # =================================================================================
    # SPSWeather - environment configuration (example)
    #
    # Copy this file to a real config (e.g. contoso-PROD.psd1) and edit the values for
    # your environment, then run:  .\SPSWeather.ps1 -ConfigFile 'contoso-PROD.psd1'
    #
    # Real config files (Config\*.psd1) are gitignored so internal infrastructure
    # details (server names, SMTP, domains) never land in version control. Only
    # *.example.psd1 templates are committed.
    # =================================================================================

    # ConfigurationName : free-form environment identifier (e.g. PROD, PPRD, DEV).
    ConfigurationName = 'PROD'

    # ApplicationName : free-form application code, used in result/log file names.
    ApplicationName   = 'contoso'

    # Domain : DNS suffix appended to each farm server short name below.
    Domain            = 'contoso.com'

    # Email behavior.
    #   SMTPEnabled : $true sends the alert email (one per farm), $false does not. When the key
    #                 is absent, the deprecated -EnableSmtp switch of SPSWeather.ps1 still
    #                 decides (removed in 4.0.0); when present, this key takes precedence.
    #   SMTPPreview : $true also writes the email body to Results\<App>-<Env>-<Farm>-mail.html
    #                 (Results\<App>-<Env>-mail.html with EmailMode = 'Consolidated'), overwritten
    #                 at each run, so it can be reviewed without an SMTP relay.
    #                 Independent from SMTPEnabled. Default: $false.
    #   EmailMode   : 'PerFarm' (default) sends one short email per farm; 'Consolidated' sends ONE
    #                 email for all the farms, with a card per farm (status, counts, main areas
    #                 and a link to its dashboard). A farm that cannot be reached gets its own card.
    # The three settings below are required whenever emails are sent (SMTPEnabled = $true, or
    # the deprecated -EnableSmtp switch); not needed when sending is off.
    SMTPEnabled       = $true
    SMTPPreview       = $false
    EmailMode         = 'PerFarm'
    SMTPToAddress     = @('admin-farm@contoso.com', 'admin-setup@contoso.com')
    SMTPFromAddress   = 'noreply@contoso.com'
    SMTPServer        = 'smtp.contoso.com'

    # CredentialKey : name of the entry in Config\secrets.psd1 that holds the
    # service account used to reach the farms (CredSSP remoting). Populate it by
    # running -Action Install as that account, or generate it manually with
    # ConvertFrom-SecureString. See Config\secrets.example.psd1.
    CredentialKey     = 'PROD-ADM'

    # ExclusionRules : checks to skip. Authorized values: None, APIHttpStatus,
    # SPSiteHttpStatus, EvtViewerStatus, IISW3WPStatus, HealthStatus, WSPStatus,
    # FailedTimerJob, TimerServiceStatus, SQLInstanceStatus, SQLDatabaseStatus,
    # SQLDiskStatus, SQLAvailabilityStatus, SQLAliasStatus, LimitStatus.
    ExclusionRules    = @(
        'SPSiteHttpStatus'
        'EvtViewerStatus'
        'IISW3WPStatus'
        'WSPStatus'
    )

    # SQL thresholds (optional; defaults shown). A SQL volume below
    # SQLDiskFreeThresholdPercent free, or a database whose last full backup is
    # older than SQLBackupMaxAgeDays, raises an alert. The key must be at the top level
    # of this file and hold a whole number of 0 or more: anything else is reported and
    # the default is used. The footer of the dashboard shows the configuration file and
    # these two values, with "(default)" when the file does not set them.
    SQLDiskFreeThresholdPercent = 15
    SQLBackupMaxAgeDays         = 3

    # JsonHistoryRetentionDays: how many days of JSON snapshots are kept under
    # Results\history for the report trend (Backup-SPSWeatherJsonFile). 0 disables
    # pruning. Default: 30.
    JsonHistoryRetentionDays    = 30

    # EmailMaxItemsPerArea: maximum number of items listed per area in the short alert
    # email; the rest is summarized as "+ N more" (the dashboard holds the full list).
    # Counters are never capped. 0 lists everything. Default: 10.
    EmailMaxItemsPerArea        = 10

    # Language : display language of the dashboard and of the alert email. A culture name
    # (en-US or fr-FR), or 'auto' for the UI culture of the account that runs the script. Only the
    # labels are translated; the values of the checks stay as collected. An unknown value falls
    # back to en-US with a warning. Default: en-US.
    Language                    = 'en-US'

    # LogRetentionDays: how many days of *.log transcript files are kept under
    # Logs\ by Clear-SPSLog. 0 disables pruning. Default: 180.
    LogRetentionDays            = 180

    # Limits (optional): the supported limits of SharePoint (content database size, site collections
    # per database, content databases and web applications per farm, managed paths, Distributed Cache
    # memory, application pools per server, search topology). A farm below every threshold adds
    # nothing to the report. Every key is optional and the values below are the defaults.
    #   Warning : the value from which a warning is raised.
    #   Failure : the limit; a value above it is a failure.
    # A number of 0 or more, or $null for none. A value that cannot be used is reported and the
    # default is used. ContentDatabaseSize is in GB of DATA (the log is not counted).
    # SearchTopology has fixed limits: only Disabled and Exempt apply to it.
    # See the wiki page Limits (source: Microsoft software boundaries and limits).
    #   Disabled   : checks to turn off, e.g. @('ManagedPaths'); LimitStatus in ExclusionRules
    #                turns them all off.
    #   Exceptions : a different threshold, or Exempt = $true, for ONE object (a database, a
    #                server or a web application; the name is matched without regard to case);
    #                Reason is shown with the alert. Example, a document archive that is
    #                supported up to 4 TB:
    #                @{ Limit = 'ContentDatabaseSize'; Object = 'WSS_Content_Archive'; Warning = 3072; Failure = 4096; Reason = 'document archive' }
    Limits                      = @{
        ContentDatabaseSize       = @{ Warning = 150; Failure = 200 }
        SiteCountPerDatabase      = @{ Warning = 5000; Failure = 10000 }
        ContentDatabasesPerFarm   = @{ Warning = 375; Failure = 500 }
        WebApplicationsPerFarm    = @{ Warning = 15; Failure = 20 }
        ManagedPaths              = @{ Warning = 21 }
        DistributedCacheSize      = @{ Failure = 16 }
        ApplicationPoolsPerServer = @{ Warning = 11 }
        Disabled                  = @()
        Exceptions                = @()
    }

    # Dashboard : where the per-farm dashboard HTML is written and how the email CTA
    # links to it. Provision the hosting target once with New-SPSDashboardSite.ps1.
    #   OutputPath : folder (local or UNC share) that receives
    #                <App>-<Env>-<Farm>-dashboard.html. Empty = Results\ (local only).
    #   Url        : public base URL serving that folder over IIS. The email button
    #                points to <Url>/<App>-<Env>-<Farm>-dashboard.html. Empty = no button.
    #   Cockpit    : $true also writes <App>-<Env>-cockpit.html, the page that shows every
    #                farm of the environment (health, trend, causes, run journal, settings),
    #                in OutputPath (Results\ when empty). Written at the end of the run, after
    #                the emails; a failure to write it never fails the run. With
    #                EmailMode = 'Consolidated' and a Url, the email gets a button to it.
    #                Optional, $false by default: nothing changes unless it is set.
    Dashboard                   = @{
        OutputPath = ''
        Url        = ''
        Cockpit    = $false
    }

    # Farms : one entry per trusted farm to check. Server is the short name; the
    # Domain above is appended to build the FQDN targeted for remoting. SqlServers
    # is OPTIONAL: the SQL client alias(es) (cliconfg) or server name(s) this farm
    # uses. SPSWeather always auto-discovers the SQL servers from Get-SPDatabase;
    # declaring them here lets it validate 'declared vs discovered' and resolve the
    # cliconfg alias to the real server/instance/port.
    Farms = @(
        @{ Name = 'SEARCH'; Server = 'srvcontososearch'; SqlServers = @('SPSQLSEARCH') }
        @{ Name = 'SERVICES'; Server = 'srvcontososervices'; SqlServers = @('SPSQLSERVICES') }
        @{ Name = 'CONTENT'; Server = 'srvcontosocontent'; SqlServers = @('SPSQLCONTENT') }
    )
}
