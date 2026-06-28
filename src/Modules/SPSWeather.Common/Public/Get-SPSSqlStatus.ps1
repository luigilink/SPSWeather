function Get-SPSSqlStatus {
    <#
        .SYNOPSIS
        Collects SharePoint-relevant SQL Server health data for a farm.

        .DESCRIPTION
        Get-SPSSqlStatus runs on a SharePoint server (over CredSSP via
        Invoke-SPSCommand), discovers the SQL servers backing the farm with
        Get-SPDatabase, and queries each of them with dependency-free ADO.NET
        (System.Data.SqlClient, always present on a SharePoint server). Running on
        the SharePoint server means SQL client aliases resolve exactly as they do
        for SharePoint.

        It returns four collections, each row carrying an IsInfo flag (so a
        non-informational row raises the global SPSWeather ALERT) and the Farm name:

        - Instances    : version/edition/build, MAXDOP, max server memory, TempDB
                         file count vs CPU count.
        - Databases    : state, recovery model, data/log size, last full backup,
                         compatibility level, AutoShrink/AutoClose (SharePoint DBs).
        - Disks        : free space per volume hosting SQL files
                         (sys.dm_os_volume_stats).
        - Availability : AlwaysOn AG replica sync health and recent failed SQL
                         Agent jobs.

        Connectivity uses Integrated Security as the InstallAccount, which therefore
        needs at least VIEW SERVER STATE plus read access to master/msdb. A SQL
        server that cannot be reached produces a single IsInfo = $false error row in
        the relevant collection instead of throwing, so one bad instance does not
        abort the farm pass.

        .PARAMETER Server
        FQDN of the SharePoint server used to run the discovery and the queries.

        .PARAMETER InstallAccount
        Credential used for the CredSSP session and the SQL Integrated Security
        connection.

        .PARAMETER Farm
        Friendly farm name, copied onto every returned row.

        .PARAMETER DiskFreeThresholdPercent
        A volume with less than this percentage free raises an alert. Default 15.

        .PARAMETER BackupMaxAgeDays
        A database whose last full backup is older than this many days raises an
        alert. Default 3.

        .EXAMPLE
        $sql = Get-SPSSqlStatus -Server $spTargetServer -InstallAccount $ADM -Farm 'CONTENT'
        $sql.Databases | Where-Object { -not $_.IsInfo }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $InstallAccount,

        [Parameter()]
        [System.String]
        $Farm,

        [Parameter()]
        [System.Int32]
        $DiskFreeThresholdPercent = 15,

        [Parameter()]
        [System.Int32]
        $BackupMaxAgeDays = 3
    )

    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments $PSBoundParameters `
        -Server $Server `
        -ScriptBlock {
        $params = $args[0]
        $farmName = $params.Farm
        $diskThreshold = if ($params.ContainsKey('DiskFreeThresholdPercent')) { [int]$params.DiskFreeThresholdPercent } else { 15 }
        $backupMaxAge = if ($params.ContainsKey('BackupMaxAgeDays')) { [int]$params.BackupMaxAgeDays } else { 3 }

        # Run a T-SQL query against $sqlServer using dependency-free ADO.NET.
        function Invoke-SqlAdo {
            param($SqlServer, $Query)
            $conn = New-Object System.Data.SqlClient.SqlConnection
            $conn.ConnectionString = "Server=$SqlServer;Database=master;Integrated Security=SSPI;Application Name=SPSWeather;Connect Timeout=15"
            $conn.Open()
            try {
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = $Query
                $cmd.CommandTimeout = 30
                $table = New-Object System.Data.DataTable
                $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
                [void]$adapter.Fill($table)
                return , $table
            }
            finally {
                $conn.Close()
                $conn.Dispose()
            }
        }

        $instances = New-Object System.Collections.ArrayList
        $databases = New-Object System.Collections.ArrayList
        $disks = New-Object System.Collections.ArrayList
        $availability = New-Object System.Collections.ArrayList

        # Discover the SQL servers and SharePoint databases of the farm.
        $spDatabases = @(Get-SPDatabase | ForEach-Object {
                $srv = if ($_.Server -and $_.Server.Address) { $_.Server.Address } else { [string]$_.Server }
                [PSCustomObject]@{ Name = $_.Name; SqlServer = $srv }
            })
        $sqlServers = @($spDatabases | Select-Object -ExpandProperty SqlServer | Sort-Object -Unique | Where-Object { $_ })

        foreach ($sqlServer in $sqlServers) {
            try {
                # --- Instance ---
                $instQuery = @"
SELECT
    CAST(SERVERPROPERTY('ServerName') AS nvarchar(256)) AS ServerName,
    CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(64)) AS Version,
    CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(64)) AS ProductLevel,
    CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(64)) AS UpdateLevel,
    CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS Edition,
    (SELECT CAST(value_in_use AS int) FROM sys.configurations WHERE name = 'max degree of parallelism') AS MaxDop,
    (SELECT CAST(value_in_use AS bigint) FROM sys.configurations WHERE name = 'max server memory (MB)') AS MaxServerMemoryMB,
    (SELECT cpu_count FROM sys.dm_os_sys_info) AS CpuCount,
    (SELECT COUNT(*) FROM tempdb.sys.database_files WHERE type = 0) AS TempDbDataFiles
