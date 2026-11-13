# Contract tests for Add-SPSSheduledTask.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Add-SPSSheduledTask' {
    It 'requires a mandatory -TaskName' {
        $param = (Get-Command -Name Add-SPSSheduledTask -Module SPSWeather.Common).Parameters['TaskName']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }

    It 'exposes an optional -Description parameter' {
        $param = (Get-Command -Name Add-SPSSheduledTask -Module SPSWeather.Common).Parameters['Description']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeFalse
    }

    It 'creates or updates the task (mode 6, no silent skip)' {
        $src = (Get-Command -Name Add-SPSSheduledTask -Module SPSWeather.Common).Definition
        $src | Should -Match 'RegisterTaskDefinition\([^)]*6,'
        $src | Should -Not -Match 'already exists - skipping'
        $src | Should -Match 'throw'
    }
}
