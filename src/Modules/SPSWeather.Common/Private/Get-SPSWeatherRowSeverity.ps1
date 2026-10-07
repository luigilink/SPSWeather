function Get-SPSWeatherRowSeverity {
    <#
        .SYNOPSIS
        Classifies a single report row as 'ok', 'warn' or 'fail'.

        .DESCRIPTION
        The single severity model shared by the dashboard renderer, the alert email,
        the history series and the per-farm outcome, so they never disagree. Rules,
        in order:
          1. a 'severity' string (Health Analyzer rows, which carry no IsInfo):
             Error/Critical -> fail, Warning -> warn;
          2. an 'IsInfo' flag: $false -> fail; $true -> 'warn' when the row carries a
             non-empty advisory (Recommendation/Note), otherwise 'ok';
          3. no IsInfo and no severity: an explicit failure status
             (Unreachable/Failed/Stopped/closed/KO) -> fail, otherwise 'ok'.

        .PARAMETER Row
        The report row (PSCustomObject) to classify.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter()]
        $Row
    )

    if ($null -eq $Row) { return 'ok' }
    $names = $Row.PSObject.Properties.Name

    # 1. Health Analyzer severity string (no IsInfo on those rows).
    if ($names -contains 'severity') {
        $s = "$($Row.severity)"
        if ($s -match 'Error|Critical|^1\b|1 -') { return 'fail' }
        if ($s -match 'Warning|^2\b|2 -') { return 'warn' }
    }

    # 2. IsInfo-bearing rows.
    if ($names -contains 'IsInfo') {
        if (-not $Row.IsInfo) { return 'fail' }
        foreach ($advisory in @('Recommendation', 'Note')) {
            if ($names -contains $advisory -and -not [string]::IsNullOrWhiteSpace("$($Row.$advisory)")) {
                return 'warn'
            }
        }
        return 'ok'
    }

    # 3. No IsInfo/severity: catch an explicit failure status (e.g. an Unreachable
    #    row from a collector that could not reach the server).
    foreach ($field in @('Status', 'State', 'CrawlState', 'CacheStatus', 'SPInstanceStatus')) {
        if ($names -contains $field -and "$($Row.$field)" -match 'Unreachable|Failed|Stopped|\bclosed\b|^KO$|Critical|Error') {
            return 'fail'
        }
    }
    foreach ($name in $names) {
        if ("$($Row.$name)" -eq 'Unreachable') { return 'fail' }
    }
    return 'ok'
}
