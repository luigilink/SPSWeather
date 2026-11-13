# Behavioural tests for the Get-SPSConfigRoot private helper.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSConfigRoot' {
    It 'resolves to src/Config under the module root' {
        InModuleScope SPSWeather.Common {
            $root = Get-SPSConfigRoot
            $root | Should -Match 'Config$'
            Split-Path -Path $root -Leaf | Should -Be 'Config'
        }
    }

    It 'throws a clear error when the module root is not set' {
        InModuleScope SPSWeather.Common {
            $saved = $script:ModuleRoot
            try {
                $script:ModuleRoot = ''
                { Get-SPSConfigRoot } | Should -Throw '*ModuleRoot*'
            }
            finally {
                $script:ModuleRoot = $saved
            }
        }
    }
}
