function ConvertTo-SPSWeatherReport {
    <#
        .SYNOPSIS
        Assembles the SPSWeather report object and computes the overall alert flag.

        .DESCRIPTION
        ConvertTo-SPSWeatherReport takes an ordered map of section name -> collected
        rows and builds the PSCustomObject consumed by Join-HtmlBodyFromPSo and the
        JSON snapshot. It also returns whether any section reported a
        non-informational row (an item whose IsInfo flag is $false), which the entry
        script uses to raise the [ALERT] state.

        A section is added whenever its value is not $null (empty collections are kept,
        matching the historical behavior so the JSON shape is stable). Sections whose
        rows have no IsInfo property never raise an alert, so info-only sections
        (SYSLastRebootStatus, SYSDOTNETVersion, SPWeatherListInfo) are handled by the
        same uniform rule without special-casing.

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
    $isAlert = $false

    foreach ($name in $Section.Keys) {
        $data = $Section[$name]
        if ($null -ne $data) {
            if (@($data).IsInfo -contains $false) {
                $isAlert = $true
            }
            $report | Add-Member -MemberType NoteProperty -Name $name -Value $data
        }
    }

    return [PSCustomObject]@{
        Report  = $report
        IsAlert = $isAlert
    }
}
