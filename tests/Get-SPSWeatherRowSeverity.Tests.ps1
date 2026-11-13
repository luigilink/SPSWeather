# Behavioural tests for the Get-SPSWeatherRowSeverity private helper: the single
# severity model shared by the dashboard, email, history and per-farm outcome.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Severity model (Get-SPSWeatherRowSeverity)' {
    It 'classifies IsInfo = $false as fail' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ IsInfo = $false }) | Should -Be 'fail'
        }
    }

    It 'classifies a healthy IsInfo = $true row as ok' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ IsInfo = $true }) | Should -Be 'ok'
        }
    }

    It 'treats an IsInfo = $true row carrying an advisory Recommendation as warn' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ IsInfo = $true; Recommendation = 'MAXDOP should be 1' }) | Should -Be 'warn'
        }
    }

    It 'treats an IsInfo = $true alias row with only a descriptive Note as ok (not warn)' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ IsInfo = $true; Note = 'used by SharePoint but not declared in config' }) | Should -Be 'ok'
        }
    }

    It 'maps Health Analyzer severity strings (no IsInfo) to warn/fail' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ severity = '2 - Warning' }) | Should -Be 'warn'
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ severity = '1 - Error' }) | Should -Be 'fail'
        }
    }

    It 'treats an Unreachable row with no IsInfo as fail' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ Server = 'SRV1'; OSName = 'Unreachable' }) | Should -Be 'fail'
        }
    }

    It 'returns ok for a pure info row and for $null' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ Server = 'SRV1'; Version = '4.8' }) | Should -Be 'ok'
            Get-SPSWeatherRowSeverity -Row $null | Should -Be 'ok'
        }
    }
}
