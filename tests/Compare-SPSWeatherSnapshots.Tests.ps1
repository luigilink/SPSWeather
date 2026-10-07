# Behavioural tests for Compare-SPSWeatherSnapshots (Ok/Alert deltas between runs).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Compare-SPSWeatherSnapshots' {
    It 'counts Ok and Alert rows from IsInfo and reports deltas' {
        $current = [PSCustomObject]@{}
        $current | Add-Member -MemberType NoteProperty -Name S -Value @(
            [PSCustomObject]@{ IsInfo = $true }
            [PSCustomObject]@{ IsInfo = $false }
            [PSCustomObject]@{ IsInfo = $false }
        )
        $previous = [PSCustomObject]@{}
        $previous | Add-Member -MemberType NoteProperty -Name S -Value @(
            [PSCustomObject]@{ IsInfo = $true }
            [PSCustomObject]@{ IsInfo = $false }
        )

        $r = Compare-SPSWeatherSnapshots -CurrentObject $current -PreviousObject $previous
        $r.Current.Ok | Should -Be 1
        $r.Current.Alert | Should -Be 2
        $r.Previous.Ok | Should -Be 1
        $r.Previous.Alert | Should -Be 1
        $r.DeltaAlert | Should -Be 1
        $r.DeltaOk | Should -Be 0
        $r.HasPrevious | Should -BeTrue
    }

    It 'ignores sections without an IsInfo property' {
        $current = [PSCustomObject]@{}
        $current | Add-Member -MemberType NoteProperty -Name SysInfo -Value @(
            [PSCustomObject]@{ Server = 'SRV1'; Version = '4.8' }
        )
        $r = Compare-SPSWeatherSnapshots -CurrentObject $current -PreviousObject ([PSCustomObject]@{})
        $r.Current.Ok | Should -Be 0
        $r.Current.Alert | Should -Be 0
    }

    It 'flags HasPrevious as $false when no previous snapshot is supplied' {
        $current = [PSCustomObject]@{}
        $current | Add-Member -MemberType NoteProperty -Name S -Value @([PSCustomObject]@{ IsInfo = $true })
        $r = Compare-SPSWeatherSnapshots -CurrentObject $current
        $r.HasPrevious | Should -BeFalse
    }
}
