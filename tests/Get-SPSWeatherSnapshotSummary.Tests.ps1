# Behavioural tests for Get-SPSWeatherSnapshotSummary (private): the one way of counting a snapshot.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSWeatherSnapshotSummary' {
    It 'gives zeros and no item for a null snapshot, an empty one and one without rows' -ForEach @(
        @{ Snapshot = $null }
        @{ Snapshot = [PSCustomObject]@{} }
        @{ Snapshot = [PSCustomObject]@{ SPUpgradeStatus = @() } }
        @{ Snapshot = [PSCustomObject]@{ SPUpgradeStatus = $null } }
    ) {
        $s = InModuleScope SPSWeather.Common -Parameters @{ S = $Snapshot } { param($S) Get-SPSWeatherSnapshotSummary -Snapshot $S }
        $s.Ok | Should -Be 0
        $s.Warn | Should -Be 0
        $s.Fail | Should -Be 0
        @($s.Items).Count | Should -Be 0
    }

    It 'counts OK, warnings and failures with the severity model, and lists the warnings and failures' {
        $snapshot = [PSCustomObject]@{
            SPAPIHttpStatus  = @([PSCustomObject]@{ Title = 'A'; IsInfo = $true }, [PSCustomObject]@{ Title = 'B'; IsInfo = $false })
            SPHealthAnalyzer = @([PSCustomObject]@{ title = 'T1'; severity = '2 - Warning' }, [PSCustomObject]@{ title = 'T2'; severity = '1 - Error' }, [PSCustomObject]@{ title = 'T3'; severity = '4 - Information' })
            SQLDatabaseStatus = @([PSCustomObject]@{ Name = 'D1'; Recommendation = 'AutoShrink ON'; IsInfo = $true })
        }
        $s = InModuleScope SPSWeather.Common -Parameters @{ S = $snapshot } { param($S) Get-SPSWeatherSnapshotSummary -Snapshot $S }
        $s.Ok | Should -Be 2
        $s.Warn | Should -Be 2
        $s.Fail | Should -Be 2
        @($s.Items).Count | Should -Be 4
        @($s.Items | Where-Object { $_.Severity -eq 'fail' } | ForEach-Object { $_.Section }) | Should -Be @('SPAPIHttpStatus', 'SPHealthAnalyzer')
        @($s.Items | Where-Object { $_.Severity -eq 'warn' } | ForEach-Object { $_.Section }) | Should -Be @('SPHealthAnalyzer', 'SQLDatabaseStatus')
    }

    It 'does not count a descriptive row (no IsInfo, no severity) as a check' {
        $snapshot = [PSCustomObject]@{ SYSLastRebootStatus = @([PSCustomObject]@{ Server = 'S1'; LastRebootTime = 'x' }) }
        $s = InModuleScope SPSWeather.Common -Parameters @{ S = $snapshot } { param($S) Get-SPSWeatherSnapshotSummary -Snapshot $S }
        $s.Ok | Should -Be 0
        @($s.Items).Count | Should -Be 0
    }

    It 'keeps the row of an item, for the caller that needs to name it' {
        $row = [PSCustomObject]@{ Name = 'D1'; IsInfo = $false }
        $s = InModuleScope SPSWeather.Common -Parameters @{ S = ([PSCustomObject]@{ SQLDatabaseStatus = @($row) }) } { param($S) Get-SPSWeatherSnapshotSummary -Snapshot $S }
        @($s.Items)[0].Row.Name | Should -Be 'D1'
    }

    It 'is the counting that Get-SPSWeatherHistory uses' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'hist'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $snapshot = [PSCustomObject]@{
            SPAPIHttpStatus  = @([PSCustomObject]@{ IsInfo = $true }, [PSCustomObject]@{ IsInfo = $false })
            SPHealthAnalyzer = @([PSCustomObject]@{ severity = '2 - Warning' })
        }
        Set-Content -Path (Join-Path -Path $folder -ChildPath 'a.json') -Value (ConvertTo-Json -InputObject $snapshot -Depth 5)
        $bar = @(Get-SPSWeatherHistory -HistoryFolder $folder)[0]
        $s = InModuleScope SPSWeather.Common -Parameters @{ S = (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $snapshot -Depth 5)) } { param($S) Get-SPSWeatherSnapshotSummary -Snapshot $S }
        $bar.Ok | Should -Be $s.Ok
        $bar.Warn | Should -Be $s.Warn
        $bar.Fail | Should -Be $s.Fail
    }
}
