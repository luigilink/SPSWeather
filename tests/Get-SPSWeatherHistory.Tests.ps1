# Behavioural tests for Get-SPSWeatherHistory (dashboard history series).
# Exported so the entry script can call it from outside the module.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSWeatherHistory' {
    It 'returns an empty array when the history folder does not exist' {
        InModuleScope SPSWeather.Common -Parameters @{ Folder = (Join-Path -Path $TestDrive -ChildPath 'nope') } {
            param($Folder)
            @(Get-SPSWeatherHistory -HistoryFolder $Folder).Count | Should -Be 0
        }
    }

    It 'classifies rows into Ok/Warn/Fail per snapshot, oldest first' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'hist-series'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null

        $snap1 = [PSCustomObject]@{
            SPAPIHttpStatus  = @([PSCustomObject]@{ IsInfo = $true }, [PSCustomObject]@{ IsInfo = $false })
            SPHealthAnalyzer = @([PSCustomObject]@{ severity = '2 - Warning' })
        }
        $snap2 = [PSCustomObject]@{
            SPAPIHttpStatus = @([PSCustomObject]@{ IsInfo = $true }, [PSCustomObject]@{ IsInfo = $true })
        }
        $f1 = Join-Path -Path $folder -ChildPath 'a-20260101-0000.json'
        $f2 = Join-Path -Path $folder -ChildPath 'a-20260102-0000.json'
        $snap1 | ConvertTo-Json -Depth 6 | Set-Content -Path $f1
        $snap2 | ConvertTo-Json -Depth 6 | Set-Content -Path $f2
        (Get-Item $f1).LastWriteTime = (Get-Date).AddDays(-2)
        (Get-Item $f2).LastWriteTime = (Get-Date).AddDays(-1)

        InModuleScope SPSWeather.Common -Parameters @{ Folder = $folder } {
            param($Folder)
            $series = @(Get-SPSWeatherHistory -HistoryFolder $Folder)
            $series.Count | Should -Be 2
            $series[0].Ok | Should -Be 1
            $series[0].Fail | Should -Be 1
            $series[0].Warn | Should -Be 1
            $series[1].Ok | Should -Be 2
            $series[1].Fail | Should -Be 0
        }
    }

    Context 'a history folder shared by several environments (-NamePrefix)' {
        BeforeAll {
            function script:New-SharedHistory {
                $folder = Join-Path -Path $TestDrive -ChildPath ('hist-' + [guid]::NewGuid().ToString('N'))
                New-Item -Path $folder -ItemType Directory -Force | Out-Null
                $specs = @(
                    @{ Name = 'zebes-PROD-CONTENT-20261120-0900.json'; Fail = 1; DaysAgo = 6 }
                    @{ Name = 'zebes-TEST-CONTENT-20261121-0900.json'; Fail = 9; DaysAgo = 5 }
                    @{ Name = 'zebes-PROD-CONTENT-20261122-0900.json'; Fail = 2; DaysAgo = 4 }
                    @{ Name = 'other-PROD-CONTENT-20261123-0900.json'; Fail = 8; DaysAgo = 3 }
                    @{ Name = 'zebes-PROD-CONTENT-20261124-0900.json'; Fail = 3; DaysAgo = 2 }
                    @{ Name = 'zebes-TEST-CONTENT-20261125-0900.json'; Fail = 7; DaysAgo = 1 }
                )
                foreach ($spec in $specs) {
                    $rows = @(); foreach ($i in 1..$spec.Fail) { $rows += [PSCustomObject]@{ IsInfo = $false } }
                    $file = Join-Path -Path $folder -ChildPath $spec.Name
                    Set-Content -Path $file -Value (ConvertTo-Json -InputObject ([PSCustomObject]@{ SPAPIHttpStatus = $rows }) -Depth 5)
                    (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-$spec.DaysAgo)
                }
                $folder
            }
            function script:Get-Bars {
                param($Folder, [string]$Prefix, [int]$Max = 30)
                InModuleScope SPSWeather.Common -Parameters @{ F = $Folder; P = $Prefix; M = $Max } {
                    param($F, $P, $M)
                    if ($P) { @(Get-SPSWeatherHistory -HistoryFolder $F -NamePrefix $P -Max $M) } else { @(Get-SPSWeatherHistory -HistoryFolder $F -Max $M) }
                }
            }
        }

        It 'reads only the runs of one environment when a prefix is given' {
            $bars = Get-Bars -Folder (New-SharedHistory) -Prefix 'zebes-PROD-CONTENT-'
            @($bars | ForEach-Object { $_.Fail }) | Should -Be @(1, 2, 3)
        }

        It 'reads every file of the folder, as before, without a prefix' {
            @(Get-Bars -Folder (New-SharedHistory) -Prefix '').Count | Should -Be 6
        }

        It 'matches the prefix whatever its case' {
            @(Get-Bars -Folder (New-SharedHistory) -Prefix 'ZEBES-prod-content-').Count | Should -Be 3
        }

        It 'keeps the most recent runs of that environment when there are more than -Max, whatever the other environments wrote later' {
            $bars = Get-Bars -Folder (New-SharedHistory) -Prefix 'zebes-PROD-CONTENT-' -Max 2
            @($bars | ForEach-Object { $_.Fail }) | Should -Be @(2, 3)
        }

        It 'returns nothing when no file has the prefix' {
            @(Get-Bars -Folder (New-SharedHistory) -Prefix 'nobody-').Count | Should -Be 0
        }
    }

    It 'gives every run a When date next to the MM-dd text, so a language can format it' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'hist-when'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $file = Join-Path -Path $folder -ChildPath 'a-20260304-0000.json'
        ([PSCustomObject]@{ SPAPIHttpStatus = @([PSCustomObject]@{ IsInfo = $true }) } | ConvertTo-Json -Depth 4) | Set-Content -Path $file
        (Get-Item $file).LastWriteTime = [datetime]'2026-03-04T10:00:00'

        InModuleScope SPSWeather.Common -Parameters @{ Folder = $folder } {
            param($Folder)
            $run = @(Get-SPSWeatherHistory -HistoryFolder $Folder)[0]
            $run.When | Should -BeOfType [datetime]
            $run.When.Month | Should -Be 3
            $run.When.Day | Should -Be 4
            $run.Date | Should -Be '03-04'
        }
    }

    It 'writes the Date text with ASCII digits whatever the host calendar' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'hist-calendar'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $file = Join-Path -Path $folder -ChildPath 'a-20260304-0000.json'
        ([PSCustomObject]@{ SPAPIHttpStatus = @([PSCustomObject]@{ IsInfo = $true }) } | ConvertTo-Json -Depth 4) | Set-Content -Path $file
        (Get-Item $file).LastWriteTime = [datetime]'2026-03-04T10:00:00'
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            foreach ($hostCulture in 'th-TH', 'ar-SA', 'fa-IR') {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($hostCulture)
                InModuleScope SPSWeather.Common -Parameters @{ Folder = $folder } {
                    param($Folder)
                    @(Get-SPSWeatherHistory -HistoryFolder $Folder)[0].Date | Should -Be '03-04'
                }
            }
        }
        finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous }
    }

    It 'caps the series at -Max most recent runs' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'hist-cap'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        for ($i = 1; $i -le 5; $i++) {
            $f = Join-Path -Path $folder -ChildPath ("a-2026010$i-0000.json")
            ([PSCustomObject]@{ S = @([PSCustomObject]@{ IsInfo = $true }) }) | ConvertTo-Json | Set-Content -Path $f
            (Get-Item $f).LastWriteTime = (Get-Date).AddDays(-6 + $i)
        }
        InModuleScope SPSWeather.Common -Parameters @{ Folder = $folder } {
            param($Folder)
            @(Get-SPSWeatherHistory -HistoryFolder $Folder -Max 3).Count | Should -Be 3
        }
    }
}

