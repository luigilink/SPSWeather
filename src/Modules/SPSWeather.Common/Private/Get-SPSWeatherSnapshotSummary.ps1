function Get-SPSWeatherSnapshotSummary {
    <#
        .SYNOPSIS
        Counts the OK, warning and failure checks of one JSON snapshot.

        .DESCRIPTION
        The one way of counting a snapshot, shared by the bars of the dashboard and the multi-farm page. Only an
        actual check (a row with IsInfo or severity) counts toward OK. Returns Ok, Warn, Fail and Items, one
        { Section; Row; Severity } for each warning or failure.

        .PARAMETER Snapshot
        The snapshot object (sections as properties, rows as the values).

        .EXAMPLE
        Get-SPSWeatherSnapshotSummary -Snapshot (Get-Content -Path $file -Raw | ConvertFrom-Json)
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
