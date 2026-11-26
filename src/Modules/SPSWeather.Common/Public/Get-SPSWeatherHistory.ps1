function Get-SPSWeatherHistory {
    <#
        .SYNOPSIS
        Builds the history series (past runs) consumed by Export-SPSWeatherReport -History.

        .DESCRIPTION
        Scans a farm history folder for archived *.json snapshots, classifies each run's
        rows into Ok/Warn/Fail with the same severity convention as the report renderer,
        and returns an ordered array (oldest first, capped at -Max) of objects shaped
        { Date; Ok; Warn; Fail; When }. Date is a 'MM-dd' text (the original contract); When is
        the same moment as a [datetime], so the renderer can write it in the order of the
        display language. The current run is appended by the renderer itself, so this returns
        PAST runs only.

        .PARAMETER HistoryFolder
        Folder holding the per-farm *.json snapshots (Backup-SPSWeatherJsonFile output).

        .PARAMETER NamePrefix
        Only the snapshots whose file name starts with this text are read (not case sensitive). The history
        folder of a farm is shared by the environments of an installation that name a farm the same, and the
        file name is what tells them apart: pass '<App>-<Env>-<Farm>-' to read the runs of one environment.
        Without it every *.json of the folder is read, as before.

        .PARAMETER Max
        Maximum number of most-recent runs to return, among the snapshots that were read. Defaults to 30.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $HistoryFolder,

        [Parameter()]
        [System.String]
        $NamePrefix,

        [Parameter()]
        [System.Int32]
        $Max = 30
    )

    if (-not (Test-Path -Path $HistoryFolder)) { return @() }

    $files = Get-ChildItem -Path $HistoryFolder -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { [string]::IsNullOrEmpty($NamePrefix) -or $_.Name.StartsWith($NamePrefix, [System.StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object LastWriteTime
    if ($null -eq $files -or $files.Count -eq 0) { return @() }
    if ($files.Count -gt $Max) { $files = $files[($files.Count - $Max)..($files.Count - 1)] }

    $series = foreach ($file in $files) {
        try { $obj = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json }
        catch { continue }
        # The same counting as the multi-farm page: only actual checks count toward OK, matching the
        # current-run donut so a run keeps the same OK total once archived.
        $summary = Get-SPSWeatherSnapshotSummary -Snapshot $obj
        [PSCustomObject]@{
            Date = $file.LastWriteTime.ToString('MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            When = $file.LastWriteTime
            Ok   = $summary.Ok
            Warn = $summary.Warn
            Fail = $summary.Fail
        }
    }
    return @($series)
}