Describe 'History series (Get-SPSWeatherHistory) callable from outside the module' {
    It 'is exported and resolves when called in the caller scope (not InModuleScope)' {
        # Regression guard: the entry script calls this from outside the module, so it
        # must be exported (it was previously private and threw "not recognized").
        Get-Command -Name Get-SPSWeatherHistory -Module SPSWeather.Common -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'builds the Ok/Warn/Fail series from snapshots when called directly' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'hist-ext'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        ([PSCustomObject]@{ S = @([PSCustomObject]@{ IsInfo = $true }, [PSCustomObject]@{ IsInfo = $false }) }) |
            ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path -Path $folder -ChildPath 'a-20260101-0000.json')
        $series = @(Get-SPSWeatherHistory -HistoryFolder $folder)
        $series.Count | Should -Be 1
        $series[0].Ok | Should -Be 1
        $series[0].Fail | Should -Be 1
    }

    It 'excludes pure info-only rows from the OK total (consistent with the current-run donut)' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'hist-info'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        ([PSCustomObject]@{
                SYSLastRebootStatus = @([PSCustomObject]@{ Server = 'S1'; LastRebootTime = 'x' })        # pure info, no IsInfo
                SYSDiskUsageStatus  = @([PSCustomObject]@{ Server = 'S1'; Status = 'OK'; IsInfo = $true }) # real check
            }) | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path -Path $folder -ChildPath 'a-20260101-0000.json')
        $series = @(Get-SPSWeatherHistory -HistoryFolder $folder)
        $series[0].Ok | Should -Be 1   # only the IsInfo check, not the reboot info row
    }
}
