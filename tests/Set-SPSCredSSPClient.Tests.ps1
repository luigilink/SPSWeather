# Behavioural tests for Set-SPSCredSSPClient (CredSSP client role + delegation).
# Windows-only: the WSMan provider and registry policy keys only exist on Windows.

# Discovery-time Windows detection: $IsWindows is undefined on Windows PowerShell 5.1,
# so derive it from the edition to keep the -Skip guards correct under the 5.1 CI job.
$script:onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'CredSSP client setup (Set-SPSCredSSPClient)' {
    It 'is Windows-only: returns $false and warns off Windows' -Skip:($onWindows) {
        $warn = $null
        $result = Set-SPSCredSSPClient -DelegateComputer 'app1.contoso.com' -WarningVariable warn -WarningAction SilentlyContinue
        $result | Should -BeFalse
        $warn | Should -Not -BeNullOrEmpty
    }

    Context 'on Windows' -Skip:(-not $onWindows) {
        BeforeAll {
            Mock -ModuleName SPSWeather.Common -CommandName Get-Item -MockWith { [PSCustomObject]@{ Value = 'false'; SourceOfValue = '' } }
            Mock -ModuleName SPSWeather.Common -CommandName Set-Item -MockWith { }
            Mock -ModuleName SPSWeather.Common -CommandName Test-Path -MockWith { $true }
            Mock -ModuleName SPSWeather.Common -CommandName New-Item -MockWith { }
            Mock -ModuleName SPSWeather.Common -CommandName Get-ItemProperty -MockWith { $null }
            Mock -ModuleName SPSWeather.Common -CommandName New-ItemProperty -MockWith { }
        }

        It 'enables CredSSP client authentication' {
            $null = Set-SPSCredSSPClient -DelegateComputer 'app1.contoso.com'
            Should -Invoke -ModuleName SPSWeather.Common -CommandName Set-Item -Times 1 -ParameterFilter { $Value -eq $true }
        }

        It 'adds a WSMAN/<fqdn> delegation SPN for each server' {
            $null = Set-SPSCredSSPClient -DelegateComputer 'app1.contoso.com', 'app2.contoso.com'
            Should -Invoke -ModuleName SPSWeather.Common -CommandName New-ItemProperty -ParameterFilter { $Value -eq 'WSMAN/app1.contoso.com' }
            Should -Invoke -ModuleName SPSWeather.Common -CommandName New-ItemProperty -ParameterFilter { $Value -eq 'WSMAN/app2.contoso.com' }
        }

        It 'does not write anything under -WhatIf' {
            $null = Set-SPSCredSSPClient -DelegateComputer 'app1.contoso.com' -WhatIf
            Should -Invoke -ModuleName SPSWeather.Common -CommandName Set-Item -Times 0
            Should -Invoke -ModuleName SPSWeather.Common -CommandName New-ItemProperty -Times 0
        }
    }
}
