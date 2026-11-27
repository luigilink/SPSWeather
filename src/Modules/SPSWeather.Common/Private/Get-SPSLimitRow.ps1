function Get-SPSLimitRow {
    <#
        .SYNOPSIS
        Judges the facts of a farm against the supported limits of SharePoint and returns one row for each object at or above a threshold.

        .DESCRIPTION
        Pure: it reads nothing and changes nothing, so every check is tested without a farm. The facts come from Get-SPSLimitFact and from
        the sections that a run has already collected (SQL, IIS, Distributed Cache, search topology). A farm below every threshold gives
        no row.

        Warning: from the warning threshold. Failure: above the failure threshold, which is the limit. A row follows the severity model
        of the report (Get-SPSWeatherRowSeverity): IsInfo $false is a failure, IsInfo $true with a Recommendation is a warning.

        The size of a content database is the used size of its data when it was read (UsedSize), else the allocated size of its data files
        (an upper bound), else the size that SharePoint reports. The log is never counted: the limit is about the content. The check says
        which of the three it used.

        .PARAMETER Farm
        Farm label written in the Farm column.

        .PARAMETER Setting
        The result of Get-SPSWeatherLimitSetting.

        .PARAMETER Fact
        The result of Get-SPSLimitFact.

        .PARAMETER SqlDatabase
        The rows of the SQLDatabaseStatus section (DataSizeMB is the allocated size of the data files).

        .PARAMETER ContentDatabaseStatus
        The rows of the SPSContentDBStatus section (DiskSize, in GB, includes the log): only used when the SQL rows are not there.

        .PARAMETER UsedSize
        The result of Get-SPSContentDatabaseUsedSize.

        .PARAMETER DistributedCache
        The rows of the AppFabricStatus section (Size is in MB).

        .PARAMETER ApplicationPool
        The rows of the IISApplicationPoolStatus section.

        .PARAMETER SearchTopology
        The rows of the SPSSearchEntTopology section.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Farm,

        [Parameter(Mandatory = $true)]
        $Setting,

        [Parameter()]
        [AllowNull()]
        $Fact,

        [Parameter()]
        [AllowNull()]
        [System.Object[]]
        $SqlDatabase,

        [Parameter()]
        [AllowNull()]
        [System.Object[]]
        $ContentDatabaseStatus,

        [Parameter()]
        [AllowNull()]
        [System.Object[]]
        $UsedSize,

        [Parameter()]
        [AllowNull()]
        [System.Object[]]
        $DistributedCache,

        [Parameter()]
        [AllowNull()]
        [System.Object[]]
        $ApplicationPool,

        [Parameter()]
        [AllowNull()]
        [System.Object[]]
        $SearchTopology
    )

    $rows = New-Object -TypeName System.Collections.ArrayList

    function ConvertTo-Number {
        param($Raw)
        $number = 0.0
        if ($null -eq $Raw -or $Raw -is [System.Boolean]) { return $null }
        if ([double]::TryParse([string]$Raw, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $number }
        return $null
    }
    function Format-Number {
        param($Value)
        if ($null -eq $Value) { return '' }
        return ([math]::Round([double]$Value, 2)).ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    function Add-LimitRow {
        param([string]$Limit, [string]$Object, $Value, [string]$Unit, $Threshold, [string]$Subject, [string]$Basis = '', [string]$Note = '')
        $level = $null
        if ($null -ne $Threshold.Failure -and $Value -gt $Threshold.Failure) { $level = 'fail' }
        elseif ($null -ne $Threshold.Warning -and $Value -ge $Threshold.Warning) { $level = 'warn' }
        if ($null -eq $level) { return }
        $unitText = if ($Unit) { " $Unit" } else { '' }
        $text = "${Subject}: $(Format-Number $Value)$unitText$Basis."
        if ($null -ne $Threshold.Warning) { $text += " Warning from $(Format-Number $Threshold.Warning)$unitText" }
        if ($null -ne $Threshold.Failure) { $text += $(if ($null -ne $Threshold.Warning) { ', failure above ' } else { ' Failure above ' }) + "$(Format-Number $Threshold.Failure)$unitText" }
        $text += '.'
        if (-not [string]::IsNullOrWhiteSpace($Threshold.Reason)) { $text += " Exception: $($Threshold.Reason)" }
        [void]$rows.Add([PSCustomObject]@{
                Farm           = $Farm
                Limit          = $Limit
                Object         = $Object
                Value          = [math]::Round([double]$Value, 2)
                Unit           = $Unit
                Warning        = $Threshold.Warning
                Failure        = $Threshold.Failure
                Status         = $(if ($level -eq 'fail') { 'Failure' } else { 'Warning' })
                Recommendation = $text
                Note           = $Note
                IsInfo         = ($level -ne 'fail')
            })
    }
    # The thresholds of the object, with the exceptions of the configuration applied
    $limitSetting = $Setting
    $thresholdOf = {
        param([string]$Limit, [string]$Object)
        Get-SPSLimitThreshold -Setting $limitSetting -Limit $Limit -Object $Object
    }

    # --- Facts of the farm: content databases, web applications, managed paths ---
    if ($null -ne $Fact -and [string]::IsNullOrEmpty("$($Fact.Error)")) {
        $databases = @($Fact.ContentDatabases)

        # Content database size: used data when read, else allocated data files, else what SharePoint reports (log included)
        $sqlRows = @($SqlDatabase | Where-Object -FilterScript { $null -ne $_ })
        $statusRows = @($ContentDatabaseStatus | Where-Object -FilterScript { $null -ne $_ -and "$($_.Type)" -eq 'Content Database' })
        $usedRows = @($UsedSize | Where-Object -FilterScript { $null -ne $_ })
        foreach ($database in $databases) {
            $name = "$($database.Name)"
            $threshold = & $thresholdOf 'ContentDatabaseSize' $name
            if ($threshold.Enabled) {
                $value = $null; $basis = ''
                $used = @($usedRows | Where-Object -FilterScript { "$($_.Name)" -eq $name })[0]
                $usedMB = if ($null -ne $used) { ConvertTo-Number $used.UsedDataMB } else { $null }
                $sql = @($sqlRows | Where-Object -FilterScript { "$($_.Name)" -eq $name -and ([string]::IsNullOrEmpty("$($database.SqlServer)") -or "$($_.SqlServer)" -eq "$($database.SqlServer)") })[0]
                if ($null -eq $sql) { $sql = @($sqlRows | Where-Object -FilterScript { "$($_.Name)" -eq $name })[0] }
                $allocatedMB = if ($null -ne $sql) { ConvertTo-Number $sql.DataSizeMB } else { $null }
                if ($null -ne $usedMB) { $value = $usedMB / 1024; $basis = ' (used)' }
                elseif ($null -ne $allocatedMB) {
                    $value = $allocatedMB / 1024
                    $basis = if ($null -ne $used -and -not [string]::IsNullOrEmpty("$($used.Error)")) { " (allocated; the used size could not be read: $("$($used.Error)".Trim()))" } else { ' (allocated)' }
                }
                else {
                    $status = @($statusRows | Where-Object -FilterScript { "$($_.DatabaseName)" -eq $name })[0]
                    $reported = if ($null -ne $status) { ConvertTo-Number $status.DiskSize } else { $null }
                    if ($null -ne $reported) { $value = $reported; $basis = ' (as reported by SharePoint, log included)' }
                }
                if ($null -ne $value) {
                    $note = if ($database.Rbs -eq $true) { 'Remote BLOB Storage is enabled: the limit includes the external BLOBs, which are not counted here.' } else { '' }
                    Add-LimitRow -Limit 'ContentDatabaseSize' -Object $name -Value $value -Unit 'GB' -Threshold $threshold -Subject 'Data size' -Basis $basis -Note $note
                }
            }

            $threshold = & $thresholdOf 'SiteCountPerDatabase' $name
            if ($threshold.Enabled -and $null -ne (ConvertTo-Number $database.SiteCount)) {
                Add-LimitRow -Limit 'SiteCountPerDatabase' -Object $name -Value (ConvertTo-Number $database.SiteCount) -Unit '' -Threshold $threshold -Subject 'Site collections'
            }
        }

        $threshold = & $thresholdOf 'ContentDatabasesPerFarm' $Farm
        if ($threshold.Enabled) { Add-LimitRow -Limit 'ContentDatabasesPerFarm' -Object $Farm -Value $databases.Count -Unit '' -Threshold $threshold -Subject 'Content databases' }

        $webApplicationCount = ConvertTo-Number $Fact.WebApplicationCount
        $threshold = & $thresholdOf 'WebApplicationsPerFarm' $Farm
        if ($threshold.Enabled -and $null -ne $webApplicationCount) { Add-LimitRow -Limit 'WebApplicationsPerFarm' -Object $Farm -Value $webApplicationCount -Unit '' -Threshold $threshold -Subject 'Web applications' }

        foreach ($webApplication in @($Fact.WebApplications)) {
            $pathCount = ConvertTo-Number $webApplication.PathCount
            $threshold = & $thresholdOf 'ManagedPaths' "$($webApplication.Name)"
            if ($threshold.Enabled -and $null -ne $pathCount) { Add-LimitRow -Limit 'ManagedPaths' -Object "$($webApplication.Name)" -Value $pathCount -Unit '' -Threshold $threshold -Subject 'Managed paths of the web application' }
        }
        $hostNamed = ConvertTo-Number $Fact.HostNamedManagedPathCount
        $threshold = & $thresholdOf 'ManagedPaths' 'host-named site collections'
        if ($threshold.Enabled -and $null -ne $hostNamed) { Add-LimitRow -Limit 'ManagedPaths' -Object 'host-named site collections' -Value $hostNamed -Unit '' -Threshold $threshold -Subject 'Managed paths for host-named site collections' }
    }

    # --- Distributed Cache: the memory given to the cache of a host (MB in the section) ---
    foreach ($row in @($DistributedCache | Where-Object -FilterScript { $null -ne $_ })) {
        $sizeMB = ConvertTo-Number $row.Size
        if ($null -eq $sizeMB) { continue }
        $threshold = & $thresholdOf 'DistributedCacheSize' "$($row.Server)"
        if ($threshold.Enabled) { Add-LimitRow -Limit 'DistributedCacheSize' -Object "$($row.Server)" -Value ($sizeMB / 1024) -Unit 'GB' -Threshold $threshold -Subject 'Memory of the cache host' }
    }

    # --- Application pools of each web server ---
    foreach ($group in @($ApplicationPool | Where-Object -FilterScript { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace("$($_.Server)") } | Group-Object -Property Server)) {
        $threshold = & $thresholdOf 'ApplicationPoolsPerServer' "$($group.Name)"
        if ($threshold.Enabled) { Add-LimitRow -Limit 'ApplicationPoolsPerServer' -Object "$($group.Name)" -Value $group.Count -Unit '' -Threshold $threshold -Subject 'Application pools' }
    }

    # --- Search topology: fixed limits of the topology, a failure when one is exceeded ---
    $searchEnabled = (& $thresholdOf 'SearchTopology' '').Enabled
    if ($searchEnabled) {
        $components = @($SearchTopology | Where-Object -FilterScript { $null -ne $_ })
        $perServer = @(
            @{ Pattern = '^IndexComponent\d+$'; Max = 4; Text = 'index components' }
            @{ Pattern = '^CrawlComponent\d+$'; Max = 1; Text = 'crawl components' }
            @{ Pattern = '^ContentProcessingComponent\d+$'; Max = 1; Text = 'content processing components' }
            @{ Pattern = '^QueryProcessingComponent\d+$'; Max = 1; Text = 'query processing components' }
            @{ Pattern = '^AnalyticsProcessingComponent\d+$'; Max = 1; Text = 'analytics processing components' }
        )
        foreach ($rule in $perServer) {
            $groups = @($components | Where-Object -FilterScript { "$($_.ComponentName)" -match $rule.Pattern -and -not [string]::IsNullOrWhiteSpace("$($_.ComponentHost)") -and "$($_.ComponentHost)" -ne 'NotApplicable' } | Group-Object -Property ComponentHost)
            foreach ($group in $groups) {
                $object = "$($group.Name) ($($rule.Text))"
                $threshold = & $thresholdOf 'SearchTopology' $object
                $threshold = [PSCustomObject]@{ Enabled = $threshold.Enabled; Warning = $null; Failure = $rule.Max; Reason = $threshold.Reason }
                if ($threshold.Enabled) { Add-LimitRow -Limit 'SearchTopology' -Object $object -Value $group.Count -Unit '' -Threshold $threshold -Subject 'Components on the server' }
            }
        }
        $totals = @(
            @{ Pattern = '^IndexComponent\d+$'; Max = 60; Text = 'index components' }
            @{ Pattern = '^CrawlComponent\d+$'; Max = 16; Text = 'crawl components' }
            @{ Pattern = '^AnalyticsProcessingComponent\d+$'; Max = 6; Text = 'analytics processing components' }
            @{ Pattern = '^Partition:\d+$'; Max = 25; Text = 'index partitions' }
        )
        foreach ($rule in $totals) {
            $count = @($components | Where-Object -FilterScript { "$($_.ComponentName)" -match $rule.Pattern }).Count
            $object = "$Farm ($($rule.Text))"
            $threshold = & $thresholdOf 'SearchTopology' $object
            $threshold = [PSCustomObject]@{ Enabled = $threshold.Enabled; Warning = $null; Failure = $rule.Max; Reason = $threshold.Reason }
            if ($threshold.Enabled) { Add-LimitRow -Limit 'SearchTopology' -Object $object -Value $count -Unit '' -Threshold $threshold -Subject 'Components of the search service application' }
        }
    }

    return @($rows)
}
