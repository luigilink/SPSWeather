# Behavioural tests for the declared-vs-discovered SQL alias mapping of Get-SPSSqlStatus.
# The logic lives in inner functions of the remote script block (they run on the farm
# server), so they are extracted by AST and exercised here without registry or SharePoint.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    # The module is only needed for the parity test against its private alias parser.
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force
    $source = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/Public/Get-SPSSqlStatus.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
    foreach ($name in @('ConvertFrom-SqlAliasRaw', 'Get-SqlTargetKey', 'Get-SqlNameKey', 'Get-SqlAliasRow')) {
        $definition = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            Where-Object { $_.Name -eq $name } | Select-Object -First 1
        $definition | Should -Not -BeNullOrEmpty
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    # Stand-in for the registry lookup done on the farm server.
    function Resolve-AliasLocal {
        param($AliasName)
        $script:fakeAliases[$AliasName]
    }
    function New-FakeAlias {
        param($Server, $Instance = '', $Bitness = 'both')
        [PSCustomObject]@{ Provider = 'DBMSSOCN'; Protocol = 'TCP'; Server = $Server; Instance = $Instance; Port = '1433'; Bitness = $Bitness; Raw = '' }
    }
}

Describe 'Get-SqlTargetKey (normalized SQL target identity)' {
    It "maps '<Target>' to '<Expected>'" -ForEach @(
        @{ Target = 'SQL1'; Expected = 'sql1' }
        @{ Target = 'sql1.contoso.com'; Expected = 'sql1' }
        @{ Target = 'tcp:SQL1,1433'; Expected = 'sql1' }
        @{ Target = 'SQL1\MSSQLSERVER'; Expected = 'sql1' }
        @{ Target = 'SQL1\SP'; Expected = 'sql1\sp' }
        @{ Target = 'SQL1.contoso.com\SP'; Expected = 'sql1\sp' }
        @{ Target = '10.0.0.5'; Expected = '10.0.0.5' }
        @{ Target = ''; Expected = '' }
    ) {
        Get-SqlTargetKey -Target $Target | Should -Be $Expected
    }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-SqlAliasRaw (raw cliconfg registry value)' {
    It "parses '<Raw>' into <Protocol> server '<Server>' instance '<Instance>' port '<Port>'" -ForEach @(
        @{ Raw = 'DBMSSOCN,SQL1,1433'; Protocol = 'TCP'; Server = 'SQL1'; Instance = ''; Port = '1433' }
        @{ Raw = 'DBMSSOCN,SQL1\SP,1433'; Protocol = 'TCP'; Server = 'SQL1'; Instance = 'SP'; Port = '1433' }
        @{ Raw = 'DBNMPNTW,\\SQL1\pipe\MSSQL$SP\sql\query'; Protocol = 'NamedPipes'; Server = 'SQL1'; Instance = 'SP'; Port = '' }
        @{ Raw = 'DBNMPNTW,\\SQL1\pipe\sql\query'; Protocol = 'NamedPipes'; Server = 'SQL1'; Instance = ''; Port = '' }
    ) {
        $r = ConvertFrom-SqlAliasRaw -Raw $Raw
        $r.Protocol | Should -Be $Protocol
        $r.Server | Should -Be $Server
        $r.Instance | Should -Be $Instance
        $r.Port | Should -Be $Port
    }

    # The remote session cannot reach the module's private parser, so the inner copy must not drift from it.
    It "agrees with the module's ConvertFrom-SPSSqlAliasValue for '<Raw>'" -ForEach @(
        @{ Raw = 'DBMSSOCN,SQLPROD01\SP,1433' }
        @{ Raw = 'DBMSSOCN,SQLPROD01' }
        @{ Raw = 'DBNMPNTW,\\SQLPROD03\pipe\MSSQL$SP\sql\query' }
        @{ Raw = 'DBNMPNTW,\\SQLPROD03\pipe\sql\query' }
        @{ Raw = 'OTHER,whatever' }
    ) {
        $inner = ConvertFrom-SqlAliasRaw -Raw $Raw
        $private = InModuleScope SPSWeather.Common -Parameters @{ Raw = $Raw } {
            param($Raw)
            ConvertFrom-SPSSqlAliasValue -AliasName 'X' -RawValue $Raw
        }
        foreach ($field in 'Provider', 'Protocol', 'Server', 'Instance', 'Port') {
            $inner.$field | Should -Be $private.$field
        }
    }
}

