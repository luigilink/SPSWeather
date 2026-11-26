function Read-SPSWeatherRunJournal {
    <#
        .SYNOPSIS
        Reads the run journal written by Add-SPSWeatherRunJournalEntry.

        .DESCRIPTION
        Returns Status (Missing, Ok or Corrupt), Runs and Journal (the object as read, so that the writer keeps
        the fields it does not know). A file that cannot be opened is not Corrupt: the exception is left to the caller.
        Timestamps are returned as ISO 8601 strings on every PowerShell version.

        .PARAMETER Path
        Full path of the journal file.

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
    $missing = [PSCustomObject]@{ Status = 'Missing'; Runs = @(); Journal = $null }
    $corrupt = [PSCustomObject]@{ Status = 'Corrupt'; Runs = @(); Journal = $null }

    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not [System.IO.File]::Exists($fullPath)) {
        return $missing
    }

    $content = [System.IO.File]::ReadAllText($fullPath)
    # ConvertFrom-Json unwraps a list of one object: check the root in the text
    if (-not $content.TrimStart().StartsWith('{')) { return $corrupt }
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
    if ($null -eq $journal.PSObject.Properties['runs'] -or $journal.runs -isnot [System.Array]) {
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

    return [PSCustomObject]@{ Status = 'Ok'; Runs = $runs.ToArray(); Journal = $journal }
}
