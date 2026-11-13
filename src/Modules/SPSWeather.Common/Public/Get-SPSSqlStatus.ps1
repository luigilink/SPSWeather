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
        $BackupMaxAgeDays = 3,

        [Parameter()]
        [System.String[]]
        $DeclaredSqlServers
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
        $aliasRows = New-Object System.Collections.ArrayList

        # Parse a raw cliconfg alias value ("<provider>,<connection-info>"). Mirrors
        # ConvertFrom-SPSSqlAliasValue, which is not available in the remote session:
        #   TCP/IP  (DBMSSOCN): "DBMSSOCN,server[\instance][,port]"
        #   Named pipes (DBNMPNTW): "DBNMPNTW,\\server\pipe\MSSQL$instance\sql\query"
        function ConvertFrom-SqlAliasRaw {
            param([string]$Raw)
            $parts = $Raw -split ',', 2
            $provider = $parts[0].Trim()
            $remainder = if ($parts.Count -eq 2) { $parts[1].Trim() } else { '' }
            $protocol = 'Unknown'; $server = ''; $instance = ''; $port = ''
            if ($provider -eq 'DBMSSOCN') {
                $protocol = 'TCP'
                $tcp = $remainder -split ','
                $target = $tcp[0].Trim()
                if ($tcp.Count -ge 2) { $port = $tcp[1].Trim() }
                if ($target -match '^(?<srv>[^\\]+)\\(?<inst>.+)$') { $server = $Matches['srv']; $instance = $Matches['inst'] } else { $server = $target }
            }
            elseif ($provider -eq 'DBNMPNTW') {
                $protocol = 'NamedPipes'
                if ($remainder -match '^\\\\(?<srv>[^\\]+)\\') { $server = $Matches['srv'] }
                if ($remainder -match '\\pipe\\MSSQL\$(?<inst>[^\\]+)\\') { $instance = $Matches['inst'] }
            }
            else { $server = $remainder }
            return [PSCustomObject]@{ Provider = $provider; Protocol = $protocol; Server = $server; Instance = $instance; Port = $port }
        }

        # Resolve a cliconfg client alias from the registry (64-bit ConnectTo and
        # 32-bit Wow6432Node). Returns the real server/instance/protocol/port and
        # the bitness where the alias is defined, or $null when it is not an alias.
        function Resolve-AliasLocal {
            param($AliasName)
            $roots = @(
                @{ Path = 'HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo'; Bitness = '64-bit' }
                @{ Path = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\MSSQLServer\Client\ConnectTo'; Bitness = '32-bit' }
            )
            $found = $null
            foreach ($root in $roots) {
                if (-not (Test-Path -Path $root.Path)) { continue }
                $key = Get-Item -Path $root.Path -ErrorAction SilentlyContinue
                if ($null -eq $key -or ($key.GetValueNames() -notcontains $AliasName)) { continue }
                $raw = [string]$key.GetValue($AliasName)
                $parsed = ConvertFrom-SqlAliasRaw -Raw $raw
                if ($null -eq $found) {
                    $found = [PSCustomObject]@{ Provider = $parsed.Provider; Protocol = $parsed.Protocol; Server = $parsed.Server; Instance = $parsed.Instance; Port = $parsed.Port; Bitness = $root.Bitness; Raw = $raw }
                }
                elseif ($found.Bitness -ne $root.Bitness) {
                    $found.Bitness = 'both'
                }
            }
            return $found
        }

        # Discover the SQL servers and SharePoint databases of the farm.
        $spDatabases = @(Get-SPDatabase | ForEach-Object {
                $srv = if ($_.Server -and $_.Server.Address) { $_.Server.Address } else { [string]$_.Server }
                [PSCustomObject]@{ Name = $_.Name; SqlServer = $srv }
            })
        $discoveredServers = @($spDatabases | Select-Object -ExpandProperty SqlServer | Sort-Object -Unique | Where-Object { $_ })
        $declaredServers = @($params.DeclaredSqlServers | Where-Object { $_ })

        # Normalized identity of a SQL target: lower-cased short host name, plus
        # \instance when it is a named one (the default instance MSSQLSERVER is the same
        # as no instance). A protocol prefix, port and domain suffix are ignored.
        function Get-SqlTargetKey {
            param([string]$Target)
            $t = ([string]$Target).Trim() -replace '^(tcp|np|lpc):', '' -replace ',\d+$', ''
            if ([string]::IsNullOrWhiteSpace($t)) { return '' }
            $srv = $t; $inst = ''
            if ($t -match '^(?<srv>[^\\]+)\\(?<inst>.+)$') { $srv = $Matches['srv']; $inst = $Matches['inst'] }
            if ($srv -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
                $short = ($srv -split '\.')[0]
                if ($short) { $srv = $short }
            }
            if ($inst -ieq 'MSSQLSERVER') { $inst = '' }
            $key = $srv.ToLowerInvariant()
            if ($inst) { $key = $key + '\' + $inst.ToLowerInvariant() }
            return $key
        }

        # Every identity a name answers to: itself and, for a cliconfg alias, the real
        # server\instance it resolves to (Get-SPDatabase returns the alias, not the server).
        function Get-SqlNameKey {
            param([string]$Name, $Alias)
            $keys = @(Get-SqlTargetKey -Target $Name)
            if ($Alias -and $Alias.Server) {
                $real = if ($Alias.Instance) { "$($Alias.Server)\$($Alias.Instance)" } else { [string]$Alias.Server }
                $keys += Get-SqlTargetKey -Target $real
            }
            return @($keys | Where-Object { $_ })
        }

        # Alias / server mapping with declared-vs-discovered validation. The union is
        # reported so a declared-but-unused or used-but-undeclared entry shows up. Two names
        # refer to the same target when they share an identity, so a declared real server
        # matches the aliases SharePoint reaches it through (and the other way round).
        function Get-SqlAliasRow {
            param($FarmName, [string[]]$DiscoveredServers, [string[]]$DeclaredServers)
            $rows = New-Object System.Collections.ArrayList
            $allNames = @(@($DiscoveredServers + $DeclaredServers) | Where-Object { $_ } | Sort-Object -Unique)
            $aliasOf = @{}
            $keysOf = @{}
            foreach ($n in $allNames) {
                $aliasOf[$n] = Resolve-AliasLocal -AliasName $n
                $keysOf[$n] = @(Get-SqlNameKey -Name $n -Alias $aliasOf[$n])
            }
            foreach ($name in $allNames) {
                $sameTarget = { param($other) @($keysOf[$other] | Where-Object { $keysOf[$name] -contains $_ }).Count -gt 0 }
                $matchingDeclared = @($DeclaredServers | Where-Object { $_ -and (& $sameTarget $_) })
                $matchingDiscovered = @($DiscoveredServers | Where-Object { $_ -and (& $sameTarget $_) })
                $isDeclared = $matchingDeclared.Count -gt 0
                $isDiscovered = $matchingDiscovered.Count -gt 0
                $alias = $aliasOf[$name]
                $notes = New-Object System.Collections.ArrayList
                if ($DeclaredServers.Count -gt 0) {
                    if ($isDiscovered -and -not $isDeclared) { [void]$notes.Add('used by SharePoint but not declared in config') }
                    if ($isDeclared -and -not $isDiscovered) { [void]$notes.Add('declared in config but not used by any database') }
                }
                $reachedVia = @($matchingDiscovered | Where-Object { $_ -ne $name })
                if ($DiscoveredServers -notcontains $name -and $reachedVia.Count -gt 0) {
                    [void]$notes.Add("used through alias $($reachedVia -join ', ')")
                }
                if ($alias -and $alias.Bitness -ne 'both' -and $alias.Provider) { [void]$notes.Add("alias defined only in $($alias.Bitness)") }
                $realServer = if ($alias) { $alias.Server } else { '' }
                if ($alias -and $alias.Instance) { $realServer = "$($alias.Server)\$($alias.Instance)" }
                [void]$rows.Add([PSCustomObject]@{
                        Farm        = $FarmName
                        Name        = $name
                        IsAlias     = [bool]$alias
                        RealServer  = $realServer
                        Protocol    = if ($alias) { $alias.Protocol } else { 'DirectName' }
                        Port        = if ($alias) { $alias.Port } else { '' }
                        Bitness     = if ($alias) { $alias.Bitness } else { '' }
                        Discovered  = $isDiscovered
                        Declared    = $isDeclared
                        Note        = ($notes -join '; ')
                        IsInfo      = $true
                    })
            }
            return $rows
        }

        foreach ($aliasRow in @(Get-SqlAliasRow -FarmName $farmName -DiscoveredServers $discoveredServers -DeclaredServers $declaredServers)) {
            [void]$aliasRows.Add($aliasRow)
        }

        # Query the servers SharePoint actually uses (declared-only entries are
        # reported above but not queried, to avoid probing unrelated servers).
        $sqlServers = $discoveredServers

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
                        IsInfo            = $true
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
            Aliases      = @($aliasRows)
        }
    }

    return $result
}
