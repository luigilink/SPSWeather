# Behavioural tests for Resolve-SPSSqlAlias (registry alias resolution).
# The registry only exists on Windows; the merge/bitness logic is exercised by
# mocking the registry access inside the module.

$script:onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-SPSSqlAlias' {
    It 'returns nothing when no alias registry key exists' {
        InModuleScope SPSWeather.Common {
            Mock Test-Path { $false }
            @(Resolve-SPSSqlAlias) | Should -BeNullOrEmpty
        }
    }

    It 'resolves a 64-bit TCP alias to its real target' {
        InModuleScope SPSWeather.Common {
            Mock Test-Path { $Path -like '*Microsoft\MSSQLServer\Client\ConnectTo*' -and $Path -notlike '*Wow6432Node*' }
            Mock Get-Item {
                [PSCustomObject]@{} |
                    Add-Member -MemberType ScriptMethod -Name GetValueNames -Value { @('SPSQLCONTENT') } -Force -PassThru |
                    Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($n) 'DBMSSOCN,SQLPROD01\SP,1433' } -Force -PassThru
            }
            $r = @(Resolve-SPSSqlAlias)
            $r.Count | Should -Be 1
            $r[0].Alias | Should -Be 'SPSQLCONTENT'
            $r[0].Server | Should -Be 'SQLPROD01'
            $r[0].Instance | Should -Be 'SP'
            $r[0].Port | Should -Be '1433'
            $r[0].Bitness | Should -Be '64-bit'
        }
    }

    It 'marks an alias defined in both bitness hives as both' {
        InModuleScope SPSWeather.Common {
            Mock Test-Path { $true }
            Mock Get-Item {
                [PSCustomObject]@{} |
                    Add-Member -MemberType ScriptMethod -Name GetValueNames -Value { @('SPSQL') } -Force -PassThru |
                    Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($n) 'DBMSSOCN,SQLPROD02' } -Force -PassThru
            }
            $r = @(Resolve-SPSSqlAlias)
            $r.Count | Should -Be 1
            $r[0].Bitness | Should -Be 'both'
        }
    }
}