"@
                $row = (Invoke-SqlAdo -SqlServer $sqlServer -Query $instQuery).Rows[0]
                $maxDop = [int]$row.MaxDop
                $tempDbFiles = [int]$row.TempDbDataFiles
                $cpuCount = [int]$row.CpuCount
                $maxMem = [long]$row.MaxServerMemoryMB
                $notes = New-Object System.Collections.ArrayList
                if ($maxDop -ne 1) { [void]$notes.Add("MAXDOP=$maxDop (SharePoint requires 1)") }
                if ($maxMem -eq 2147483647) { [void]$notes.Add('max server memory is not capped') }
                if ($tempDbFiles -eq 1 -and $cpuCount -gt 1) { [void]$notes.Add("TempDB has 1 data file for $cpuCount CPUs") }
                [void]$instances.Add([PSCustomObject]@{
                        Farm              = $farmName
                        SqlServer         = $sqlServer
                        ServerName        = [string]$row.ServerName
                        Edition           = [string]$row.Edition
                        Version           = [string]$row.Version
                        ProductLevel      = [string]$row.ProductLevel
                        UpdateLevel       = [string]$row.UpdateLevel
                        MaxDop            = $maxDop
                        MaxServerMemoryMB = $maxMem
                        TempDbDataFiles   = $tempDbFiles
                        Recommendation    = ($notes -join '; ')
                        IsInfo            = ($notes.Count -eq 0)
                    })

                # --- Databases (filtered to SharePoint databases on this server) ---
                $spNamesHere = @($spDatabases | Where-Object { $_.SqlServer -eq $sqlServer } | Select-Object -ExpandProperty Name)
                $dbQuery = @"
SELECT d.name AS DbName, d.state_desc AS State, d.recovery_model_desc AS RecoveryModel,
    d.compatibility_level AS CompatLevel, d.is_auto_shrink_on AS AutoShrink, d.is_auto_close_on AS AutoClose,
    CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size END) * 8 / 1024.0 AS decimal(18,2)) AS DataSizeMB,
    CAST(ISNULL(SUM(CASE WHEN mf.type = 1 THEN mf.size END), 0) * 8 / 1024.0 AS decimal(18,2)) AS LogSizeMB,
    (SELECT MAX(bs.backup_finish_date) FROM msdb.dbo.backupset bs WHERE bs.database_name = d.name AND bs.type = 'D') AS LastFullBackup
FROM sys.databases d
JOIN sys.master_files mf ON d.database_id = mf.database_id
GROUP BY d.name, d.state_desc, d.recovery_model_desc, d.compatibility_level, d.is_auto_shrink_on, d.is_auto_close_on
"@
                $dbTable = Invoke-SqlAdo -SqlServer $sqlServer -Query $dbQuery
                foreach ($db in $dbTable.Rows) {
                    if ($spNamesHere -notcontains [string]$db.DbName) { continue }
                    $state = [string]$db.State
                    $lastBackup = if ($db.LastFullBackup -is [DateTime]) { [DateTime]$db.LastFullBackup } else { $null }
                    $backupAge = if ($lastBackup) { [math]::Round(((Get-Date) - $lastBackup).TotalDays, 1) } else { $null }
                    $notes = New-Object System.Collections.ArrayList
                    $isAlert = $false
                    if ($state -ne 'ONLINE') { [void]$notes.Add("state=$state"); $isAlert = $true }
                    if ($null -eq $lastBackup) { [void]$notes.Add('no full backup found'); $isAlert = $true }
                    elseif ($backupAge -gt $backupMaxAge) { [void]$notes.Add("last full backup $backupAge d ago"); $isAlert = $true }
                    if ([bool]$db.AutoShrink) { [void]$notes.Add('AutoShrink ON') }
                    if ([bool]$db.AutoClose) { [void]$notes.Add('AutoClose ON') }
                    [void]$databases.Add([PSCustomObject]@{
                            Farm           = $farmName
                            SqlServer      = $sqlServer
                            Name           = [string]$db.DbName
                            State          = $state
                            RecoveryModel  = [string]$db.RecoveryModel
                            DataSizeMB     = [decimal]$db.DataSizeMB
                            LogSizeMB      = [decimal]$db.LogSizeMB
                            LastFullBackup = if ($lastBackup) { $lastBackup.ToString('yyyy-MM-dd HH:mm') } else { 'never' }
                            CompatLevel    = [int]$db.CompatLevel
                            Recommendation = ($notes -join '; ')
                            IsInfo         = (-not $isAlert)
                        })
                }

                # --- Disk volumes hosting SQL files ---
                $diskQuery = @"
