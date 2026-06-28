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

    # SMTP settings (used when SPSWeather.ps1 runs with -EnableSmtp).
    SMTPToAddress     = @('admin-farm@contoso.com', 'admin-setup@contoso.com')
    SMTPFromAddress   = 'noreply@contoso.com'
    SMTPServer        = 'smtp.contoso.com'

    # CredentialKey : name of the entry in Config\secrets.psd1 that holds the
    # service account used to reach the farms (CredSSP remoting). Populate it by
    # running -Install as that account, or generate it manually with
    # ConvertFrom-SecureString. See Config\secrets.example.psd1.
    CredentialKey     = 'PROD-ADM'

    # ExclusionRules : checks to skip. Authorized values: None, APIHttpStatus,
    # SPSiteHttpStatus, EvtViewerStatus, IISW3WPStatus, HealthStatus, WSPStatus,
    # FailedTimerJob, SQLInstanceStatus, SQLDatabaseStatus, SQLDiskStatus,
    # SQLAvailabilityStatus, SQLAliasStatus.
    ExclusionRules    = @(
        'SPSiteHttpStatus'
        'EvtViewerStatus'
        'IISW3WPStatus'
        'WSPStatus'
    )

    # SQL thresholds (optional; defaults shown). A SQL volume below
    # SQLDiskFreeThresholdPercent free, or a database whose last full backup is
    # older than SQLBackupMaxAgeDays, raises an alert.
    SQLDiskFreeThresholdPercent = 15
    SQLBackupMaxAgeDays         = 3

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
