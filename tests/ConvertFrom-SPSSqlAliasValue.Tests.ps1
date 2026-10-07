# Behavioural tests for the ConvertFrom-SPSSqlAliasValue private parser.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'SQL alias parsing (ConvertFrom-SPSSqlAliasValue)' {
    It 'parses a TCP alias with instance and port' {
        InModuleScope SPSWeather.Common {
            $r = ConvertFrom-SPSSqlAliasValue -AliasName 'SPSQL' -RawValue 'DBMSSOCN,SQLPROD01\SP,1433'
            $r.Protocol | Should -Be 'TCP'
            $r.Server   | Should -Be 'SQLPROD01'
            $r.Instance | Should -Be 'SP'
            $r.Port     | Should -Be '1433'
        }
    }

    It 'parses a default-instance TCP alias without a port' {
        InModuleScope SPSWeather.Common {
            $r = ConvertFrom-SPSSqlAliasValue -AliasName 'SPDEF' -RawValue 'DBMSSOCN,SQLPROD02'
            $r.Protocol | Should -Be 'TCP'
            $r.Server   | Should -Be 'SQLPROD02'
            $r.Instance | Should -BeNullOrEmpty
            $r.Port     | Should -BeNullOrEmpty
        }
    }

    It 'parses a named-pipes alias' {
        InModuleScope SPSWeather.Common {
            $r = ConvertFrom-SPSSqlAliasValue -AliasName 'SPNP' -RawValue 'DBNMPNTW,\\SQLPROD03\pipe\MSSQL$SP\sql\query'
            $r.Protocol | Should -Be 'NamedPipes'
            $r.Server   | Should -Be 'SQLPROD03'
            $r.Instance | Should -Be 'SP'
        }
    }

    It 'does not throw on an empty value' {
        InModuleScope SPSWeather.Common {
            $r = ConvertFrom-SPSSqlAliasValue -AliasName 'SPBAD' -RawValue ''
            $r.Alias    | Should -Be 'SPBAD'
            $r.Protocol | Should -Be 'Unknown'
        }
    }
}
