function Get-SPSLimitStatus {
    <#
        .SYNOPSIS
        Checks a farm against the supported limits of SharePoint and returns one row for each object at or above a threshold.

        .DESCRIPTION
        The limit checks of the report (section SPSLimitStatus). The limits are the ones of the page "Software boundaries and limits for
        SharePoint Servers 2016 and 2019", which also applies to Subscription Edition: the size of a content database, the site
        collections of a database, the content databases and the web applications of the farm, the managed paths, the memory of a
        Distributed Cache host, the application pools of a web server and the topology of the search service application. See the wiki
        page Limits.

        It reads the farm once (Get-SPSLimitFact, read-only), then, only for the content databases whose allocated data size reaches the
        warning threshold, the used size of their data (Get-SPSContentDatabaseUsedSize), and judges the facts with the sections that the
        run has already collected (Get-SPSLimitRow). A farm below every threshold gives no row. Whatever goes wrong on the way, the
        run is never stopped: what could not be read is left out and written as a warning.

        .PARAMETER Server
        FQDN of the farm entry point.

        .PARAMETER InstallAccount
        The account used for the remote sessions.

        .PARAMETER Farm
        Farm label written in the Farm column of the rows.

        .PARAMETER Setting
        The result of Get-SPSWeatherLimitSetting.

        .PARAMETER SqlDatabase
        The rows of the SQLDatabaseStatus section of this farm.

        .PARAMETER ContentDatabaseStatus
        The rows of the SPSContentDBStatus section of this farm.

        .PARAMETER DistributedCache
        The rows of the AppFabricStatus section of this farm.

        .PARAMETER ApplicationPool
        The rows of the IISApplicationPoolStatus section of this farm.

        .PARAMETER SearchTopology
        The rows of the SPSSearchEntTopology section of this farm.

        .EXAMPLE
        $tbSPSLimitStatus += Get-SPSLimitStatus -Server $spTargetServer -InstallAccount $ADM -Farm 'CONTENT' -Setting $limitSetting
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Farm,

        [Parameter(Mandatory = $true)]
        $Setting,

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

    # Nothing to read when every check that needs the farm is off
    $needsFarm = @('ContentDatabaseSize', 'SiteCountPerDatabase', 'ContentDatabasesPerFarm', 'WebApplicationsPerFarm', 'ManagedPaths') |
        Where-Object -FilterScript { $Setting.Checks[$_].Enabled }

    $fact = $null
    if (@($needsFarm).Count -gt 0) {
        try {
            $fact = Get-SPSLimitFact -Server $Server -InstallAccount $InstallAccount -Farm $Farm
            if ($null -ne $fact -and -not [string]::IsNullOrEmpty("$($fact.Error)")) {
                Write-Warning -Message "Limits of farm '$Farm': the farm could not be read ($($fact.Error)); the checks that need it are left out."
                $fact = $null
            }
        }
        catch {
            Write-Warning -Message "Limits of farm '$Farm': the farm could not be read ($($_.Exception.Message)); the checks that need it are left out."
            $fact = $null
        }
    }

    # The exact size is only read for the databases whose allocated size reaches the warning threshold: usually none
    $usedSize = @()
    if ($null -ne $fact -and $Setting.Checks['ContentDatabaseSize'].Enabled) {
        $candidates = New-Object -TypeName System.Collections.ArrayList
        foreach ($database in @($fact.ContentDatabases)) {
            $threshold = Get-SPSLimitThreshold -Setting $Setting -Limit 'ContentDatabaseSize' -Object "$($database.Name)"
            if (-not $threshold.Enabled -or $null -eq $threshold.Warning) { continue }
            $sql = @($SqlDatabase | Where-Object -FilterScript { $null -ne $_ -and "$($_.Name)" -eq "$($database.Name)" })[0]
            $allocatedMB = 0.0
            if ($null -ne $sql -and [double]::TryParse([string]$sql.DataSizeMB, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$allocatedMB)) {
                if (($allocatedMB / 1024) -ge $threshold.Warning) { [void]$candidates.Add($database) }
            }
        }
        if ($candidates.Count -gt 0) {
            try { $usedSize = @(Get-SPSContentDatabaseUsedSize -Server $Server -InstallAccount $InstallAccount -Farm $Farm -Database @($candidates)) }
            catch { Write-Warning -Message "Limits of farm '$Farm': the used size of the databases could not be read ($($_.Exception.Message)); the allocated size is used."; $usedSize = @() }
        }
    }

    try {
        return @(Get-SPSLimitRow -Farm $Farm -Setting $Setting -Fact $fact -SqlDatabase $SqlDatabase -ContentDatabaseStatus $ContentDatabaseStatus `
                -UsedSize $usedSize -DistributedCache $DistributedCache -ApplicationPool $ApplicationPool -SearchTopology $SearchTopology)
    }
    catch {
        Write-Warning -Message "Limits of farm '$Farm': the limits could not be judged ($($_.Exception.Message))."
        return @()
    }
}
