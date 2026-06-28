@{
    # PSScriptAnalyzer settings for SPSWeather.
    # Run locally with:
    #   Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
    Severity = @('Error', 'Warning')

    # PSUseSingularNouns is intentionally disabled. A few functions deliberately use a
    # plural noun because they return a collection of records, mirroring built-in cmdlets
    # such as Get-EventLog:
    #   - Get-SPSSearchEntCrawlLogs (returns the crawl log entries)
    #   - Get-SYSEvtAppErrors       (returns the application error events)
    ExcludeRules = @(
        'PSUseSingularNouns'
    )
}
