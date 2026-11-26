function Add-SPSWeatherRunJournalEntry {
    <#
        .SYNOPSIS
        Appends one record to the run journal of an environment.

        .DESCRIPTION
        A farm that cannot be reached leaves no JSON snapshot, so a page that tracks the
        collections over time has nothing to read for it. Add-SPSWeatherRunJournalEntry records every
        run in a small JSON file: when it started, how long it took, the script version, the display
        language, the email mode and the outcome of the email, and for each configured farm whether
        it was collected (ok) or unreachable, with its counts of checks when collected.

        The journal is never allowed to break a run: the function returns $true when the record was
        written and $false (with a warning) otherwise. It writes through a temporary file that then
        replaces the journal, so a crash never leaves a truncated file. A journal that cannot be read
        (corrupt, unexpected shape, newer schema) is kept aside as <name>.corrupt and a new one starts.

        Two runs of the same environment can overlap (a manual run next to the scheduled task): the whole
        read, prune, append and replace sequence is serialized with an exclusive lock on <name>.lock, a small
        empty file that stays next to the journal. A run that cannot get the lock within -LockTimeoutSeconds
        gives up with a warning rather than wait for ever, and the operating system releases the lock if a
        run is killed. Fields of the journal that this version does not know are kept when it is rewritten.

        Records older than -RetentionDays are pruned (0 keeps them all) and the journal never holds
        more than -MaxEntries records. Nothing is collected from the farm: the record only holds
        the farm name, its outcome and the counts that the snapshot already contains.

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
        Outcome of the email: sent, preview, disabled, failed, or none (nothing to send).

        .PARAMETER Farm
        One object per configured farm with the properties Name, Outcome (ok or unreachable) and,
        for a collected farm, Ok, Warn and Fail.

        .PARAMETER RetentionDays
        Records older than this many days are removed. 0 (default) keeps every record.

        .PARAMETER MaxEntries
        Upper bound on the number of records kept (the oldest are removed first). Default: 1000.

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

        # Exclusive lock for the whole read-modify-write: without it two overlapping runs read the same
        # journal and the last one to replace it silently drops the record of the other.
        $deadline = [System.DateTime]::UtcNow.AddSeconds($LockTimeoutSeconds)
        while ($null -eq $lock) {
            try {
                $lock = [System.IO.File]::Open($fullPath + '.lock', [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            }
            catch [System.IO.IOException] {
                # Only a plain IOException is a lock held by another run (a missing folder or a path that is
                # too long are IOException subclasses and must fail at once, not after the timeout).
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
        # Replace swaps the content in one step (the journal never disappears) and throws on failure.
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
