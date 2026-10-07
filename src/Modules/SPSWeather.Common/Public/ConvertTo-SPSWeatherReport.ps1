function ConvertTo-SPSWeatherReport {
    <#
        .SYNOPSIS
        Assembles the SPSWeather report object and computes the overall alert flag.

        .DESCRIPTION
        ConvertTo-SPSWeatherReport takes an ordered map of section name -> collected
        rows and builds the PSCustomObject consumed by Export-SPSWeatherReport,
        ConvertTo-SPSWeatherEmailBody and the JSON snapshot. It also classifies every
        row through the shared severity model (Get-SPSWeatherRowSeverity) and returns
        Ok/Warn/Fail counts plus IsAlert (true when any row is a warning or a failure),
        which the entry script uses to set the per-farm outcome.

        A section is added whenever its value is not $null (empty collections are kept,
        matching the historical behavior so the JSON shape is stable). Only rows that
        are actual checks (carrying IsInfo or a severity) count toward Ok, so pure
        info-only rows (reboot time, .NET version) do not inflate the healthy total.

        .PARAMETER Section
        Ordered dictionary mapping each report section name to its collection of rows.
        Use an [ordered] hashtable to control the property order of the result.

        .EXAMPLE
        $result = ConvertTo-SPSWeatherReport -Section ([ordered]@{
            SYSDiskUsageStatus = $tbSYSDiskUsageStatus
            SPSContentDBStatus = $tbSPSContentDBStatus
        })
        $jsonObject = $result.Report
        if ($result.IsAlert) { $mailAlert = 'ALERT' }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $Section
    )

    $report = [PSCustomObject]@{}
    $okCount = 0
    $warnCount = 0
    $failCount = 0

    foreach ($name in $Section.Keys) {
        $data = $Section[$name]
        if ($null -ne $data) {
            foreach ($row in @($data)) {
                $isCheck = ($row.PSObject.Properties.Name -contains 'IsInfo') -or
                    ($row.PSObject.Properties.Name -contains 'severity')
                switch (Get-SPSWeatherRowSeverity -Row $row) {
                    'fail' { $failCount++ }
                    'warn' { $warnCount++ }
                    default { if ($isCheck) { $okCount++ } }
                }
            }
            $report | Add-Member -MemberType NoteProperty -Name $name -Value $data
        }
    }

    return [PSCustomObject]@{
        Report  = $report
        IsAlert = ($failCount -gt 0 -or $warnCount -gt 0)
        Summary = [PSCustomObject]@{
            Ok    = $okCount
            Warn  = $warnCount
            Fail  = $failCount
            Alert = ($warnCount + $failCount)
        }
    }
}
