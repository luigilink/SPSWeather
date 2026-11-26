# Behavioural tests for Get-SPSWeatherCockpitData (private): the one dataset of the multi-farm page,
# built from the history, the snapshots and the run journal that the runs leave in Results.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force

    $script:now = [datetime]'2026-11-26T09:00:00'

    function script:New-Results {
        $root = Join-Path -Path $TestDrive -ChildPath ('res-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        $root
    }

    # A snapshot with a number of failures, warnings and OK checks, each failure a database of its own.
    function script:New-Snap {
        param([int]$Fail = 0, [int]$Warn = 0, [int]$Ok = 0, [string]$Cause = 'last full backup 4.5 d ago')
        $rows = @()
        foreach ($i in 1..$Fail) { if ($Fail -gt 0) { $rows += [PSCustomObject]@{ Farm = 'F'; SqlServer = 'SQL1'; Name = "DB$i"; Recommendation = $Cause; IsInfo = $false } } }
        foreach ($i in 1..$Warn) { if ($Warn -gt 0) { $rows += [PSCustomObject]@{ Farm = 'F'; SqlServer = 'SQL1'; Name = "WARN$i"; Recommendation = 'MAXDOP should be 1'; IsInfo = $true } } }
        $snap = [PSCustomObject]@{}
        if ($rows.Count -gt 0) { $snap | Add-Member -MemberType NoteProperty -Name SQLDatabaseStatus -Value $rows }
        $oks = @()
        foreach ($i in 1..$Ok) { if ($Ok -gt 0) { $oks += [PSCustomObject]@{ Farm = 'F'; Server = "S$i"; Status = 'OK'; IsInfo = $true } } }
        if ($oks.Count -gt 0) { $snap | Add-Member -MemberType NoteProperty -Name SPUpgradeStatus -Value $oks }
        $snap
    }

    # Writes a snapshot where a run leaves it: the history folder, or Results for the last run.
    function script:Add-Snap {
        param($Results, [string]$Farm, [datetime]$When, $Snapshot, [switch]$Current, [string]$Raw)
        $safe = $Farm -replace '[^A-Za-z0-9_-]', '_'
        if ($Current) { $file = Join-Path -Path $Results -ChildPath "zebes-PROD-$safe.json" }
        else {
            $folder = Join-Path -Path $Results -ChildPath "history/$safe"
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
            $file = Join-Path -Path $folder -ChildPath ("zebes-PROD-$safe-" + $When.ToString('yyyyMMdd-HHmm') + '.json')
        }
        if ($PSBoundParameters.ContainsKey('Raw')) { [System.IO.File]::WriteAllText($file, $Raw) }
        else { [System.IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $Snapshot -Depth 6)) }
        (Get-Item -LiteralPath $file).LastWriteTime = $When
        $file
    }

    function script:Add-Run {
        param($Results, [datetime]$Started, $Farm = @(), $Setting = $null, [string]$Mail = 'sent')
        $arguments = @{ Path = (Join-Path -Path $Results -ChildPath 'zebes-PROD.runs.json'); Started = $Started; Duration = [timespan]::FromSeconds(60); Version = '3.5.0'; Language = 'en-US'; EmailMode = 'PerFarm'; Mail = $Mail; Farm = $Farm }
        if ($null -ne $Setting) { $arguments['Setting'] = $Setting }
        [void](Add-SPSWeatherRunJournalEntry @arguments)
    }

    function script:Get-Data {
        param($Results, [string[]]$Farm, [uint32]$Retention = 30, [datetime]$Now = $script:now, [int]$MaxItems = 300)
        InModuleScope SPSWeather.Common -Parameters @{ R = $Results; F = $Farm; Ret = $Retention; N = $Now; M = $MaxItems } {
            param($R, $F, $Ret, $N, $M)
            $w = @()
            $data = Get-SPSWeatherCockpitData -ResultsFolder $R -Application 'zebes' -Environment 'PROD' -FarmName $F -RetentionDays $Ret -Now $N -MaxItemsPerFarm $M -WarningVariable w -WarningAction SilentlyContinue
            [PSCustomObject]@{ Data = $data; Warnings = @($w) }
        }
    }

    function script:Get-Farm { param($Data, [string]$Name) @($Data.farms | Where-Object { $_.name -eq $Name })[0] }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSWeatherCockpitData' {
    Context 'nothing to read' {
        It 'returns an empty but complete dataset when Results does not exist' {
            $r = Get-Data -Results (Join-Path -Path $TestDrive -ChildPath 'nope') -Farm 'CONTENT'
            $r.Data.schemaVersion | Should -Be 1
            @($r.Data.days) | Should -Be @('2026-11-26')
            @($r.Data.farms).Count | Should -Be 1
            @((Get-Farm $r.Data 'CONTENT').daily).Count | Should -Be 1
            (Get-Farm $r.Data 'CONTENT').daily[0] | Should -BeNullOrEmpty
            @($r.Data.runs).Count | Should -Be 0
            $r.Data.kpi | Should -BeNullOrEmpty
            $r.Warnings.Count | Should -Be 0
        }

        It 'returns no farm when none is configured and nothing is found' {
            @((Get-Data -Results (New-Results)).Data.farms).Count | Should -Be 0
        }

        It 'carries the environment, the generation time and the reserved kpi section' {
            $r = (Get-Data -Results (New-Results)).Data
            $r.environment.application | Should -Be 'zebes'
            $r.environment.name | Should -Be 'PROD'
            $r.generatedAt | Should -Match '^2026-11-26T09:00:00'
            $r.PSObject.Properties.Name | Should -Not -BeNullOrEmpty
            $r.Contains('kpi') | Should -BeTrue
            $r['kpi'] | Should -BeNullOrEmpty
        }
    }

    Context 'the periods' {
        It 'offers <Expected> for a retention of <Retention> days' -ForEach @(
            @{ Retention = 0; Expected = @(7, 14, 30, 60) }
            @{ Retention = 30; Expected = @(7, 14, 30) }
            @{ Retention = 60; Expected = @(7, 14, 30, 60) }
            @{ Retention = 90; Expected = @(7, 14, 30, 60) }
            @{ Retention = 14; Expected = @(7, 14) }
            @{ Retention = 7; Expected = @(7) }
            @{ Retention = 5; Expected = @(5) }
            @{ Retention = 1; Expected = @(1) }
        ) {
            $r = (Get-Data -Results (New-Results) -Retention $Retention).Data
            @($r.period.offered) | Should -Be $Expected
            $r.period.maxDays | Should -Be ($Expected | Measure-Object -Maximum).Maximum
            $r.period.retentionDays | Should -Be $Retention
        }

        It 'does not read the history beyond the longest period offered' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-20) -Snapshot (New-Snap -Fail 1))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-5) -Snapshot (New-Snap -Fail 2))
            $r = (Get-Data -Results $res -Farm 'CONTENT' -Retention 7).Data
            @($r.days).Count | Should -Be 6
            $r.days[0] | Should -Be '2026-11-21'
            (Get-Farm $r 'CONTENT').daily[0].fail | Should -Be 2
        }

        It 'never deletes or changes a file, whatever the retention' {
            $res = New-Results
            $old = Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-45) -Snapshot (New-Snap -Fail 1)
            [void](Get-Data -Results $res -Farm 'CONTENT' -Retention 7)
            Test-Path -LiteralPath $old | Should -BeTrue
        }
    }

    Context 'the days and the counts of a farm' {
        BeforeAll {
            $script:res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-4).AddHours(-1) -Snapshot (New-Snap -Ok 10))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-3).AddHours(-1) -Snapshot (New-Snap -Ok 10 -Warn 2))
            # day -2: nothing (a gap)
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-1).AddHours(-1) -Snapshot (New-Snap -Ok 10 -Fail 3))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Ok 10 -Fail 8) -Current)
            $script:data = (Get-Data -Results $res -Farm 'CONTENT').Data
            $script:farm = Get-Farm $data 'CONTENT'
        }

        It 'lists one day per calendar day from the first day with data to today' {
            @($data.days) | Should -Be @('2026-11-22', '2026-11-23', '2026-11-24', '2026-11-25', '2026-11-26')
            $data.period.firstDay | Should -Be '2026-11-22'
            $data.period.lastDay | Should -Be '2026-11-26'
        }

        It 'marks the weekend days' {
            @($data.weekend) | Should -Be @($true, $false, $false, $false, $false)
        }

        It 'aligns the daily entries with the days, with $null for a day without any information' {
            @($farm.daily).Count | Should -Be @($data.days).Count
            $farm.daily[2] | Should -BeNullOrEmpty
        }

        It 'counts OK, warnings and failures of the snapshot of each day, and gives the weather' {
            $farm.daily[0].ok | Should -Be 10
            $farm.daily[0].fail | Should -Be 0
            $farm.daily[0].warn | Should -Be 0
            $farm.daily[0].weather | Should -Be 'sunny'
            $farm.daily[1].warn | Should -Be 2
            $farm.daily[1].weather | Should -Be 'fair'
            $farm.daily[3].fail | Should -Be 3
            $farm.daily[3].weather | Should -Be 'cloudy'
            $farm.daily[4].fail | Should -Be 8
            $farm.daily[4].weather | Should -Be 'stormy'
        }

        It 'reads the snapshot of the last run (in Results) as today' {
            $farm.latestSnapshot | Should -Match '^2026-11-26T08:00:00'
        }

        It 'gives the weather rule so that the page can say how it is computed' {
            $data.rules.weather.stormyAbove | Should -Be 5
        }
    }

    Context 'a day with several runs' {
        It 'uses the last snapshot of the day and says how many there were' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-6) -Snapshot (New-Snap -Fail 9))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-3) -Snapshot (New-Snap -Fail 2))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 1) -Current)
            $entry = (Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').daily[0]
            $entry.fail | Should -Be 1
            $entry.snapshots | Should -Be 3
        }
    }

    Context 'the farms' {
        It 'lists the configured farms in their order, then the farms that only the history or the journal knows' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'ZETA' -When $now.AddHours(-1) -Snapshot (New-Snap -Ok 1))
            [void](Add-Snap -Results $res -Farm 'ALPHA' -When $now.AddHours(-1) -Snapshot (New-Snap -Ok 1))
            Add-Run -Results $res -Started $now.AddHours(-1) -Farm @([PSCustomObject]@{ Name = 'GAMMA'; Outcome = 'unreachable' })
            $names = @((Get-Data -Results $res -Farm 'SEARCH', 'CONTENT').Data.farms | ForEach-Object { $_.name })
            $names | Should -Be @('SEARCH', 'CONTENT', 'GAMMA', 'ALPHA', 'ZETA')
        }

        It 'keeps the real name of a farm whose name is not a valid file name' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'Ferme "Été" <1>' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 1))
            $farm = Get-Farm (Get-Data -Results $res -Farm 'Ferme "Été" <1>').Data 'Ferme "Été" <1>'
            $farm.daily[0].fail | Should -Be 1
            @($farm.attention)[0].farm | Should -Be 'Ferme "Été" <1>'
        }

        It 'shows no farm twice when the configuration, the history and the journal all know it' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Ok 1))
            Add-Run -Results $res -Started $now.AddHours(-1) -Farm @([PSCustomObject]@{ Name = 'CONTENT'; Outcome = 'ok'; Ok = 1; Warn = 0; Fail = 0 })
            @((Get-Data -Results $res -Farm 'CONTENT').Data.farms).Count | Should -Be 1
        }
    }

    Context 'an unreachable farm' {
        It 'shows the unreachable runs of a farm that left no snapshot' {
            $res = New-Results
            Add-Run -Results $res -Started $now.AddHours(-1) -Farm @([PSCustomObject]@{ Name = 'SERVICES'; Outcome = 'unreachable' }) -Mail 'none'
            Add-Run -Results $res -Started $now.AddHours(-2) -Farm @([PSCustomObject]@{ Name = 'SERVICES'; Outcome = 'unreachable' }) -Mail 'none'
            $entry = (Get-Farm (Get-Data -Results $res -Farm 'SERVICES').Data 'SERVICES').daily[0]
            $entry.unreachable | Should -Be 2
            $entry.snapshots | Should -Be 0
            $entry.ok | Should -BeNullOrEmpty
            $entry.weather | Should -BeNullOrEmpty
        }

        It 'counts the unreachable runs of a day on which the farm also has a snapshot' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'SERVICES' -When $now.AddHours(-5) -Snapshot (New-Snap -Ok 4))
            Add-Run -Results $res -Started $now.AddHours(-1) -Farm @([PSCustomObject]@{ Name = 'SERVICES'; Outcome = 'unreachable' })
            $entry = (Get-Farm (Get-Data -Results $res -Farm 'SERVICES').Data 'SERVICES').daily[0]
            $entry.ok | Should -Be 4
            $entry.unreachable | Should -Be 1
        }

        It 'does not count a reachable run as unreachable' {
            $res = New-Results
            Add-Run -Results $res -Started $now.AddHours(-1) -Farm @([PSCustomObject]@{ Name = 'CONTENT'; Outcome = 'ok'; Ok = 3; Warn = 0; Fail = 0 })
            (Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').daily[0] | Should -BeNullOrEmpty
        }
    }

    Context 'what needs attention' {
        It 'says since when an item needs attention, and that an item that was fixed in between starts again' {
            $res = New-Results
            $failing = New-Snap -Fail 1
            $fixed = New-Snap -Ok 1
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-5).AddHours(-1) -Snapshot $failing)
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-4).AddHours(-1) -Snapshot $fixed)
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-3).AddHours(-1) -Snapshot $failing)
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-2).AddHours(-1) -Snapshot $failing)
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot $failing -Current)
            $item = @((Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').attention)[0]
            $item.since | Should -Be '2026-11-23'
            $item.sinceIsLowerBound | Should -BeFalse
            $item.severity | Should -Be 'fail'
        }

        It 'flags a series that starts at the oldest snapshot read as a lower bound' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-2).AddHours(-1) -Snapshot (New-Snap -Fail 1))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 1) -Current)
            $item = @((Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').attention)[0]
            $item.since | Should -Be '2026-11-24'
            $item.sinceIsLowerBound | Should -BeTrue
        }

        It 'does not let a day without snapshot (farm not reached) break the series' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-4).AddHours(-1) -Snapshot (New-Snap -Fail 1))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-1).AddHours(-1) -Snapshot (New-Snap -Fail 1))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 1) -Current)
            @((Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').attention)[0].since | Should -Be '2026-11-22'
        }

        It 'follows an item although its figures and its state change from one run to the next' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-2).AddHours(-1) -Snapshot (New-Snap -Fail 1 -Cause 'last full backup 4.5 d ago'))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-1).AddHours(-1) -Snapshot (New-Snap -Fail 1 -Cause 'last full backup 5.5 d ago'))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 1 -Cause 'no full backup found') -Current)
            $items = @((Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').attention)
            $items.Count | Should -Be 1
            $items[0].since | Should -Be '2026-11-24'
            $items[0].detail | Should -Be 'no full backup found'
        }

        It 'lists the items of the last snapshot only, failures first, then the oldest, with name, cause and detail' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-3).AddHours(-1) -Snapshot (New-Snap -Fail 1))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 2 -Warn 1) -Current)
            $items = @((Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').attention)
            $items.Count | Should -Be 3
            @($items | ForEach-Object { $_.severity }) | Should -Be @('fail', 'fail', 'warn')
            $items[0].name | Should -Be 'SQL1 / DB1'
            $items[0].since | Should -Be '2026-11-23'
            $items[1].name | Should -Be 'SQL1 / DB2'
            $items[1].since | Should -Be '2026-11-26'
            $items[0].cause | Should -Be 'last full backup # d ago'
            $items[2].detail | Should -Be 'MAXDOP should be 1'
            $items[0].section | Should -Be 'SQLDatabaseStatus'
            $items[0].farm | Should -Be 'CONTENT'
        }

        It 'lists nothing for a farm without snapshot, and nothing when everything is fine' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Ok 5) -Current)
            $data = (Get-Data -Results $res -Farm 'CONTENT', 'SEARCH').Data
            @((Get-Farm $data 'CONTENT').attention).Count | Should -Be 0
            @((Get-Farm $data 'SEARCH').attention).Count | Should -Be 0
            (Get-Farm $data 'SEARCH').latestSnapshot | Should -BeNullOrEmpty
        }

        It 'caps the list, keeps the total and says that it was cut' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 12) -Current)
            $farm = Get-Farm (Get-Data -Results $res -Farm 'CONTENT' -MaxItems 5).Data 'CONTENT'
            @($farm.attention).Count | Should -Be 5
            $farm.attentionTotal | Should -Be 12
            $farm.attentionTruncated | Should -BeTrue
        }

        It 'merges identical rows into one item and counts them' {
            $res = New-Results
            $snap = [PSCustomObject]@{ SQLDatabaseStatus = @(
                    [PSCustomObject]@{ Farm = 'F'; SqlServer = 'SQL1'; Name = 'DB1'; Recommendation = 'x'; IsInfo = $true }
                    [PSCustomObject]@{ Farm = 'F'; SqlServer = 'SQL1'; Name = 'DB1'; Recommendation = 'x'; IsInfo = $false }) }
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot $snap -Current)
            $items = @((Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').attention)
            $items.Count | Should -Be 1
            $items[0].count | Should -Be 2
            $items[0].severity | Should -Be 'fail'
        }

        It 'keeps the detail on one line of 200 characters at most' {
            $res = New-Results
            $snap = New-Snap -Fail 1 -Cause (("long`r`nmessage " * 40))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot $snap -Current)
            $detail = @((Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').attention)[0].detail
            $detail.Length | Should -BeLessOrEqual 200
            $detail | Should -Not -Match '[\r\n]'
        }
    }

    Context 'files that cannot be used' {
        It 'skips a snapshot that is not valid JSON, says so, and keeps the others' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-2).AddHours(-1) -Snapshot (New-Snap -Fail 1))
            $bad = Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-1).AddHours(-1) -Raw '{ not json'
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 2) -Current)
            $r = Get-Data -Results $res -Farm 'CONTENT'
            $farm = Get-Farm $r.Data 'CONTENT'
            $farm.daily[0].fail | Should -Be 1
            $farm.daily[1] | Should -BeNullOrEmpty
            $farm.daily[2].fail | Should -Be 2
            @($r.Data.skipped) | Should -Contain (Split-Path -Path $bad -Leaf)
            ($r.Warnings -join ' ') | Should -Match 'not valid JSON'
        }

        It 'skips an empty snapshot and a snapshot that is not an object (<Name>)' -ForEach @(
            @{ Name = 'empty'; Raw = '' }
            @{ Name = 'blank'; Raw = "  `r`n" }
            @{ Name = 'array'; Raw = '[1,2]' }
            @{ Name = 'number'; Raw = '42' }
            @{ Name = 'string'; Raw = '"x"' }
            @{ Name = 'null'; Raw = 'null' }
        ) {
            $res = New-Results
            $file = Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Raw $Raw
            $r = Get-Data -Results $res -Farm 'CONTENT'
            (Get-Farm $r.Data 'CONTENT').daily[0] | Should -BeNullOrEmpty
            @($r.Data.skipped) | Should -Contain (Split-Path -Path $file -Leaf)
            $r.Warnings.Count | Should -BeGreaterThan 0
        }

        It 'ignores a run journal that cannot be read, says so, and still builds the dataset' {
            $res = New-Results
            [System.IO.File]::WriteAllText((Join-Path -Path $res -ChildPath 'zebes-PROD.runs.json'), '{ not json')
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Ok 2) -Current)
            $r = Get-Data -Results $res -Farm 'CONTENT'
            @($r.Data.runs).Count | Should -Be 0
            (Get-Farm $r.Data 'CONTENT').daily[0].ok | Should -Be 2
            @($r.Data.skipped) | Should -Contain 'zebes-PROD.runs.json'
            ($r.Warnings -join ' ') | Should -Match 'run journal'
        }

        It 'reports at most 20 skipped files' {
            $res = New-Results
            foreach ($i in 1..25) { [void](Add-Snap -Results $res -Farm "FARM$i" -When $now.AddHours(-1) -Raw '{') }
            @((Get-Data -Results $res).Data.skipped).Count | Should -Be 20
        }
    }

    Context 'the run journal and the settings' {
        BeforeAll {
            $script:setting1 = (Get-SPSWeatherRunSetting -Config @{ SQLBackupMaxAgeDays = 3; ExclusionRules = @('WSPStatus') } -ConfigFile 'prod.psd1').Record
            $script:setting2 = (Get-SPSWeatherRunSetting -Config @{ SQLBackupMaxAgeDays = 8; ExclusionRules = @('WSPStatus') } -ConfigFile 'prod.psd1').Record
            $script:setting3 = (Get-SPSWeatherRunSetting -Config @{ SQLBackupMaxAgeDays = 8; SQLDiskFreeThresholdPercent = 20; ExclusionRules = @('SQLDiskStatus', 'WSPStatus') } -ConfigFile 'other.psd1').Record
        }

        It 'gives the records of the journal inside the period, oldest first' {
            $res = New-Results
            Add-Run -Results $res -Started $now.AddDays(-80)
            Add-Run -Results $res -Started $now.AddDays(-2) -Mail 'failed'
            Add-Run -Results $res -Started $now.AddDays(-1) -Mail 'sent'
            $runs = @((Get-Data -Results $res -Retention 30).Data.runs)
            $runs.Count | Should -Be 2
            $runs[0].mail | Should -Be 'failed'
            $runs[1].mail | Should -Be 'sent'
            $runs[1].version | Should -Be '3.5.0'
            $runs[1].durationSeconds | Should -Be 60
        }

        It 'gives the settings of the last record that has some' {
            $res = New-Results
            Add-Run -Results $res -Started $now.AddDays(-2) -Setting $setting1
            Add-Run -Results $res -Started $now.AddDays(-1) -Setting $setting2
            Add-Run -Results $res -Started $now.AddHours(-1)
            $current = (Get-Data -Results $res).Data.settings.current
            $current.thresholds.SQLBackupMaxAgeDays.value | Should -Be 8
            $current.configFile | Should -Be 'prod.psd1'
        }

        It 'says what changed between two records: a threshold, its source, the exclusions, the file' {
            $res = New-Results
            Add-Run -Results $res -Started $now.AddDays(-3) -Setting $setting1
            Add-Run -Results $res -Started $now.AddDays(-2) -Setting $setting2
            Add-Run -Results $res -Started $now.AddDays(-1) -Setting $setting3
            $changes = @((Get-Data -Results $res).Data.settings.changes)
            $backup = @($changes | Where-Object { $_.name -eq 'SQLBackupMaxAgeDays' })
            $backup.Count | Should -Be 1
            $backup[0].from | Should -Be '3'
            $backup[0].to | Should -Be '8'
            $backup[0].fromSource | Should -Be 'config'
            $backup[0].started | Should -Match '^2026-11-24'
            $disk = @($changes | Where-Object { $_.name -eq 'SQLDiskFreeThresholdPercent' })
            $disk.Count | Should -Be 1
            $disk[0].fromSource | Should -Be 'default'
            $disk[0].toSource | Should -Be 'config'
            @($changes | Where-Object { $_.name -eq 'exclusionRules' }).Count | Should -Be 1
            @($changes | Where-Object { $_.name -eq 'configFile' }).Count | Should -Be 1
        }

        It 'reports no change when the settings stay the same' {
            $res = New-Results
            Add-Run -Results $res -Started $now.AddDays(-2) -Setting $setting2
            Add-Run -Results $res -Started $now.AddDays(-1) -Setting $setting2
            @((Get-Data -Results $res).Data.settings.changes).Count | Should -Be 0
        }

        It 'does not invent a change around the records that have no settings (an older journal)' {
            $res = New-Results
            Add-Run -Results $res -Started $now.AddDays(-3)
            Add-Run -Results $res -Started $now.AddDays(-2) -Setting $setting2
            Add-Run -Results $res -Started $now.AddDays(-1)
            Add-Run -Results $res -Started $now.AddHours(-1) -Setting $setting2
            @((Get-Data -Results $res).Data.settings.changes).Count | Should -Be 0
        }

        It 'has no current settings and no change for a journal without settings' {
            $res = New-Results
            Add-Run -Results $res -Started $now.AddHours(-1)
            $s = (Get-Data -Results $res).Data.settings
            $s.current | Should -BeNullOrEmpty
            @($s.changes).Count | Should -Be 0
        }
    }

    Context 'agreement with the other readers of a snapshot' {
        It 'counts exactly like the report of the run (ConvertTo-SPSWeatherReport) once the snapshot is archived' {
            $res = New-Results
            $sections = [ordered]@{
                SPAPIHttpStatus  = @([PSCustomObject]@{ Farm = 'CONTENT'; Title = 'A'; Url = 'u'; Status = 'OK'; IsInfo = $true }, [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'B'; Url = 'v'; Status = 'Failed'; IsInfo = $false })
                SPHealthAnalyzer = @([PSCustomObject]@{ farm = 'CONTENT'; title = 'T1'; severity = '2 - Warning'; category = 'Configuration' }, [PSCustomObject]@{ farm = 'CONTENT'; title = 'T2'; severity = '1 - Error'; category = 'Availability' })
                SYSLastRebootStatus = @([PSCustomObject]@{ Farm = 'CONTENT'; Server = 'S1'; LastRebootTime = 'x' })
                SQLDatabaseStatus = @([PSCustomObject]@{ Farm = 'CONTENT'; SqlServer = 'SQL1'; Name = 'DB1'; Recommendation = 'AutoShrink ON'; IsInfo = $true }, [PSCustomObject]@{ Farm = 'CONTENT'; SqlServer = 'SQL1'; Name = 'DB2'; Recommendation = ''; IsInfo = $true })
            }
            $result = ConvertTo-SPSWeatherReport -Section $sections
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot $result.Report -Current)
            $entry = (Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').daily[0]
            $entry.ok | Should -Be $result.Summary.Ok
            $entry.warn | Should -Be $result.Summary.Warn
            $entry.fail | Should -Be $result.Summary.Fail
            $result.Summary.Ok | Should -BeGreaterThan 0
            $result.Summary.Warn | Should -BeGreaterThan 0
            $result.Summary.Fail | Should -BeGreaterThan 0
        }

        It 'counts exactly like the bars of the dashboard (Get-SPSWeatherHistory)' {
            $res = New-Results
            $folder = Join-Path -Path $res -ChildPath 'history/CONTENT'
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-2) -Snapshot (New-Snap -Ok 7 -Warn 2 -Fail 3))
            $bars = @(Get-SPSWeatherHistory -HistoryFolder $folder)
            $entry = (Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').daily[0]
            $entry.ok | Should -Be $bars[0].Ok
            $entry.warn | Should -Be $bars[0].Warn
            $entry.fail | Should -Be $bars[0].Fail
        }
    }

    Context 'the form of the dataset' {
        It 'serialises to JSON and back with every list still a list (one day, one farm, one item, one period)' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 1) -Current)
            $data = (Get-Data -Results $res -Farm 'CONTENT' -Retention 7).Data
            $json = ConvertTo-Json -InputObject $data -Depth 12
            $back = ConvertFrom-Json -InputObject $json
            $json | Should -Match '"days":\s*\['
            $json | Should -Match '"offered":\s*\['
            $json | Should -Match '"farms":\s*\['
            $json | Should -Match '"attention":\s*\['
            $json | Should -Match '"daily":\s*\['
            $json | Should -Match '"kpi":\s*null'
            @($back.days).Count | Should -Be 1
            @($back.period.offered) | Should -Be @(7)
            @($back.farms[0].attention).Count | Should -Be 1
        }

        It 'only holds text, numbers, booleans, lists and objects (nothing the page cannot read)' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 1) -Current)
            Add-Run -Results $res -Started $now.AddHours(-1) -Farm @([PSCustomObject]@{ Name = 'CONTENT'; Outcome = 'ok'; Ok = 1; Warn = 0; Fail = 1 })
            $json = ConvertTo-Json -InputObject (Get-Data -Results $res -Farm 'CONTENT').Data -Depth 12
            $json | Should -Not -Match 'System\.'
            $json | Should -Not -Match '"DateTime"|"value":\s*\{[^}]*"Ticks"'
        }

        It 'keeps the text of the snapshots as data: escaping is the job of the page that shows it' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 1 -Cause '</script><img src=x onerror=alert(1)>') -Current)
            $item = @((Get-Farm (Get-Data -Results $res -Farm 'CONTENT').Data 'CONTENT').attention)[0]
            $item.detail | Should -Be '</script><img src=x onerror=alert(1)>'
        }

        It 'never writes or changes a file of Results' {
            $res = New-Results
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddDays(-1) -Snapshot (New-Snap -Fail 1))
            [void](Add-Snap -Results $res -Farm 'CONTENT' -When $now.AddHours(-1) -Snapshot (New-Snap -Fail 1) -Current)
            Add-Run -Results $res -Started $now.AddHours(-1)
            $before = @(Get-ChildItem -Path $res -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTime.Ticks)" })
            [void](Get-Data -Results $res -Farm 'CONTENT')
            $after = @(Get-ChildItem -Path $res -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTime.Ticks)" })
            $after | Should -Be $before
        }
    }
}