Describe 'Get-SqlAliasRow (declared vs discovered)' {
    BeforeEach {
        $script:fakeAliases = @{}
    }

    Context 'declared real server reached through cliconfg aliases' {
        BeforeEach {
            $aliases = 'SINGLE-ADM-SPSSQL', 'SINGLE-SCH-SPSSQL', 'SINGLE-SVC-SPSSQL', 'SINGLE-WEB-SPSSQL'
            foreach ($a in $aliases) { $script:fakeAliases[$a] = New-FakeAlias -Server 'SQL1' -Instance 'MSSQLSERVER' }
            $rows = @(Get-SqlAliasRow -FarmName 'CONTENT' -DiscoveredServers $aliases -DeclaredServers @('SQL1'))
        }

        It 'treats every alias as declared through its real server' {
            $aliasRows = @($rows | Where-Object { $_.IsAlias })
            $aliasRows.Count | Should -Be 4
            $aliasRows | ForEach-Object { $_.Declared | Should -BeTrue; $_.Discovered | Should -BeTrue; $_.Note | Should -BeNullOrEmpty }
        }

        It 'shows the declared server as used, through its aliases' {
            $server = $rows | Where-Object { $_.Name -eq 'SQL1' }
            $server.Declared | Should -BeTrue
            $server.Discovered | Should -BeTrue
            $server.Note | Should -Match 'used through alias SINGLE-ADM-SPSSQL'
        }

        It 'raises neither the not-declared nor the not-used note' {
            ($rows.Note -join ' ') | Should -Not -Match 'not declared|not used'
        }
    }

    Context 'genuine mismatches are still reported' {
        It 'flags a used server that is not declared, and a declared server that is not used' {
            $script:fakeAliases['SPSQLCONTENT'] = New-FakeAlias -Server 'SQL2' -Instance 'MSSQLSERVER'
            $rows = @(Get-SqlAliasRow -FarmName 'CONTENT' -DiscoveredServers @('SPSQLCONTENT') -DeclaredServers @('SQL1'))
            ($rows | Where-Object { $_.Name -eq 'SPSQLCONTENT' }).Note | Should -Be 'used by SharePoint but not declared in config'
            ($rows | Where-Object { $_.Name -eq 'SQL1' }).Note | Should -Be 'declared in config but not used by any database'
        }

        It 'does not let a host-only declaration hide a named instance' {
            $script:fakeAliases['SPSQLCONTENT'] = New-FakeAlias -Server 'SQL1' -Instance 'SP'
            $rows = @(Get-SqlAliasRow -FarmName 'CONTENT' -DiscoveredServers @('SPSQLCONTENT') -DeclaredServers @('SQL1'))
            ($rows | Where-Object { $_.Name -eq 'SPSQLCONTENT' }).Declared | Should -BeFalse
            ($rows | Where-Object { $_.Name -eq 'SQL1' }).Discovered | Should -BeFalse
        }
    }

    Context 'matching rules' {
        It 'matches a declared FQDN case-insensitively against the real server of an alias' {
            $script:fakeAliases['SPSQLCONTENT'] = New-FakeAlias -Server 'SQL1' -Instance ''
            $rows = @(Get-SqlAliasRow -FarmName 'CONTENT' -DiscoveredServers @('SPSQLCONTENT') -DeclaredServers @('sql1.contoso.com'))
            ($rows | Where-Object { $_.Name -eq 'SPSQLCONTENT' }).Declared | Should -BeTrue
            ($rows | Where-Object { $_.Name -eq 'sql1.contoso.com' }).Discovered | Should -BeTrue
        }

        It 'considers a declared alias used when SharePoint references its real server directly' {
            $script:fakeAliases['SPSQL'] = New-FakeAlias -Server 'SQL1' -Instance 'MSSQLSERVER'
            $rows = @(Get-SqlAliasRow -FarmName 'CONTENT' -DiscoveredServers @('SQL1') -DeclaredServers @('SPSQL'))
            $rows.Count | Should -Be 2
            ($rows.Note -join ' ') | Should -Not -Match 'not declared|not used'
            ($rows | Where-Object { $_.Name -eq 'SPSQL' }).Discovered | Should -BeTrue
        }

        It 'does not let a host-only declaration match a named-pipe alias to a named instance' {
            $pipe = ConvertFrom-SqlAliasRaw -Raw 'DBNMPNTW,\\SQL1\pipe\MSSQL$SP\sql\query'
            $script:fakeAliases['SPNP'] = [PSCustomObject]@{ Provider = $pipe.Provider; Protocol = $pipe.Protocol; Server = $pipe.Server; Instance = $pipe.Instance; Port = $pipe.Port; Bitness = 'both'; Raw = '' }
            $rows = @(Get-SqlAliasRow -FarmName 'CONTENT' -DiscoveredServers @('SPNP') -DeclaredServers @('SQL1'))
            ($rows | Where-Object { $_.Name -eq 'SPNP' }).Declared | Should -BeFalse
            ($rows | Where-Object { $_.Name -eq 'SQL1' }).Discovered | Should -BeFalse

            $rows = @(Get-SqlAliasRow -FarmName 'CONTENT' -DiscoveredServers @('SPNP') -DeclaredServers @('SQL1\SP'))
            ($rows | Where-Object { $_.Name -eq 'SPNP' }).Declared | Should -BeTrue
        }

        It 'reports no declared-vs-discovered note when no server is declared' {
            $script:fakeAliases['SPSQLCONTENT'] = New-FakeAlias -Server 'SQL1' -Instance ''
            $rows = @(Get-SqlAliasRow -FarmName 'CONTENT' -DiscoveredServers @('SPSQLCONTENT') -DeclaredServers @())
            $rows.Count | Should -Be 1
            $rows[0].Note | Should -BeNullOrEmpty
        }

        It 'still reports an alias defined in only one bitness' {
            $script:fakeAliases['SPSQLCONTENT'] = New-FakeAlias -Server 'SQL1' -Instance '' -Bitness '64-bit'
            $rows = @(Get-SqlAliasRow -FarmName 'CONTENT' -DiscoveredServers @('SPSQLCONTENT') -DeclaredServers @('SPSQLCONTENT'))
            $rows[0].Note | Should -Be 'alias defined only in 64-bit'
        }
    }

    It 'keeps the row shape consumed by the dashboard and the report' {
        $script:fakeAliases['SPSQLCONTENT'] = New-FakeAlias -Server 'SQL1' -Instance 'MSSQLSERVER'
        $rows = @(Get-SqlAliasRow -FarmName 'CONTENT' -DiscoveredServers @('SPSQLCONTENT') -DeclaredServers @('SQL1'))
        $rows[0].PSObject.Properties.Name | Should -Be @('Farm', 'Name', 'IsAlias', 'RealServer', 'Protocol', 'Port', 'Bitness', 'Discovered', 'Declared', 'Note', 'IsInfo')
        $rows[0].RealServer | Should -Be 'SQL1\MSSQLSERVER'
        $rows[0].IsInfo | Should -BeTrue
    }
}
