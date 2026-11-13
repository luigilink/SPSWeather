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
