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

        Records older than -RetentionDays are pruned (0 keeps them all) and the journal never holds
        more than -MaxEntries records. Nothing is collected from the farm: the record only holds
        the farm name, its outcome and the counts that the snapshot already contains.

        .PARAMETER Path
        Full path of the journal file (Results\<App>-<Env>-runs.json). Created when missing.

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
        $MaxEntries = 1000
    )

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $tempFile = $null

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

        $existing = Read-SPSWeatherRunJournal -Path $fullPath
        if ($existing.Status -eq 'Corrupt') {
            $aside = $fullPath + '.corrupt'
            Move-Item -LiteralPath $fullPath -Destination $aside -Force
            Write-Warning -Message "SPSWeather run journal '$fullPath' could not be read: kept as '$aside', a new journal starts."
        }

        $runs = New-Object -TypeName System.Collections.ArrayList
        $cutoff = $null
        if ($RetentionDays -gt 0) { $cutoff = [System.DateTimeOffset]::Now.AddDays(-[double]$RetentionDays) }
        foreach ($run in @($existing.Runs)) {
            $when = [System.DateTimeOffset]::MinValue
            if (-not [System.DateTimeOffset]::TryParse("$($run.started)", $invariant, [System.Globalization.DateTimeStyles]::None, [ref]$when)) { continue }
            if ($null -ne $cutoff -and $when -lt $cutoff) { continue }
            [void]$runs.Add($run)
        }
        [void]$runs.Add($record)
        if ($runs.Count -gt $MaxEntries) { $runs.RemoveRange(0, $runs.Count - $MaxEntries) }

        $json = ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = 1; runs = $runs.ToArray() }) -Depth 6
        $tempFile = '{0}.{1}.tmp' -f $fullPath, [System.Diagnostics.Process]::GetCurrentProcess().Id
        [System.IO.File]::WriteAllText($tempFile, $json, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
        Move-Item -LiteralPath $tempFile -Destination $fullPath -Force
        $tempFile = $null
        return $true
    }
    catch {
        Write-Warning -Message "SPSWeather could not update the run journal '$Path': $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($null -ne $tempFile -and [System.IO.File]::Exists($tempFile)) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}
