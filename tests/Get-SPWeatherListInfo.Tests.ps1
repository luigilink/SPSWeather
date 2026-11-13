# Behavioural tests for Get-SPWeatherListInfo (run metadata row shown in the report).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPWeatherListInfo' {
    BeforeAll {
        $info = @(Get-SPWeatherListInfo -Version '3.1.0' -PSVersion '5.1.20348' -UserAccount 'CONTOSO\svc' `
                -DateStarted '2026-11-13 18:00' -DateEnded '2026-11-13 18:04' -Environment 'PROD' -Application 'zebes')
    }

    It 'returns a single row carrying every supplied value' {
        $info.Count | Should -Be 1
        $info[0].Version | Should -Be '3.1.0'
        $info[0].PSVersion | Should -Be '5.1.20348'
        $info[0].UserAccount | Should -Be 'CONTOSO\svc'
        $info[0].DateStarted | Should -Be '2026-11-13 18:00'
        $info[0].DateEnded | Should -Be '2026-11-13 18:04'
        $info[0].Environment | Should -Be 'PROD'
        $info[0].Application | Should -Be 'zebes'
    }

    It 'exposes exactly the run-metadata columns, in order' {
        $info[0].PSObject.Properties.Name |
            Should -Be @('Version', 'PSVersion', 'UserAccount', 'DateStarted', 'DateEnded', 'Environment', 'Application')
    }

    It 'treats every parameter as optional' {
        { Get-SPWeatherListInfo } | Should -Not -Throw
        $empty = @(Get-SPWeatherListInfo)
        $empty.Count | Should -Be 1
    }
}
