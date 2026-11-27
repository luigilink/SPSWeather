# The columns that name the thing a row checks, by section (built once, the function runs for every item)
$script:SPSWeatherIdentityColumns = @{
    SPHealthAnalyzer         = @('title')
    SPUpgradeStatus          = @('server')
    SPAPIHttpStatus          = @('Title', 'Url')
    SPSSitesHttpStatus       = @('Url')
    SPTimerServiceStatus     = @('Server')
    SPFailedTimerJobs        = @('server', 'JobDefinitionTitle')
    SPSolutionDeployment     = @('SolutionName')
    SPSearchLastCrawlStatus  = @('SearchService', 'ContentSource')
    SPSearchCrawlLogs        = @('SearchService', 'ContentSource', 'ErrorID')
    SPSSearchEntTopology     = @('SearchService', 'ComponentHost', 'ComponentName')
    AppFabricStatus          = @('Server', 'Port')
    USPAudienceStatus        = @('Server')
    IISApplicationPoolStatus = @('Server', 'ApplicationPool')
    IISWorkerProcessStatus   = @('Server', 'ApplicationPool')
    IISWebSiteCertStatus     = @('Server', 'WebSiteName')
    SYSEventViewerAppErrors  = @('Server', 'ID', 'Name')
    SYSDiskUsageStatus       = @('Server', 'DriveLetter')
    SYSLastRebootStatus      = @('Server')
    SYSDOTNETVersion         = @('Server')
    SPSContentDBStatus       = @('SQLInstance', 'DatabaseName')
    SQLInstanceStatus        = @('SqlServer')
    SQLDatabaseStatus        = @('SqlServer', 'Name')
    SQLDiskStatus            = @('SqlServer', 'Volume')
    SQLAvailabilityStatus    = @('SqlServer', 'Type', 'Name')
    SQLAliasStatus           = @('Name')
    SPSLimitStatus           = @('Limit', 'Object')
}

function Get-SPSWeatherItemIdentity {
    <#
        .SYNOPSIS
        Gives a stable identity, a name, a detail and a cause to a row of the report.

        .DESCRIPTION
        Recognises an item from one run to the next by the columns that name the thing, never by the ones that
        describe its state. Returns Id, Name, Detail (200 characters at most, one line) and Cause (the detail
        with its numbers replaced by '#'). See the wiki page Cockpit-Data.

        .PARAMETER Section
        The name of the report section the row comes from.

        .PARAMETER Row
        The row.

        .PARAMETER IdOnly
        Only Id is needed: Name, Detail and Cause are left empty.

        .EXAMPLE
        Get-SPSWeatherItemIdentity -Section SQLDatabaseStatus -Row $row
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Section,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Row,

        [Parameter()]
        [switch]
        $IdOnly
    )

    $noise = @('PSComputerName', 'RunspaceId', 'PSShowComputerName', 'Farm', 'IsInfo')
    $state = @('Status', 'State', 'Recommendation', 'Note')

    function _text($value) {
        if ($null -eq $value) { return '' }
        return ([string]$value -replace '[\r\n\t]+', ' ').Trim()
    }
    function _prop($row, [string]$name) {
        $p = $row.PSObject.Properties[$name]
        if ($null -eq $p) { return '' }
        return _text $p.Value
    }

    $parts = New-Object -TypeName System.Collections.ArrayList
    $idParts = New-Object -TypeName System.Collections.ArrayList
    if ($null -ne $Row) {
        $columns = $script:SPSWeatherIdentityColumns[$Section]
        if ($null -ne $columns) {
            foreach ($column in $columns) {
                $value = _prop $Row $column
                if ($value) {
                    [void]$parts.Add($value)
                    # The role at the end of the name, 'AG / SQL1 (PRIMARY)', changes with a failover
                    if ($Section -eq 'SQLAvailabilityStatus' -and $column -eq 'Name' -and (_prop $Row 'Type') -eq 'AvailabilityGroup') {
                        $value = $value -replace '\s*\([^()]*\)$', ''
                    }
                    [void]$idParts.Add($value)
                }
            }
        }
        if ($parts.Count -eq 0) {
            foreach ($p in $Row.PSObject.Properties) {
                if ($noise -contains $p.Name -or $state -contains $p.Name) { continue }
                $value = _text $p.Value
                if ($value) { [void]$parts.Add($value); [void]$idParts.Add($value) }
            }
        }
    }

    $id = $Section + '|' + (($idParts -join '|').ToLowerInvariant())
    if ($IdOnly) {
        return [PSCustomObject]@{ Id = $id; Name = ''; Detail = ''; Cause = '' }
    }

    $detailParts = New-Object -TypeName System.Collections.ArrayList
    if ($null -ne $Row) {
        if ($null -ne $Row.PSObject.Properties['severity']) {
            foreach ($column in @('severity', 'category')) {
                $value = _prop $Row $column
                if ($value) { [void]$detailParts.Add($value) }
            }
        }
        else {
            foreach ($column in @('Recommendation', 'Note', 'Message')) {
                $value = _prop $Row $column
                if ($value) { [void]$detailParts.Add($value) }
            }
            if ($detailParts.Count -eq 0) {
                foreach ($column in @('Status', 'UpgradeStatus', 'CacheStatus', 'SPInstanceStatus', 'CrawlState', 'DeploymentState', 'State', 'Detail', 'Severity')) {
                    $value = _prop $Row $column
                    if ($value) { [void]$detailParts.Add($value); break }
                }
            }
        }
    }
    $detail = ($detailParts -join ' · ')
    if ($detail.Length -gt 200) { $detail = $detail.Substring(0, 200) }

    $cause = ($detail -replace '\d+(?:[.,]\d+)?', '#' -replace '\s+', ' ').Trim()
    if ($cause.Length -gt 80) { $cause = $cause.Substring(0, 80) }

    return [PSCustomObject]@{
        Id     = $id
        Name   = ($parts -join ' / ')
        Detail = $detail
        Cause  = $cause
    }
}
