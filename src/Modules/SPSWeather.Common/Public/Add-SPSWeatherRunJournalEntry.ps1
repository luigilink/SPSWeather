function Add-SPSWeatherRunJournalEntry {
    <#
        .SYNOPSIS
        Appends one record to the run journal of an environment.

        .DESCRIPTION
        Records when the run started, how long it took, the email outcome, the outcome of each farm (ok or
        unreachable, with its counts) and the settings in effect. It never breaks a run: it returns $true when the
        record was written and $false, with a warning, otherwise. The write is atomic and serialized by a lock,
        and an unreadable journal is kept aside as <name>.corrupt. See the wiki page Cockpit-Data.

        .PARAMETER Path
        Full path of the journal file (Results\<App>-<Env>.runs.json). Created when missing.

        .PARAMETER Started
        When the run started.

        .PARAMETER Duration
        How long the run took.

        .PARAMETER Version
        Version of SPSWeather that ran.

        .PARAMETER Language
        Culture name of the display language (for example en-US).

        .PARAMETER EmailMode
        PerFarm or Consolidated.

        .PARAMETER Mail
        Outcome of the email: sent, preview, disabled, failed or none.

        .PARAMETER Farm
        One object per configured farm: Name, Outcome (ok or unreachable) and, when reached, Ok, Warn and Fail.

        .PARAMETER RetentionDays
        Records older than this many days are removed. 0 (default) keeps every record.

        .PARAMETER MaxEntries
        Upper bound on the number of records kept. Default: 1000.

        .PARAMETER Setting
        The Record of Get-SPSWeatherRunSetting, stored as the settings of the record. Never pass the configuration itself.

        .PARAMETER LockTimeoutSeconds
        How long to wait for another run to finish writing the journal. Default: 20.

        .EXAMPLE
        Add-SPSWeatherRunJournalEntry -Path $journalFile -Started $DateStarted -Duration ((Get-Date) - $DateStarted) `
            -Version '3.5.0' -Language 'en-US' -EmailMode 'PerFarm' -Mail 'sent' `
            -Farm @([PSCustomObject]@{ Name = 'CONTENT'; Outcome = 'ok'; Ok = 119; Warn = 0; Fail = 3 })
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.DateTime]
        $Started,

        [Parameter(Mandatory = $true)]
        [System.TimeSpan]
        $Duration,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Version,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Language,

        [Parameter(Mandatory = $true)]
        [ValidateSet('PerFarm', 'Consolidated')]
        [System.String]
        $EmailMode,

        [Parameter(Mandatory = $true)]
        [ValidateSet('sent', 'preview', 'disabled', 'failed', 'none')]
        [System.String]
        $Mail,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Farm,

        [Parameter()]
        [System.UInt32]
        $RetentionDays = 0,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [System.Int32]
        $MaxEntries = 1000,

        [Parameter()]
        [AllowNull()]
        [System.Object]
        $Setting,

        [Parameter()]
        [ValidateRange(0, 600)]
        [System.Int32]
        $LockTimeoutSeconds = 20
    )

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $tempFile = $null
    $lock = $null

    try {
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $folder = [System.IO.Path]::GetDirectoryName($fullPath)
        if (-not [System.IO.Directory]::Exists($folder)) {
            [void][System.IO.Directory]::CreateDirectory($folder)
        }

        $farmRecords = @(foreach ($entry in $Farm) {
            $outcome = "$($entry.Outcome)"
            if ($outcome -notin @('ok', 'unreachable')) {
                throw "Farm '$($entry.Name)' has the outcome '$outcome' (expected ok or unreachable)."
            }
            $collected = ($outcome -eq 'ok')
            [ordered]@{
                name    = "$($entry.Name)"
                outcome = $outcome
                ok      = if ($collected -and $null -ne $entry.Ok) { [int]$entry.Ok } else { $null }
                warn    = if ($collected -and $null -ne $entry.Warn) { [int]$entry.Warn } else { $null }
                fail    = if ($collected -and $null -ne $entry.Fail) { [int]$entry.Fail } else { $null }
            }
        })

        $record = [ordered]@{
            started         = $Started.ToString('o', $invariant)
            durationSeconds = [int][System.Math]::Round($Duration.TotalSeconds)
            version         = $Version
            language        = $Language
            emailMode       = $EmailMode
            mail            = $Mail
            farms           = @($farmRecords)
        }
        if ($null -ne $Setting) { $record['settings'] = $Setting }

        # One writer at a time: overlapping runs would drop each other's record
        $deadline = [System.DateTime]::UtcNow.AddSeconds($LockTimeoutSeconds)
        while ($null -eq $lock) {
            try {
                $lock = [System.IO.File]::Open($fullPath + '.lock', [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            }
            catch [System.IO.IOException] {
                # Only a plain IOException means locked: its subclasses (missing folder, long path) fail at once
                if ($_.Exception.GetType() -ne [System.IO.IOException]) { throw }
                if ([System.DateTime]::UtcNow -ge $deadline) {
                    throw "another run kept the journal locked for $LockTimeoutSeconds seconds."
                }
                Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 150)
            }
        }

        $existing = Read-SPSWeatherRunJournal -Path $fullPath
        if ($existing.Status -eq 'Corrupt') {
            $aside = $fullPath + '.corrupt'
            if ([System.IO.File]::Exists($aside)) { [System.IO.File]::Replace($fullPath, $aside, [NullString]::Value) }
            else { [System.IO.File]::Move($fullPath, $aside) }
            Write-Warning -Message "SPSWeather run journal '$fullPath' could not be read: kept as '$aside', a new journal starts."
        }

        $runs = New-Object -TypeName System.Collections.ArrayList
        $cutoff = $null
        if ($RetentionDays -gt 0) { $cutoff = [System.DateTimeOffset]::Now.AddDays(-[System.Math]::Min([double]$RetentionDays, 36500)) }
        foreach ($run in @($existing.Runs)) {
            $when = [System.DateTimeOffset]::MinValue
            if (-not [System.DateTimeOffset]::TryParse("$($run.started)", $invariant, [System.Globalization.DateTimeStyles]::None, [ref]$when)) { continue }
            if ($null -ne $cutoff -and $when -lt $cutoff) { continue }
            [void]$runs.Add($run)
        }
        [void]$runs.Add($record)
        if ($runs.Count -gt $MaxEntries) { $runs.RemoveRange(0, $runs.Count - $MaxEntries) }

        $content = [ordered]@{ schemaVersion = 1 }
        if ($existing.Status -eq 'Ok') {
            foreach ($property in $existing.Journal.PSObject.Properties) {
                if ($property.Name -notin @('schemaVersion', 'runs')) { $content[$property.Name] = $property.Value }
            }
        }
        $content['runs'] = $runs.ToArray()
        $json = ConvertTo-Json -InputObject $content -Depth 20
        $tempFile = '{0}.{1}.tmp' -f $fullPath, [System.Diagnostics.Process]::GetCurrentProcess().Id
        [System.IO.File]::WriteAllText($tempFile, $json, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
        # Replace is a single step and throws on failure
        if ([System.IO.File]::Exists($fullPath)) { [System.IO.File]::Replace($tempFile, $fullPath, [NullString]::Value) }
        else { [System.IO.File]::Move($tempFile, $fullPath) }
        $tempFile = $null
        return $true
    }
    catch {
        Write-Warning -Message "SPSWeather could not update the run journal '$Path': $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($null -ne $lock) { $lock.Dispose() }
        if ($null -ne $tempFile -and [System.IO.File]::Exists($tempFile)) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}
