function Get-SPSWeatherHistory {
    <#
        .SYNOPSIS
        Builds the history series (past runs) consumed by Export-SPSWeatherReport -History.

        .DESCRIPTION
        Scans a farm history folder for archived *.json snapshots, classifies each run's
        rows into Ok/Warn/Fail with the same severity convention as the report renderer,
        and returns an ordered array (oldest first, capped at -Max) of objects shaped
        { Date; Ok; Warn; Fail }. The current run is appended by the renderer itself, so
        this returns PAST runs only.

        .PARAMETER HistoryFolder
        Folder holding the per-farm *.json snapshots (Backup-SPSWeatherJsonFile output).

        .PARAMETER Max
        Maximum number of most-recent runs to return. Defaults to 30.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $HistoryFolder,

        [Parameter()]
        [System.Int32]
        $Max = 30
    )

    if (-not (Test-Path -Path $HistoryFolder)) { return @() }

    $files = Get-ChildItem -Path $HistoryFolder -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime
    if ($null -eq $files -or $files.Count -eq 0) { return @() }
    if ($files.Count -gt $Max) { $files = $files[($files.Count - $Max)..($files.Count - 1)] }

    $series = foreach ($file in $files) {
        try { $obj = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json }
        catch { continue }
        $ok = 0; $warn = 0; $fail = 0
        foreach ($prop in $obj.PSObject.Properties) {
            foreach ($row in @($prop.Value | Where-Object { $null -ne $_ })) {
                switch (Get-SPSWeatherRowSeverity -Row $row) {
                    'warn' { $warn++ }
                    'fail' { $fail++ }
                    default {
                        # Only actual checks (IsInfo/severity) count toward OK, matching the
                        # current-run donut so a run keeps the same OK total once archived.
                        $n = $row.PSObject.Properties.Name
                        if (($n -contains 'IsInfo') -or ($n -contains 'severity')) { $ok++ }
                    }
                }
            }
        }
        [PSCustomObject]@{
            Date = $file.LastWriteTime.ToString('MM-dd')
            Ok   = $ok
            Warn = $warn
            Fail = $fail
        }
    }
    return @($series)
}