SELECT DISTINCT vs.volume_mount_point AS Volume,
    CAST(vs.total_bytes / 1073741824.0 AS decimal(18,2)) AS TotalGB,
    CAST(vs.available_bytes / 1073741824.0 AS decimal(18,2)) AS FreeGB,
    CAST(vs.available_bytes * 100.0 / NULLIF(vs.total_bytes, 0) AS decimal(5,2)) AS FreePercent
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
"@
                $diskTable = Invoke-SqlAdo -SqlServer $sqlServer -Query $diskQuery
                foreach ($vol in $diskTable.Rows) {
                    $freePercent = [decimal]$vol.FreePercent
                    [void]$disks.Add([PSCustomObject]@{
                            Farm        = $farmName
                            SqlServer   = $sqlServer
                            Volume      = [string]$vol.Volume
                            TotalGB     = [decimal]$vol.TotalGB
                            FreeGB      = [decimal]$vol.FreeGB
                            FreePercent = $freePercent
                            IsInfo      = ($freePercent -ge $diskThreshold)
                        })
                }

                # --- Availability: AlwaysOn AG sync health + recent failed SQL Agent jobs ---
                $agQuery = @"
SELECT ag.name AS AGName, ar.replica_server_name AS Replica,
    ars.role_desc AS Role, ars.synchronization_health_desc AS SyncHealth
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
"@
                try {
                    $agTable = Invoke-SqlAdo -SqlServer $sqlServer -Query $agQuery
                    foreach ($ag in $agTable.Rows) {
                        $health = [string]$ag.SyncHealth
                        [void]$availability.Add([PSCustomObject]@{
                                Farm      = $farmName
                                SqlServer = $sqlServer
                                Type      = 'AvailabilityGroup'
                                Name      = "$([string]$ag.AGName) / $([string]$ag.Replica) ($([string]$ag.Role))"
                                Detail    = $health
                                IsInfo    = ($health -eq 'HEALTHY')
                            })
                    }
                }
                catch {
                    # AlwaysOn not enabled on this instance - nothing to report.
                    Write-Verbose -Message "AlwaysOn availability groups not queried on '$sqlServer': $($_.Exception.Message)"
                }

                $jobQuery = @"
SELECT TOP 20 j.name AS JobName, h.run_date AS RunDate, h.run_time AS RunTime
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE h.step_id = 0 AND h.run_status = 0
    AND msdb.dbo.agent_datetime(h.run_date, h.run_time) > DATEADD(DAY, -1, GETDATE())
ORDER BY h.run_date DESC, h.run_time DESC
"@
                try {
                    $jobTable = Invoke-SqlAdo -SqlServer $sqlServer -Query $jobQuery
                    foreach ($job in $jobTable.Rows) {
                        [void]$availability.Add([PSCustomObject]@{
                                Farm      = $farmName
                                SqlServer = $sqlServer
                                Type      = 'FailedAgentJob'
                                Name      = [string]$job.JobName
                                Detail    = "failed run on $([string]$job.RunDate)"
                                IsInfo    = $false
                            })
                    }
                }
                catch {
                    # SQL Agent / msdb not accessible - skip job history.
                    Write-Verbose -Message "SQL Agent job history not queried on '$sqlServer': $($_.Exception.Message)"
                }
            }
            catch {
                $message = $_.Exception.Message
                [void]$instances.Add([PSCustomObject]@{
                        Farm              = $farmName
                        SqlServer         = $sqlServer
                        ServerName        = $sqlServer
                        Edition           = 'unreachable'
                        Version           = ''
                        ProductLevel      = ''
                        UpdateLevel       = ''
                        MaxDop            = 0
                        MaxServerMemoryMB = 0
                        TempDbDataFiles   = 0
                        Recommendation    = "Query failed: $message"
                        IsInfo            = $false
                    })
            }
        }

        [PSCustomObject]@{
            Instances    = @($instances)
            Databases    = @($databases)
            Disks        = @($disks)
            Availability = @($availability)
        }
    }

    return $result
}
