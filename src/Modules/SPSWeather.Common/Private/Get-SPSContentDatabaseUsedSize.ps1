function Get-SPSContentDatabaseUsedSize {
    <#
        .SYNOPSIS
        Reads the used size of the data of the content databases that need an exact figure.

        .DESCRIPTION
        The allocated size of the data files (already collected by Get-SPSSqlStatus) is an upper bound: a database in a file pre-sized
        to 210 GB can hold 120 GB. Only the databases whose allocated size reaches the warning threshold are asked here, usually none.
        For each one, the query runs in the context of the database and sums the space used by its data files (FILEPROPERTY SpaceUsed),
        never the log: the 200 GB limit is about the content.

        Read-only, one connection per database with the account of the remote session, a time limit on each query, and a time budget
        for all of them together: when it is spent, the databases left are not tried and are returned with an Error and no size, so
        that an unreachable SQL server cannot delay the report by one connection timeout for each database. A database that cannot be
        read is returned with its Error and no size, so that the caller keeps the allocated one and says so. Never throws.

        .PARAMETER Server
        FQDN of the farm entry point, from where the SQL servers are reached.

        .PARAMETER InstallAccount
        The account used for the remote session.

        .PARAMETER Farm
        Farm label written in the Farm column of the rows.

        .PARAMETER Database
        The databases to read: objects with Name and SqlServer (the instance or alias that SharePoint uses).

        .PARAMETER TimeBudgetSeconds
        The time, in seconds, after which no other database is tried (default 120). 0 reads nothing.
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

        [Parameter()]
        [System.String]
        $Farm = 'SPS',

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Database,

        [Parameter()]
        [ValidateRange(0, 3600)]
        [System.UInt32]
        $TimeBudgetSeconds = 120
    )

    if (@($Database).Count -eq 0) { return @() }

    $targets = @($Database | ForEach-Object -Process { @{ Name = "$($_.Name)"; SqlServer = "$($_.SqlServer)" } })
    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments @{ Farm = $Farm; Database = $targets; TimeBudgetSeconds = $TimeBudgetSeconds } `
        -Server $Server `
        -ScriptBlock {
        $params = $args[0]
        $rows = New-Object -TypeName System.Collections.ArrayList
        $deadline = [System.DateTime]::UtcNow.AddSeconds([double]$params.TimeBudgetSeconds)
        foreach ($target in @($params.Database)) {
            $row = [PSCustomObject]@{ Farm = "$($params.Farm)"; Name = "$($target.Name)"; SqlServer = "$($target.SqlServer)"; UsedDataMB = $null; Error = '' }
            if ([System.DateTime]::UtcNow -ge $deadline) {
                $row.Error = "the time budget of $($params.TimeBudgetSeconds) seconds for reading the used size was spent"
                [void]$rows.Add($row)
                continue
            }
            $connection = $null
            try {
                $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection
                $builder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder
                $builder['Data Source'] = "$($target.SqlServer)"
                $builder['Initial Catalog'] = "$($target.Name)"
                $builder['Integrated Security'] = $true
                $builder['Application Name'] = 'SPSWeather'
                $builder['Connect Timeout'] = 15
                $connection.ConnectionString = $builder.ConnectionString
                $connection.Open()
                $command = $connection.CreateCommand()
                $command.CommandText = "SELECT CAST(ISNULL(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint)), 0) * 8 / 1024.0 AS decimal(18,2)) FROM sys.database_files WHERE type = 0"
                $command.CommandTimeout = 30
                $row.UsedDataMB = [System.Decimal]$command.ExecuteScalar()
            }
            catch {
                $row.Error = "$($_.Exception.Message)"
            }
            finally {
                if ($null -ne $connection) { $connection.Close(); $connection.Dispose() }
            }
            [void]$rows.Add($row)
        }
        return @($rows)
    }
    return @($result)
}
