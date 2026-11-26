function Get-SPSWeatherCockpitData {
    <#
        .SYNOPSIS
        Builds the one dataset of the multi-farm page from the files that the runs leave in Results.

        .DESCRIPTION
        The per-farm dashboard reads the history of one farm. A page for the whole environment needs the history
        of every farm, the run journal and the settings in one structure. This function reads, read-only:

          Results\history\<Farm>\<App>-<Env>-<Farm>-*.json
                                          the archived snapshots of each farm (the date of a snapshot is the
                                          time the file was written, which the archive keeps). The folder of a
                                          farm is shared by the environments of an installation that name a farm
                                          the same: only the files of this application and environment are read
          Results\<App>-<Env>-<Farm>.json the snapshot of the last run of each farm
          Results\<App>-<Env>.runs.json   the run journal (see Add-SPSWeatherRunJournalEntry)

        and returns an ordered dictionary, ready for ConvertTo-Json, with the sections:

          schemaVersion, generatedAt, environment
          period    retentionDays, offered (the period buttons: 7, 14, 30 and 60 days, limited by the
                    retention; every one of them when the retention is 0), maxDays, firstDay, lastDay
          rules     the weather rule (stormyAbove)
          days      the days of the page, one per calendar day from the first day with data to today, and weekend
          farms     for each farm, in the order of the configuration: name, daily (one entry per day, aligned with
                    days, or $null when nothing is known: ok, warn, fail, weather, snapshots, unreachable),
                    latestSnapshot, snapshotsTruncated, attention (what needs attention in the last snapshot:
                    farm, section, id, name, severity, cause, detail, since - the day of the first snapshot of the
                    unbroken series of snapshots in which the item needed attention - and sinceIsLowerBound when
                    that series starts at the oldest snapshot read), attentionTotal and attentionTruncated
          runs      the records of the run journal inside the period
          settings  current (the settings of the last record that has some) and changes (the thresholds, the
                    exclusions and the configuration file that changed between two records, oldest first)
          skipped   the snapshots that were not used (missing, empty or not valid JSON), by file name
          kpi       $null: reserved for the nightly activity run, so that a later release can fill it without
                    changing this contract

        A day is described by the last usable snapshot of that day, and every usable snapshot counts to say since
        when an item needs attention. A snapshot that cannot be used is skipped with a
        warning: the dataset is never a reason for a run to fail. Nothing is written and nothing is collected
        from the farms. The counts follow the same rule as the dashboard (Get-SPSWeatherSnapshotSummary).

        .PARAMETER ResultsFolder
        The Results folder of the installation.

        .PARAMETER Application
        The ApplicationName of the environment configuration.

        .PARAMETER Environment
        The ConfigurationName of the environment configuration.

        .PARAMETER FarmName
        The names of the configured farms, in the order to show them. A farm that is only in the history or in the
        journal is added after them.

        .PARAMETER RetentionDays
        JsonHistoryRetentionDays of the configuration. It limits the periods that are offered; it is not changed
        and nothing is deleted. 0 offers all of them.

        .PARAMETER Now
        The current time (a parameter so that tests do not depend on the clock).

        .PARAMETER MaxItemsPerFarm
        Upper bound on the items listed in attention for each farm (failures first, then the oldest).

        .PARAMETER MaxSnapshotsPerFarm
        Upper bound on the snapshots read for each farm (the most recent ones): about 60 days of several runs a
        day. A farm that has more is flagged with snapshotsTruncated, and a warning says so.

        .EXAMPLE
        Get-SPSWeatherCockpitData -ResultsFolder $pathResultsFolder -Application $Application -Environment $Environment -FarmName 'CONTENT', 'SEARCH' -RetentionDays 30
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ResultsFolder,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Application,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Environment,

        [Parameter()]
        [System.String[]]
        $FarmName,

        [Parameter()]
        [System.UInt32]
        $RetentionDays = 0,

        [Parameter()]
        [System.DateTime]
        $Now = (Get-Date),

        [Parameter()]
        [ValidateRange(1, 5000)]
        [System.Int32]
        $MaxItemsPerFarm = 300,

        [Parameter()]
        [ValidateRange(1, 5000)]
        [System.Int32]
        $MaxSnapshotsPerFarm = 400
    )

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $stormyAbove = 5
    $skipped = New-Object -TypeName System.Collections.ArrayList

    function _day([System.DateTime]$when) { $when.ToString('yyyy-MM-dd', $invariant) }
    function _safe([string]$name) { $name -replace '[^A-Za-z0-9_-]', '_' }

    # --- the periods that are offered, limited by the retention (which is never changed) ---
    $standard = @(7, 14, 30, 60)
    if ($RetentionDays -eq 0) { $offered = $standard }
    else {
        $offered = @($standard | Where-Object -FilterScript { $_ -le $RetentionDays })
        if ($offered.Count -eq 0) { $offered = @([int]$RetentionDays) }
    }
    $maxDays = [int](($offered | Measure-Object -Maximum).Maximum)
    $today = $Now.Date
    $windowStart = $today.AddDays(-($maxDays - 1))

    # --- the run journal ---
    $journalRuns = @()
    $journalPath = Join-Path -Path $ResultsFolder -ChildPath "$Application-$Environment.runs.json"
    try {
        $journal = Read-SPSWeatherRunJournal -Path $journalPath
        if ($journal.Status -eq 'Corrupt') {
            Write-Warning -Message "SPSWeather cockpit: the run journal '$(Split-Path -Path $journalPath -Leaf)' cannot be read and is ignored."
            [void]$skipped.Add((Split-Path -Path $journalPath -Leaf))
        }
        $journalRuns = @($journal.Runs)
    }
    catch {
        Write-Warning -Message "SPSWeather cockpit: the run journal '$(Split-Path -Path $journalPath -Leaf)' cannot be opened and is ignored. $($_.Exception.Message)"
        [void]$skipped.Add((Split-Path -Path $journalPath -Leaf))
    }

    $runsInPeriod = New-Object -TypeName System.Collections.ArrayList
    foreach ($run in $journalRuns) {
        $when = [System.DateTimeOffset]::MinValue
        if (-not [System.DateTimeOffset]::TryParse("$($run.started)", $invariant, [System.Globalization.DateTimeStyles]::None, [ref]$when)) { continue }
        if ($when.LocalDateTime.Date -lt $windowStart -or $when.LocalDateTime.Date -gt $today) { continue }
        [void]$runsInPeriod.Add([PSCustomObject]@{ When = $when; Run = $run })
    }
    $runsInPeriod = @($runsInPeriod | Sort-Object -Property When)

    # The files that belong to a farm for this application and environment: its archived snapshots and the
    # snapshot of the last run. The archive folder of a farm is shared by the environments of an installation
    # that name a farm the same, so the name of the file is what tells them apart.
    $historyRoot = Join-Path -Path $ResultsFolder -ChildPath 'history'
    function _farmFiles([string]$safe) {
        $found = New-Object -TypeName System.Collections.ArrayList
        $prefix = "$Application-$Environment-$safe-"
        $folder = Join-Path -Path $historyRoot -ChildPath $safe
        if (Test-Path -LiteralPath $folder) {
            foreach ($f in @(Get-ChildItem -LiteralPath $folder -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
                if ($f.Name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { [void]$found.Add($f) }
            }
        }
        $current = Join-Path -Path $ResultsFolder -ChildPath "$Application-$Environment-$safe.json"
        if (Test-Path -LiteralPath $current -PathType Leaf) { [void]$found.Add((Get-Item -LiteralPath $current)) }
        return , $found
    }

    # --- the farms: the configuration first, then what only the journal or the history knows ---
    $farmDisplay = [ordered]@{}
    foreach ($name in @($FarmName)) {
        if (-not [string]::IsNullOrWhiteSpace($name) -and -not $farmDisplay.Contains((_safe $name))) { $farmDisplay[(_safe $name)] = $name }
    }
    foreach ($entry in $runsInPeriod) {
        foreach ($farm in @($entry.Run.farms)) {
            $name = "$($farm.name)"
            if (-not [string]::IsNullOrWhiteSpace($name) -and -not $farmDisplay.Contains((_safe $name))) { $farmDisplay[(_safe $name)] = $name }
        }
    }
    if (Test-Path -LiteralPath $historyRoot) {
        foreach ($folder in @(Get-ChildItem -LiteralPath $historyRoot -Directory -ErrorAction SilentlyContinue | Sort-Object -Property Name)) {
            # A folder that only holds the files of another application or environment is not a farm of this page.
            if (-not $farmDisplay.Contains($folder.Name) -and (_farmFiles $folder.Name).Count -gt 0) { $farmDisplay[$folder.Name] = $folder.Name }
        }
    }

    # A snapshot is the JSON object that a run writes. ConvertFrom-Json unwraps a list of one object into that
    # object, so the root is checked in the text, before it is read.
    function _readSnapshot([string]$path) {
        $text = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        if (-not $text.TrimStart([char[]]@([char]0xFEFF, [char]32, [char]9, [char]13, [char]10)).StartsWith('{')) { return $null }
        $object = ConvertFrom-Json -InputObject $text -ErrorAction Stop
        if ($object -is [System.Management.Automation.PSCustomObject]) { return $object }
        return $null
    }

    # --- the snapshots of each farm, in the order they were written ---
    # Every usable snapshot is read, not only the last of each day: an item that was fixed and came back the
    # same day must start again, and a corrupt last snapshot must not hide the valid one before it. For each one
    # only what the page needs is kept (the counts and the identities of the items that need attention), so the
    # parsed snapshot can be freed, whatever its size.
    $farmSeries = [ordered]@{}
    $farmFilesPerDay = @{}
    $farmTruncated = @{}
    $earliest = $null
    foreach ($safe in @($farmDisplay.Keys)) {
        $inPeriod = New-Object -TypeName System.Collections.ArrayList
        $perDay = @{}
        foreach ($f in (_farmFiles $safe)) {
            # Nothing dated after today (a clock that was ahead, restored files) belongs to a page that ends today.
            if ($f.LastWriteTime.Date -lt $windowStart -or $f.LastWriteTime.Date -gt $today) { continue }
            [void]$inPeriod.Add($f)
            $key = _day $f.LastWriteTime
            if ($perDay.ContainsKey($key)) { $perDay[$key]++ } else { $perDay[$key] = 1 }
        }
        $ordered = @($inPeriod | Sort-Object -Property LastWriteTime)
        $truncated = $false
        if ($ordered.Count -gt $MaxSnapshotsPerFarm) {
            $truncated = $true
            Write-Warning -Message "SPSWeather cockpit: farm '$($farmDisplay[$safe])' has $($ordered.Count) snapshots in the period: only the last $MaxSnapshotsPerFarm are read."
            $ordered = @($ordered | Select-Object -Last $MaxSnapshotsPerFarm)
        }

        $series = New-Object -TypeName System.Collections.ArrayList
        foreach ($file in $ordered) {
            $snapshot = $null
            try { $snapshot = _readSnapshot $file.FullName } catch { $snapshot = $null }
            if ($null -eq $snapshot) {
                Write-Warning -Message "SPSWeather cockpit: the snapshot '$($file.Name)' is empty or is not valid JSON and is skipped."
                [void]$skipped.Add($file.Name)
                continue
            }
            $summary = Get-SPSWeatherSnapshotSummary -Snapshot $snapshot
            $idSet = @{}
            foreach ($item in $summary.Items) { $idSet[(Get-SPSWeatherItemIdentity -Section $item.Section -Row $item.Row -IdOnly).Id] = $true }
            # Only the last snapshot is described item by item: let go of the items of the one before.
            if ($series.Count -gt 0) { $series[$series.Count - 1].Items = $null }
            [void]$series.Add([PSCustomObject]@{ Day = (_day $file.LastWriteTime); When = $file.LastWriteTime; Ok = $summary.Ok; Warn = $summary.Warn; Fail = $summary.Fail; IdSet = $idSet; Items = $summary.Items })
            if ($null -eq $earliest -or $file.LastWriteTime.Date -lt $earliest) { $earliest = $file.LastWriteTime.Date }
        }
        $farmSeries[$safe] = $series.ToArray()
        $farmFilesPerDay[$safe] = $perDay
        $farmTruncated[$safe] = $truncated
    }
    foreach ($entry in $runsInPeriod) {
        if ($null -eq $earliest -or $entry.When.LocalDateTime.Date -lt $earliest) { $earliest = $entry.When.LocalDateTime.Date }
    }

    # --- the days of the page ---
    $firstDay = $today
    if ($null -ne $earliest -and $earliest -gt $windowStart) { $firstDay = $earliest }
    elseif ($null -ne $earliest) { $firstDay = $windowStart }
    $days = New-Object -TypeName System.Collections.ArrayList
    $weekend = New-Object -TypeName System.Collections.ArrayList
    for ($d = $firstDay; $d -le $today; $d = $d.AddDays(1)) {
        [void]$days.Add((_day $d))
        [void]$weekend.Add(($d.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $d.DayOfWeek -eq [System.DayOfWeek]::Sunday))
    }

    # The unreachable runs of each farm for each day, from the journal.
    $unreachable = @{}
    foreach ($entry in $runsInPeriod) {
        $day = _day $entry.When.LocalDateTime
        foreach ($farm in @($entry.Run.farms)) {
            if ("$($farm.outcome)" -ne 'unreachable') { continue }
            $key = (_safe "$($farm.name)") + '|' + $day
            if ($unreachable.ContainsKey($key)) { $unreachable[$key]++ } else { $unreachable[$key] = 1 }
        }
    }

    # --- each farm: the daily counts and what needs attention now ---
    $farms = New-Object -TypeName System.Collections.ArrayList
    foreach ($safe in @($farmDisplay.Keys)) {
        $series = @($farmSeries[$safe])
        $perDay = $farmFilesPerDay[$safe]

        # A day is described by the last usable snapshot of that day.
        $daily = New-Object -TypeName System.Collections.ArrayList
        foreach ($day in $days) {
            $index = -1
            for ($i = $series.Count - 1; $i -ge 0; $i--) { if ($series[$i].Day -eq $day) { $index = $i; break } }
            $down = 0
            if ($unreachable.ContainsKey("$safe|$day")) { $down = [int]$unreachable["$safe|$day"] }
            if ($index -ge 0) {
                $s = $series[$index]
                [void]$daily.Add([ordered]@{
                        ok          = $s.Ok
                        warn        = $s.Warn
                        fail        = $s.Fail
                        weather     = (Get-SPSWeatherWeatherKey -Warn $s.Warn -Fail $s.Fail -StormyAbove $stormyAbove)
                        snapshots   = [int]$perDay[$day]
                        unreachable = $down
                    })
            }
            elseif ($down -gt 0) {
                [void]$daily.Add([ordered]@{ ok = $null; warn = $null; fail = $null; weather = $null; snapshots = 0; unreachable = $down })
            }
            else { [void]$daily.Add($null) }
        }

        # What needs attention in the last snapshot, and since when: the first snapshot of the unbroken series of
        # snapshots in which the item also needed attention (a day without snapshot, because the farm was not
        # reached, does not break it).
        $attention = New-Object -TypeName System.Collections.ArrayList
        $latestSnapshot = $null
        if ($series.Count -gt 0) {
            $last = $series.Count - 1
            $latestSnapshot = $series[$last].When.ToString('o', $invariant)
            $latestItems = [ordered]@{}
            foreach ($item in $series[$last].Items) {
                $identity = Get-SPSWeatherItemIdentity -Section $item.Section -Row $item.Row
                if ($latestItems.Contains($identity.Id)) {
                    $latestItems[$identity.Id].count++
                    if ($item.Severity -eq 'fail') { $latestItems[$identity.Id].severity = 'fail' }
                }
                else {
                    $latestItems[$identity.Id] = [ordered]@{ section = $item.Section; id = $identity.Id; name = $identity.Name; severity = $item.Severity; cause = $identity.Cause; detail = $identity.Detail; count = 1 }
                }
            }
            foreach ($id in @($latestItems.Keys)) {
                $first = $last
                while ($first -gt 0 -and $series[$first - 1].IdSet.ContainsKey($id)) { $first-- }
                $item = $latestItems[$id]
                [void]$attention.Add([ordered]@{
                        farm              = $farmDisplay[$safe]
                        section           = $item.section
                        id                = $item.id
                        name              = $item.name
                        severity          = $item.severity
                        cause             = $item.cause
                        detail            = $item.detail
                        count             = $item.count
                        since             = $series[$first].Day
                        sinceIsLowerBound = ($first -eq 0)
                    })
            }
        }
        $sorted = @($attention | Sort-Object -Property @{ Expression = { if ($_.severity -eq 'fail') { 0 } else { 1 } } }, @{ Expression = { $_.since } }, @{ Expression = { $_.id } })
        $total = $sorted.Count
        if ($sorted.Count -gt $MaxItemsPerFarm) { $sorted = @($sorted | Select-Object -First $MaxItemsPerFarm) }

        [void]$farms.Add([ordered]@{
                name               = $farmDisplay[$safe]
                daily              = $daily.ToArray()
                latestSnapshot     = $latestSnapshot
                snapshotsTruncated = $farmTruncated[$safe]
                attention          = $sorted
                attentionTotal     = $total
                attentionTruncated = ($total -gt $sorted.Count)
            })
    }

    # --- what changed in the settings between two records ---
    $changes = New-Object -TypeName System.Collections.ArrayList
    $current = $null
    $previous = $null
    foreach ($entry in $runsInPeriod) {
        $setting = $entry.Run.PSObject.Properties['settings']
        if ($null -eq $setting -or $null -eq $setting.Value) {
            # The settings of this run are not known (an older journal, an older version): nothing is compared across
            # it, and the last known settings stay the current ones.
            $previous = $null
            continue
        }
        $current = $setting.Value
        if ($null -ne $previous) {
            $record = {
                param([string]$name, $from, $to, $fromSource, $toSource)
                [void]$changes.Add([ordered]@{ started = "$($entry.Run.started)"; name = $name; from = $from; to = $to; fromSource = $fromSource; toSource = $toSource })
            }
            if ("$($previous.configFile)" -ne "$($current.configFile)") { & $record 'configFile' "$($previous.configFile)" "$($current.configFile)" $null $null }
            $names = @(@($previous.thresholds.PSObject.Properties.Name) + @($current.thresholds.PSObject.Properties.Name) | Select-Object -Unique)
            foreach ($name in $names) {
                $a = $previous.thresholds.PSObject.Properties[$name]
                $b = $current.thresholds.PSObject.Properties[$name]
                $aValue = if ($null -ne $a) { "$($a.Value.value)" } else { $null }
                $bValue = if ($null -ne $b) { "$($b.Value.value)" } else { $null }
                $aSource = if ($null -ne $a) { "$($a.Value.source)" } else { $null }
                $bSource = if ($null -ne $b) { "$($b.Value.source)" } else { $null }
                if ($aValue -ne $bValue -or $aSource -ne $bSource) { & $record $name $aValue $bValue $aSource $bSource }
            }
            $aRules = (@($previous.exclusionRules) | Sort-Object) -join ','
            $bRules = (@($current.exclusionRules) | Sort-Object) -join ','
            if ($aRules -ne $bRules) { & $record 'exclusionRules' $aRules $bRules $null $null }
        }
        $previous = $current
    }
    $changeList = @($changes)
    if ($changeList.Count -gt 100) { $changeList = @($changeList | Select-Object -Last 100) }

    return [ordered]@{
        schemaVersion = 1
        generatedAt   = ([System.DateTimeOffset]$Now).ToString('o', $invariant)
        environment   = [ordered]@{ application = $Application; name = $Environment }
        period        = [ordered]@{
            retentionDays = [int]$RetentionDays
            offered       = @($offered)
            maxDays       = $maxDays
            firstDay      = $days[0]
            lastDay       = $days[$days.Count - 1]
        }
        rules         = [ordered]@{ weather = [ordered]@{ stormyAbove = $stormyAbove } }
        days          = $days.ToArray()
        weekend       = $weekend.ToArray()
        farms         = $farms.ToArray()
        runs          = @($runsInPeriod | ForEach-Object -Process { $_.Run })
        settings      = [ordered]@{ current = $current; changes = $changeList }
        skipped       = @($skipped | Select-Object -First 20)
        kpi           = $null
    }
}
