# The columns that name the thing a row checks, section by section. Built once when the module is loaded:
# the function below runs for every item of every snapshot that the multi-farm page reads.
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
}

function Get-SPSWeatherItemIdentity {
    <#
        .SYNOPSIS
        Gives a stable identity, a name, a detail and a cause to a row of the report.

        .DESCRIPTION
        To say since when an item needs attention, the same item has to be recognised from one run to the next
        although its status and its figures change. The identity of a row is made of the columns that name
        the thing that is checked (the server, the database, the application pool, the volume...), never of
        the columns that describe its state. The columns of each section are listed here; a section that is not
        listed uses every column except the noise of remoting, IsInfo and the state columns.

        Returns:
          Id     - section and identity in lower case, stable between runs, used to follow an item;
          Name   - the identity as shown to a person (for example 'SQL1 / WSS_Content');
          Detail - the advisory or the state, on one line of 200 characters at most;
          Cause  - the detail with its numbers replaced by '#', so that 'last full backup 4.5 d ago' and
                   'last full backup 6 d ago' are the same cause and can be grouped.

        .PARAMETER Section
        The name of the report section the row comes from.

        .PARAMETER Row
        The row.

        .PARAMETER IdOnly
        Only the identity (Id) is needed: Name, Detail and Cause are left empty. Used for the older snapshots of a
        series, where only the recognition of an item matters, because the multi-farm page reads many snapshots.

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
    if ($null -ne $Row) {
        $columns = $script:SPSWeatherIdentityColumns[$Section]
        if ($null -ne $columns) {
            foreach ($column in $columns) {
                $value = _prop $Row $column
                if ($value) { [void]$parts.Add($value) }
            }
        }
        if ($parts.Count -eq 0) {
            foreach ($p in $Row.PSObject.Properties) {
                if ($noise -contains $p.Name -or $state -contains $p.Name) { continue }
                $value = _text $p.Value
                if ($value) { [void]$parts.Add($value) }
            }
        }
    }

    if ($IdOnly) {
        return [PSCustomObject]@{ Id = ($Section + '|' + (($parts -join '|').ToLowerInvariant())); Name = ''; Detail = ''; Cause = '' }
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
        Id     = ($Section + '|' + (($parts -join '|').ToLowerInvariant()))
        Name   = ($parts -join ' / ')
        Detail = $detail
        Cause  = $cause
    }
}
