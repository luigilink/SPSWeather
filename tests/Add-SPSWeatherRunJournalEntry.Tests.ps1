# Behavioural tests for the run journal (Add-SPSWeatherRunJournalEntry and its private reader).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force

    function script:New-Entry {
        param ($Path, [datetime]$Started = (Get-Date), [string]$Mail = 'sent', $Farm, [uint32]$RetentionDays = 0, [int]$MaxEntries = 1000)
        if ($null -eq $Farm) { $Farm = @([PSCustomObject]@{ Name = 'CONTENT'; Outcome = 'ok'; Ok = 119; Warn = 1; Fail = 3 }) }
        Add-SPSWeatherRunJournalEntry -Path $Path -Started $Started -Duration ([timespan]::FromSeconds(172.4)) `
            -Version '3.5.0' -Language 'fr-FR' -EmailMode 'Consolidated' -Mail $Mail -Farm $Farm `
            -RetentionDays $RetentionDays -MaxEntries $MaxEntries -WarningAction SilentlyContinue
    }

    function script:Read-Journal {
        param ($Path)
        [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
    }

    # The 'started' strings exactly as written: ConvertFrom-Json turns them into [datetime] on PowerShell 7.
    function script:Get-StartedText {
        param ($Path)
        @([regex]::Matches([System.IO.File]::ReadAllText($Path), '"started":\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Add-SPSWeatherRunJournalEntry' {
    Context 'the record' {
        It 'creates the journal (and its folder) on the first run and returns $true' {
            $file = Join-Path -Path $TestDrive -ChildPath 'first/zebes-PROD-runs.json'
            New-Entry -Path $file | Should -BeTrue
            Test-Path -Path $file | Should -BeTrue
        }

        It 'writes the schema version and one record with the documented fields' {
            $file = Join-Path -Path $TestDrive -ChildPath 'fields-runs.json'
            $started = [datetime]'2026-11-26T08:30:01'
            New-Entry -Path $file -Started $started | Out-Null

            $journal = Read-Journal -Path $file
            $journal.schemaVersion | Should -Be 1
            @($journal.runs).Count | Should -Be 1
            $run = @($journal.runs)[0]
            $run.durationSeconds | Should -Be 172
            $run.version | Should -Be '3.5.0'
            $run.language | Should -Be 'fr-FR'
            $run.emailMode | Should -Be 'Consolidated'
            $run.mail | Should -Be 'sent'
            Get-StartedText -Path $file | Should -Match '^2026-11-26T08:30:01'
        }

        It 'records the counts of a collected farm and nulls for an unreachable one' {
            $file = Join-Path -Path $TestDrive -ChildPath 'farms-runs.json'
            $farms = @(
                [PSCustomObject]@{ Name = 'CONTENT'; Outcome = 'ok'; Ok = 119; Warn = 1; Fail = 33 }
                [PSCustomObject]@{ Name = 'SERVICES'; Outcome = 'unreachable' }
            )
            New-Entry -Path $file -Farm $farms | Out-Null

            $run = @((Read-Journal -Path $file).runs)[0]
            @($run.farms).Count | Should -Be 2
            $run.farms[0].name | Should -Be 'CONTENT'
            $run.farms[0].outcome | Should -Be 'ok'
            $run.farms[0].ok | Should -Be 119
            $run.farms[0].warn | Should -Be 1
            $run.farms[0].fail | Should -Be 33
            $run.farms[1].name | Should -Be 'SERVICES'
            $run.farms[1].outcome | Should -Be 'unreachable'
            $run.farms[1].ok | Should -BeNullOrEmpty
            $run.farms[1].fail | Should -BeNullOrEmpty
        }

        It 'records a run where every farm is unreachable' {
            $file = Join-Path -Path $TestDrive -ChildPath 'allfail-runs.json'
            $farms = @([PSCustomObject]@{ Name = 'CONTENT'; Outcome = 'unreachable' })
            New-Entry -Path $file -Farm $farms -Mail 'none' | Should -BeTrue
            $run = @((Read-Journal -Path $file).runs)[0]
            $run.mail | Should -Be 'none'
            $run.farms[0].outcome | Should -Be 'unreachable'
        }

        It 'keeps the farms list as an array when there is a single farm or none' {
            $file = Join-Path -Path $TestDrive -ChildPath 'array-runs.json'
            New-Entry -Path $file | Out-Null
            New-Entry -Path $file -Farm @() | Out-Null
            $raw = [System.IO.File]::ReadAllText($file)
            $raw | Should -Match '"farms":\s*\[\s*\{'
            $raw | Should -Match '"farms":\s*\[\s*\]'
        }

        It 'keeps accents and special characters of a farm name' {
            $file = Join-Path -Path $TestDrive -ChildPath 'utf8-runs.json'
            New-Entry -Path $file -Farm @([PSCustomObject]@{ Name = 'Ferme "Été" <1>'; Outcome = 'ok'; Ok = 1; Warn = 0; Fail = 0 }) | Out-Null
            @((Read-Journal -Path $file).runs)[0].farms[0].name | Should -Be 'Ferme "Été" <1>'
        }

        It 'writes UTF-8 without a byte order mark' {
            $file = Join-Path -Path $TestDrive -ChildPath 'bom-runs.json'
            New-Entry -Path $file | Out-Null
            $bytes = [System.IO.File]::ReadAllBytes($file)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        }

        It 'rejects a mail outcome or an email mode that the journal does not know' {
            $file = Join-Path -Path $TestDrive -ChildPath 'validate-runs.json'
            { New-Entry -Path $file -Mail 'maybe' } | Should -Throw
        }

        It 'returns $false with a warning, and does not throw, for a farm with an unknown outcome' {
            $file = Join-Path -Path $TestDrive -ChildPath 'badfarm-runs.json'
            $farms = @([PSCustomObject]@{ Name = 'CONTENT'; Outcome = 'exploded' })
            New-Entry -Path $file -Farm $farms | Should -BeFalse
            Test-Path -Path $file | Should -BeFalse
        }
    }

    Context 'appending and pruning' {
        It 'appends the new record after the existing ones' {
            $file = Join-Path -Path $TestDrive -ChildPath 'append-runs.json'
            New-Entry -Path $file -Started ([datetime]'2026-11-24T08:30:00') | Out-Null
            New-Entry -Path $file -Started ([datetime]'2026-11-25T08:30:00') | Out-Null
            New-Entry -Path $file -Started ([datetime]'2026-11-26T08:30:00') | Out-Null

            $runs = @((Read-Journal -Path $file).runs)
            $runs.Count | Should -Be 3
            $started = @(Get-StartedText -Path $file)
            $started[0] | Should -Match '^2026-11-24'
            $started[2] | Should -Match '^2026-11-26'
        }

        It 'removes the records older than the retention window' {
            $file = Join-Path -Path $TestDrive -ChildPath 'retention-runs.json'
            New-Entry -Path $file -Started (Get-Date).AddDays(-60) | Out-Null
            New-Entry -Path $file -Started (Get-Date).AddDays(-10) | Out-Null
            New-Entry -Path $file -Started (Get-Date) -RetentionDays 30 | Out-Null

            @((Read-Journal -Path $file).runs).Count | Should -Be 2
        }

        It 'keeps every record when the retention is 0' {
            $file = Join-Path -Path $TestDrive -ChildPath 'keep-runs.json'
            New-Entry -Path $file -Started (Get-Date).AddDays(-400) | Out-Null
            New-Entry -Path $file -Started (Get-Date) -RetentionDays 0 | Out-Null

            @((Read-Journal -Path $file).runs).Count | Should -Be 2
        }

        It 'never holds more than MaxEntries records, the oldest go first' {
            $file = Join-Path -Path $TestDrive -ChildPath 'cap-runs.json'
            1..5 | ForEach-Object { New-Entry -Path $file -Started ([datetime]"2026-11-0$_`T08:00:00") -MaxEntries 3 | Out-Null }

            $runs = @((Read-Journal -Path $file).runs)
            $runs.Count | Should -Be 3
            $started = @(Get-StartedText -Path $file)
            $started[0] | Should -Match '^2026-11-03'
            $started[2] | Should -Match '^2026-11-05'
        }

        It 'preserves the fields that a record carries beyond the ones this version writes' {
            $file = Join-Path -Path $TestDrive -ChildPath 'future-runs.json'
            $json = '{"schemaVersion":1,"runs":[{"started":"2026-11-20T08:00:00+01:00","durationSeconds":9,"extra":"keep me","farms":[]}]}'
            [System.IO.File]::WriteAllText($file, $json)
            New-Entry -Path $file | Out-Null

            $runs = @((Read-Journal -Path $file).runs)
            $runs.Count | Should -Be 2
            $runs[0].extra | Should -Be 'keep me'
            [System.DateTimeOffset]::Parse((Get-StartedText -Path $file)[0]) | Should -Be ([System.DateTimeOffset]::Parse('2026-11-20T08:00:00+01:00'))
        }

        It 'keeps the extra fields of a record even when they are nested deeply' {
            $file = Join-Path -Path $TestDrive -ChildPath 'deep-runs.json'
            $json = '{"schemaVersion":1,"runs":[{"started":"2026-11-20T08:00:00+01:00","farms":[{"name":"A","extra":{"l1":{"l2":{"l3":{"l4":"deep value"}}}}}]}]}'
            [System.IO.File]::WriteAllText($file, $json)
            New-Entry -Path $file | Out-Null

            [System.IO.File]::ReadAllText($file) | Should -Match 'deep value'
        }

        It 'accepts a retention far larger than any realistic one (keeps everything)' {
            $file = Join-Path -Path $TestDrive -ChildPath 'huge-runs.json'
            New-Entry -Path $file -Started (Get-Date).AddDays(-400) | Out-Null
            New-Entry -Path $file -RetentionDays 4294967295 | Should -BeTrue
            @((Read-Journal -Path $file).runs).Count | Should -Be 2
        }

        It 'leaves no temporary file behind' {
            $folder = Join-Path -Path $TestDrive -ChildPath 'clean'
            $file = Join-Path -Path $folder -ChildPath 'x-runs.json'
            New-Entry -Path $file | Out-Null
            New-Entry -Path $file | Out-Null
            @(Get-ChildItem -Path $folder).Name | Sort-Object | Should -Be @('x-runs.json', 'x-runs.json.lock')
        }
    }

    Context 'overlapping runs' {
        It 'keeps the record of every run when several runs write the same journal at the same time' {
            $file = Join-Path -Path $TestDrive -ChildPath 'concurrent-runs.json'
            $modulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
            $workers = 4
            $perWorker = 10
            $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $workers)
            $pool.Open()
            try {
                $jobs = foreach ($id in 1..$workers) {
                    $ps = [powershell]::Create()
                    $ps.RunspacePool = $pool
                    [void]$ps.AddScript({
                            param($Module, $File, $Count)
                            Import-Module -Name $Module -Force
                            $written = 0
                            foreach ($i in 1..$Count) {
                                $done = Add-SPSWeatherRunJournalEntry -Path $File -Started (Get-Date) -Duration ([timespan]::FromSeconds(1)) `
                                    -Version 'x' -Language 'en-US' -EmailMode 'PerFarm' -Mail 'none' -Farm @() -WarningAction SilentlyContinue
                                if ($done -eq $true) { $written++ }
                            }
                            $written
                        }).AddArgument($modulePath).AddArgument($file).AddArgument($perWorker)
                    [PSCustomObject]@{ Shell = $ps; Handle = $ps.BeginInvoke() }
                }
                $written = 0
                foreach ($job in $jobs) { $written += @($job.Shell.EndInvoke($job.Handle))[0]; $job.Shell.Dispose() }
            }
            finally { $pool.Dispose() }

            $written | Should -Be ($workers * $perWorker)
            @((Read-Journal -Path $file).runs).Count | Should -Be ($workers * $perWorker)
        }

        It 'gives up with a warning, and leaves the journal alone, when another run keeps it locked' {
            $file = Join-Path -Path $TestDrive -ChildPath 'busy-runs.json'
            New-Entry -Path $file | Out-Null
            $before = [System.IO.File]::ReadAllText($file)
            $holder = [System.IO.File]::Open("$file.lock", 'OpenOrCreate', 'ReadWrite', 'None')
            try {
                $started = Get-Date
                $result = Add-SPSWeatherRunJournalEntry -Path $file -Started (Get-Date) -Duration ([timespan]::FromSeconds(1)) -Version 'x' -Language 'en-US' `
                    -EmailMode 'PerFarm' -Mail 'none' -Farm @() -LockTimeoutSeconds 1 -WarningVariable lockWarning -WarningAction SilentlyContinue
                $result | Should -BeFalse
                ((Get-Date) - $started).TotalSeconds | Should -BeLessThan 10
                ($lockWarning -join ' ') | Should -Match 'locked'
            }
            finally { $holder.Dispose() }
            [System.IO.File]::ReadAllText($file) | Should -Be $before
        }

        It 'writes again once the other run has released the lock' {
            $file = Join-Path -Path $TestDrive -ChildPath 'released-runs.json'
            New-Entry -Path $file | Out-Null
            $holder = [System.IO.File]::Open("$file.lock", 'OpenOrCreate', 'ReadWrite', 'None')
            Add-SPSWeatherRunJournalEntry -Path $file -Started (Get-Date) -Duration ([timespan]::FromSeconds(1)) -Version 'x' -Language 'en-US' `
                -EmailMode 'PerFarm' -Mail 'none' -Farm @() -LockTimeoutSeconds 0 -WarningAction SilentlyContinue | Should -BeFalse
            $holder.Dispose()
            New-Entry -Path $file | Should -BeTrue
            @((Read-Journal -Path $file).runs).Count | Should -Be 2
        }

        It 'releases the lock after a failed write too' {
            $file = Join-Path -Path $TestDrive -ChildPath 'failed-runs.json'
            $bad = @([PSCustomObject]@{ Name = 'CONTENT'; Outcome = 'exploded' })
            New-Entry -Path $file -Farm $bad | Should -BeFalse
            { [System.IO.File]::Open("$file.lock", 'OpenOrCreate', 'ReadWrite', 'None').Dispose() } | Should -Not -Throw
        }
    }

    Context 'fields that this version does not know' {
        It 'keeps the extra top-level fields of the journal' {
            $file = Join-Path -Path $TestDrive -ChildPath 'meta-runs.json'
            [System.IO.File]::WriteAllText($file, '{"schemaVersion":1,"owner":"kept","limits":{"a":1},"runs":[]}')
            New-Entry -Path $file | Should -BeTrue

            $journal = Read-Journal -Path $file
            $journal.owner | Should -Be 'kept'
            $journal.limits.a | Should -Be 1
            $journal.schemaVersion | Should -Be 1
            @($journal.runs).Count | Should -Be 1
        }

        It 'writes a new journal with only the schema version and the runs' {
            $file = Join-Path -Path $TestDrive -ChildPath 'plain-runs.json'
            New-Entry -Path $file | Out-Null
            @((Read-Journal -Path $file).PSObject.Properties.Name) | Should -Be @('schemaVersion', 'runs')
        }
    }

    Context 'a journal that cannot be used' {
        It 'keeps a corrupt journal aside and starts a new one' {
            $file = Join-Path -Path $TestDrive -ChildPath 'corrupt-runs.json'
            [System.IO.File]::WriteAllText($file, '{ not json')
            New-Entry -Path $file | Should -BeTrue

            @((Read-Journal -Path $file).runs).Count | Should -Be 1
            [System.IO.File]::ReadAllText("$file.corrupt") | Should -Be '{ not json'
        }

        It 'keeps aside a journal whose runs is not a list (<Content>)' -ForEach @(
            @{ Content = '{"schemaVersion":1,"runs":"bad"}' }
            @{ Content = '{"schemaVersion":1,"runs":null}' }
            @{ Content = '{"schemaVersion":1,"runs":{"started":"2026-11-20T08:00:00+01:00"}}' }
        ) {
            $file = Join-Path -Path $TestDrive -ChildPath ("shape-{0}-runs.json" -f [guid]::NewGuid().ToString('N'))
            [System.IO.File]::WriteAllText($file, $Content)
            New-Entry -Path $file | Should -BeTrue

            [System.IO.File]::ReadAllText("$file.corrupt") | Should -Be $Content
            @((Read-Journal -Path $file).runs).Count | Should -Be 1
        }

        It 'treats a journal written by a newer schema as unreadable and does not overwrite it' {
            $file = Join-Path -Path $TestDrive -ChildPath 'newer-runs.json'
            [System.IO.File]::WriteAllText($file, '{"schemaVersion":99,"runs":[]}')
            New-Entry -Path $file | Should -BeTrue
            [System.IO.File]::ReadAllText("$file.corrupt") | Should -Match '"schemaVersion":99'
        }

        It 'does not set a journal aside when it exists but cannot be read (transient I/O error, not corruption)' -Skip:([System.Environment]::OSVersion.Platform -ne 'Unix') {
            $file = Join-Path -Path $TestDrive -ChildPath 'locked-unix-runs.json'
            New-Entry -Path $file | Out-Null
            $before = [System.IO.File]::ReadAllText($file)
            & chmod 000 $file
            try {
                New-Entry -Path $file | Should -BeFalse
            }
            finally { & chmod 644 $file }
            [System.IO.File]::ReadAllText($file) | Should -Be $before
            Test-Path -Path "$file.corrupt" | Should -BeFalse
        }

        It 'returns $false, keeps the journal intact and leaves no temporary file while another process holds it open' -Skip:([System.Environment]::OSVersion.Platform -ne 'Win32NT') {
            $file = Join-Path -Path $TestDrive -ChildPath 'locked-win-runs.json'
            New-Entry -Path $file | Out-Null
            $before = [System.IO.File]::ReadAllText($file)
            $stream = [System.IO.File]::Open($file, 'Open', 'Read', 'None')
            try {
                New-Entry -Path $file | Should -BeFalse
            }
            finally { $stream.Dispose() }
            [System.IO.File]::ReadAllText($file) | Should -Be $before
            Test-Path -Path "$file.corrupt" | Should -BeFalse
            @(Get-ChildItem -Path $TestDrive -Filter 'locked-win-runs.json.*.tmp').Count | Should -Be 0
        }

        It 'returns $false with a warning, and does not throw, when the journal cannot be written' {
            $blocker = Join-Path -Path $TestDrive -ChildPath 'iam-a-file'
            Set-Content -Path $blocker -Value 'x'
            $file = Join-Path -Path $blocker -ChildPath 'sub/runs.json'
            { New-Entry -Path $file } | Should -Not -Throw
            New-Entry -Path $file | Should -BeFalse
        }
    }
}

Describe 'Read-SPSWeatherRunJournal (private)' {
    It 'reports Missing, with no run, when the file does not exist' {
        InModuleScope SPSWeather.Common -Parameters @{ File = (Join-Path -Path $TestDrive -ChildPath 'nope-runs.json') } {
            $result = Read-SPSWeatherRunJournal -Path $File
            $result.Status | Should -Be 'Missing'
            @($result.Runs).Count | Should -Be 0
        }
    }

    It 'reports Corrupt for invalid JSON, a missing runs list or an unknown schema' {
        InModuleScope SPSWeather.Common -Parameters @{ Dir = $TestDrive } {
            foreach ($content in @('{ not json', '{"schemaVersion":1}', '{"runs":[]}', '[]', '{"schemaVersion":0,"runs":[]}', '{"schemaVersion":2,"runs":[]}', '{"schemaVersion":1,"runs":"bad"}', '{"schemaVersion":1,"runs":null}', '{"schemaVersion":1,"runs":{}}', '{"schemaVersion":1,"runs":7}')) {
                $file = Join-Path -Path $Dir -ChildPath 'probe-runs.json'
                [System.IO.File]::WriteAllText($file, $content)
                (Read-SPSWeatherRunJournal -Path $file).Status | Should -Be 'Corrupt' -Because $content
            }
        }
    }

    It 'returns the started timestamp as the original ISO string whatever the PowerShell version' {
        InModuleScope SPSWeather.Common -Parameters @{ File = (Join-Path -Path $TestDrive -ChildPath 'iso-runs.json') } {
            [System.IO.File]::WriteAllText($File, '{"schemaVersion":1,"runs":[{"started":"2026-11-26T08:30:01.0000000+01:00","farms":[]}]}')
            $result = Read-SPSWeatherRunJournal -Path $File
            $result.Status | Should -Be 'Ok'
            @($result.Runs)[0].started | Should -BeOfType [string]
            [System.DateTimeOffset]::Parse(@($result.Runs)[0].started) | Should -Be ([System.DateTimeOffset]::Parse('2026-11-26T08:30:01+01:00'))
        }
    }

    It 'ignores a record that has no started timestamp' {
        InModuleScope SPSWeather.Common -Parameters @{ File = (Join-Path -Path $TestDrive -ChildPath 'nostart-runs.json') } {
            [System.IO.File]::WriteAllText($File, '{"schemaVersion":1,"runs":[{"farms":[]},{"started":"2026-11-26T08:30:01+01:00"}]}')
            @((Read-SPSWeatherRunJournal -Path $File).Runs).Count | Should -Be 1
        }
    }
}
