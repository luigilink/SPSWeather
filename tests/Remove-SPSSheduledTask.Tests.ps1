# Contract tests for Remove-SPSSheduledTask.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-SPSSheduledTask' {
    It 'supports ShouldProcess (WhatIf/Confirm)' {
        (Get-Command -Name Remove-SPSSheduledTask -Module SPSWeather.Common).Parameters.Keys |
            Should -Contain 'WhatIf'
    }

    It 'requires a mandatory -TaskName' {
        $param = (Get-Command -Name Remove-SPSSheduledTask -Module SPSWeather.Common).Parameters['TaskName']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }
}
