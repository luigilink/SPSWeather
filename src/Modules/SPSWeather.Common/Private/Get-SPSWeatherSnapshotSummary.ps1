function Get-SPSWeatherSnapshotSummary {
    <#
        .SYNOPSIS
        Counts the OK, warning and failure checks of one JSON snapshot, and lists the ones that need attention.

        .DESCRIPTION
        The single place that turns a snapshot (the object read back from Results\<App>-<Env>-<Farm>.json or
        from the history folder) into counts, with the severity model of Get-SPSWeatherRowSeverity. Only an
        actual check (a row with IsInfo or severity) counts toward OK, so a run keeps the same OK total
        once archived as in the donut of the dashboard. Shared by Get-SPSWeatherHistory (the bars of the dashboard)
        and Get-SPSWeatherCockpitData (the multi-farm page), so that they can never disagree.

        Returns Ok, Warn and Fail, and Items: one object { Section; Row; Severity } for each warning or failure.
        A $null snapshot has no row and gives zeros.

        .PARAMETER Snapshot
        The snapshot object (sections as properties, rows as the values).

        .EXAMPLE
        $summary = Get-SPSWeatherSnapshotSummary -Snapshot (Get-Content -Path $file -Raw | ConvertFrom-Json)
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Snapshot
    )

    $ok = 0; $warn = 0; $fail = 0
    $items = New-Object -TypeName System.Collections.ArrayList
    foreach ($prop in $Snapshot.PSObject.Properties) {
        foreach ($row in @($prop.Value | Where-Object { $null -ne $_ })) {
            $severity = Get-SPSWeatherRowSeverity -Row $row
            switch ($severity) {
                'warn' { $warn++; [void]$items.Add([PSCustomObject]@{ Section = $prop.Name; Row = $row; Severity = 'warn' }) }
                'fail' { $fail++; [void]$items.Add([PSCustomObject]@{ Section = $prop.Name; Row = $row; Severity = 'fail' }) }
                default {
                    $n = $row.PSObject.Properties.Name
                    if (($n -contains 'IsInfo') -or ($n -contains 'severity')) { $ok++ }
                }
            }
        }
    }
    return [PSCustomObject]@{ Ok = $ok; Warn = $warn; Fail = $fail; Items = $items.ToArray() }
}
