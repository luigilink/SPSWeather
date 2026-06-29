function Compare-SPSWeatherSnapshots {
    <#
        .SYNOPSIS
        Compares two SPSWeather JSON snapshots and returns Ok/Alert deltas.

        .DESCRIPTION
        Compare-SPSWeatherSnapshots loads two JSON snapshots produced by SPSWeather (or
        accepts the corresponding PSCustomObject directly via -CurrentObject /
        -PreviousObject) and returns the OK and Alert counts for each, plus the delta.
        It is intentionally simple - the SPSWeather report can render a one-line trend
        line based on these numbers.

        Rows are counted from any IsInfo-bearing section: IsInfo=$true increments Ok,
        IsInfo=$false increments Alert. Sections without IsInfo (info-only tables like
        SYSDOTNETVersion) are ignored, matching the entry-script alert convention.

        .PARAMETER CurrentFile
        Path to the most recent JSON snapshot.

        .PARAMETER PreviousFile
        Path to the prior JSON snapshot. Omit to auto-pick the latest *.json under
        -HistoryFolder.

        .PARAMETER CurrentObject
        In-memory current snapshot (alternative to -CurrentFile).

        .PARAMETER PreviousObject
        In-memory previous snapshot (alternative to -PreviousFile).

        .PARAMETER HistoryFolder
        Folder to pick the most recent prior snapshot from when -PreviousFile is omitted.

        .EXAMPLE
        Compare-SPSWeatherSnapshots -CurrentObject $jsonObject -HistoryFolder $hist
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(ParameterSetName = 'File')]
        [System.String]
        $CurrentFile,

        [Parameter(ParameterSetName = 'File')]
        [System.String]
        $PreviousFile,

        [Parameter(ParameterSetName = 'Object')]
        [PSCustomObject]
        $CurrentObject,

        [Parameter(ParameterSetName = 'Object')]
        [PSCustomObject]
        $PreviousObject,

        [Parameter()]
        [System.String]
        $HistoryFolder
    )

    function _load([string]$path) {
        if ([string]::IsNullOrEmpty($path)) { return $null }
        if (-not (Test-Path -Path $path)) { return $null }
        return Get-Content -Path $path -Raw | ConvertFrom-Json
    }

    function _count($obj) {
        $ok = 0; $alert = 0
        if ($null -eq $obj) { return [PSCustomObject]@{ Ok = 0; Alert = 0 } }
        foreach ($prop in $obj.PSObject.Properties) {
            foreach ($row in @($prop.Value)) {
                if ($null -ne $row -and ($row.PSObject.Properties.Name -contains 'IsInfo')) {
                    if ($row.IsInfo -eq $false) { $alert++ } else { $ok++ }
                }
            }
        }
        return [PSCustomObject]@{ Ok = $ok; Alert = $alert }
    }

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $current = _load $CurrentFile
        if ([string]::IsNullOrEmpty($PreviousFile) -and -not [string]::IsNullOrEmpty($HistoryFolder) -and (Test-Path -Path $HistoryFolder)) {
            $latest = Get-ChildItem -Path $HistoryFolder -Filter '*.json' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($null -ne $latest) { $PreviousFile = $latest.FullName }
        }
        $previous = _load $PreviousFile
    }
    else {
        $current = $CurrentObject
        $previous = $PreviousObject
    }

    $cur = _count $current
    $prev = _count $previous

    return [PSCustomObject]@{
        Current      = $cur
        Previous     = $prev
        DeltaOk      = ($cur.Ok - $prev.Ok)
        DeltaAlert   = ($cur.Alert - $prev.Alert)
        HasPrevious  = ($null -ne $previous)
    }
}
