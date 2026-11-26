function Read-SPSWeatherRunJournal {
    <#
        .SYNOPSIS
        Reads the run journal written by Add-SPSWeatherRunJournalEntry.

        .DESCRIPTION
        Returns an object with a Status and the Runs found in the file at -Path:
        Missing (no file yet, first run), Ok, or Corrupt (the file is not valid JSON, has
        an unexpected shape or comes from a newer schema). Runs is then an empty array and the
        caller decides what to do. A file that exists but cannot be opened (sharing violation,
        access denied) is NOT reported as Corrupt: the I/O exception is left to the caller, so a
        healthy journal is never set aside because of a transient lock.

        The timestamp of each run ('started') is always returned as an ISO 8601 string, whatever
        the PowerShell version: PowerShell 7 turns date-like JSON strings into [datetime], which
        would otherwise change the format of the records when they are written back.

        .PARAMETER Path
        Full path of the journal file (Results\<App>-<Env>-runs.json).

        .EXAMPLE
        (Read-SPSWeatherRunJournal -Path $journalFile).Runs
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $supportedSchemaVersion = 1
    $missing = [PSCustomObject]@{ Status = 'Missing'; Runs = @() }
    $corrupt = [PSCustomObject]@{ Status = 'Corrupt'; Runs = @() }

    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not [System.IO.File]::Exists($fullPath)) {
        return $missing
    }

    $content = [System.IO.File]::ReadAllText($fullPath)
    try {
        $journal = ConvertFrom-Json -InputObject $content -ErrorAction Stop
    }
    catch {
        Write-Verbose -Message "Read-SPSWeatherRunJournal: '$fullPath' is not valid JSON. $($_.Exception.Message)"
        return $corrupt
    }

    $schema = 0
    if ($null -eq $journal -or -not [int]::TryParse("$($journal.schemaVersion)", [ref]$schema) -or $schema -lt 1 -or $schema -gt $supportedSchemaVersion) {
        return $corrupt
    }
    if ($null -eq $journal.PSObject.Properties['runs']) {
        return $corrupt
    }

    $runs = New-Object -TypeName System.Collections.ArrayList
    foreach ($run in @($journal.runs)) {
        if ($null -eq $run -or $null -eq $run.PSObject.Properties['started']) { continue }
        if ($run.started -is [System.DateTime]) {
            $run.started = $run.started.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        [void]$runs.Add($run)
    }

    return [PSCustomObject]@{ Status = 'Ok'; Runs = $runs.ToArray() }
}
