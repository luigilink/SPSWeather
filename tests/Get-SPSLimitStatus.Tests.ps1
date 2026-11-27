# Tests of the reads of the limit checks (#137): Get-SPSLimitFact (the facts of the farm, with fake SharePoint cmdlets),
# Get-SPSContentDatabaseUsedSize (the used size of the data, with a fake SQL connection) and Get-SPSLimitStatus (what it reads and
# when, and that it never stops a run).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force
    $script:cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))

    # The remote script block calls cmdlets that only exist on a SharePoint server
    function global:Get-SPContentDatabase {
        if ($global:SPSLimitTest.Throw) { throw 'the farm is not reachable' }
        $global:SPSLimitTest.Databases
    }
    function global:Get-SPWebApplication { $global:SPSLimitTest.WebApplications }
    function global:Get-SPManagedPath {
        param($WebApplication, [switch]$HostHeader)
        if ($HostHeader) { if ($global:SPSLimitTest.HostNamedThrows) { throw 'denied' }; return @(1..$global:SPSLimitTest.HostNamed | ForEach-Object { [PSCustomObject]@{ Name = "h$_" } }) }
        if ($WebApplication.PathsThrow) { throw 'denied' }
        @(1..$WebApplication.Paths | ForEach-Object { [PSCustomObject]@{ Name = "p$_" } })
    }
    function script:New-SpDatabase {
        param([string]$Name, [int]$Sites = 1, $Address = 'SQL1', $Rbs = $false, [switch]$RbsThrows)
        $settings = [PSCustomObject]@{ Rbs = $Rbs; Throws = [bool]$RbsThrows }
        $settings | Add-Member -MemberType ScriptMethod -Name Enabled -Value { if ($this.Throws) { throw 'not available' }; $this.Rbs }
        [PSCustomObject]@{ Name = $Name; Server = [PSCustomObject]@{ Address = $Address }; CurrentSiteCount = $Sites; WarningSiteCount = 9000; RemoteBlobStorageSettings = $settings }
    }
    function script:Set-Farm {
        param($Databases = @(), $WebApplications = @(), [int]$HostNamed = 0, [switch]$Throw, [switch]$HostNamedThrows)
        $global:SPSLimitTest = @{ Databases = $Databases; WebApplications = $WebApplications; HostNamed = $HostNamed; Throw = [bool]$Throw; HostNamedThrows = [bool]$HostNamedThrows }
    }
    function script:Invoke-Fact {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            Mock Invoke-SPSCommand { & $ScriptBlock @($Arguments) }
            Get-SPSLimitFact -Server 'APP1.contoso.com' -InstallAccount $Cred -Farm 'CONTENT'
        }
    }
}

AfterAll {
    foreach ($name in 'Get-SPContentDatabase', 'Get-SPWebApplication', 'Get-SPManagedPath') { Remove-Item -Path "Function:\global:$name" -ErrorAction SilentlyContinue }
    Remove-Variable -Name SPSLimitTest -Scope Global -ErrorAction SilentlyContinue
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSLimitFact' {
    It 'reads the content databases with their site count, their SQL server and whether Remote BLOB Storage is on' {
        Set-Farm -Databases @((New-SpDatabase -Name 'A' -Sites 12 -Address 'SQL1' -Rbs $true), (New-SpDatabase -Name 'B' -Sites 3 -Address 'SQL2'))
        $fact = Invoke-Fact
        $fact.Farm | Should -Be 'CONTENT'
        $fact.Error | Should -Be ''
        @($fact.ContentDatabases).Count | Should -Be 2
        $fact.ContentDatabases[0].Name | Should -Be 'A'
        $fact.ContentDatabases[0].SiteCount | Should -Be 12
        $fact.ContentDatabases[0].SqlServer | Should -Be 'SQL1'
        $fact.ContentDatabases[0].Rbs | Should -BeTrue
        $fact.ContentDatabases[1].Rbs | Should -BeFalse
        $fact.ContentDatabases[1].SqlServer | Should -Be 'SQL2'
    }

    It 'says nothing (not false) about Remote BLOB Storage when it cannot be read' {
        Set-Farm -Databases @(New-SpDatabase -Name 'A' -RbsThrows)
        $fact = Invoke-Fact
        $fact.ContentDatabases[0].Rbs | Should -BeNullOrEmpty
        $fact.Error | Should -Be ''
    }

    It 'counts the web applications and the managed paths of each, and the host-named ones' {
        Set-Farm -WebApplications @([PSCustomObject]@{ Name = 'Intranet'; Paths = 4; PathsThrow = $false }, [PSCustomObject]@{ Name = 'Extranet'; Paths = 22; PathsThrow = $false }) -HostNamed 2
        $fact = Invoke-Fact
        $fact.WebApplicationCount | Should -Be 2
        $fact.WebApplications[1].Name | Should -Be 'Extranet'
        $fact.WebApplications[1].PathCount | Should -Be 22
        $fact.HostNamedManagedPathCount | Should -Be 2
    }

    It 'leaves a count that cannot be read empty, and keeps the rest' {
        Set-Farm -Databases @(New-SpDatabase -Name 'A') -WebApplications @([PSCustomObject]@{ Name = 'Intranet'; Paths = 1; PathsThrow = $true }) -HostNamedThrows
        $fact = Invoke-Fact
        $fact.WebApplications[0].PathCount | Should -BeNullOrEmpty
        $fact.HostNamedManagedPathCount | Should -BeNullOrEmpty
        @($fact.ContentDatabases).Count | Should -Be 1
        $fact.Error | Should -Be ''
    }

    It 'returns the error as a text, with no fact, when the farm cannot be read, and never throws' {
        Set-Farm -Throw
        { Invoke-Fact } | Should -Not -Throw
        $fact = Invoke-Fact
        $fact.Error | Should -Match 'the farm is not reachable'
        @($fact.ContentDatabases).Count | Should -Be 0
        $fact.WebApplicationCount | Should -BeNullOrEmpty
    }

    It 'is an empty farm without error when there is nothing' {
        Set-Farm
        $fact = Invoke-Fact
        $fact.Error | Should -Be ''
        @($fact.ContentDatabases).Count | Should -Be 0
        $fact.WebApplicationCount | Should -Be 0
    }

    It 'only reads: no cmdlet that changes anything, and the thresholds never travel to the remote side' {
        $source = Get-Content -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common/Private/Get-SPSLimitFact.ps1') -Raw
        $code = [regex]::Replace($source, '(?s)<#.*?#>', '')
        $code | Should -Not -Match '\b(Set|New|Remove|Add|Start|Stop|Move|Update|Enable|Disable)-SP\w*'
        $code | Should -Match '-Arguments @\{ Farm = \$Farm \}'
        $code | Should -Not -Match 'Threshold|\$Setting|\.Failure\b|\.Warning\b'
    }
}

Describe 'Get-SPSContentDatabaseUsedSize' {
    It 'returns nothing, and calls nothing, for no database' {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            Mock Invoke-SPSCommand { throw 'must not be called' }
            @(Get-SPSContentDatabaseUsedSize -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Database @()).Count | Should -Be 0
            Should -Invoke Invoke-SPSCommand -Times 0 -Exactly
        }
    }

    It 'sends only the names and the SQL servers, and the farm, to the remote side' {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            Mock Invoke-SPSCommand { $null } -ParameterFilter { $true }
            $null = Get-SPSContentDatabaseUsedSize -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Database @([PSCustomObject]@{ Name = 'A'; SqlServer = 'SQL1'; SiteCount = 99; Rbs = $true })
            Should -Invoke Invoke-SPSCommand -Times 1 -Exactly -ParameterFilter {
                $sent = @($Arguments)[0]
                $sent.Farm -eq 'F' -and @($sent.Database).Count -eq 1 -and $sent.Database[0].Name -eq 'A' -and $sent.Database[0].SqlServer -eq 'SQL1' -and $sent.Database[0].Keys.Count -eq 2
            }
        }
    }

    It 'asks the data files only, in the context of the database, with a time limit, and reads nothing else' {
        $source = Get-Content -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common/Private/Get-SPSContentDatabaseUsedSize.ps1') -Raw
        $source | Should -Match "FILEPROPERTY\(name, 'SpaceUsed'\)"
        $source | Should -Match 'WHERE type = 0'
        $source | Should -Match 'Initial Catalog.\] = "\$\(\$target\.Name\)"'
        $source | Should -Match 'Integrated Security'
        $source | Should -Match 'CommandTimeout = 30'
        $source | Should -Match 'Connect Timeout'
        $source | Should -Not -Match '(?i)\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|EXEC|TRUNCATE|SHRINK|BACKUP|RESTORE)\b'
    }

    It 'never puts the name of a database in the text of the query (an object name is never a part of SQL)' {
        $source = Get-Content -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common/Private/Get-SPSContentDatabaseUsedSize.ps1') -Raw
        $query = [regex]::Match($source, 'CommandText = "([^"]*)"').Groups[1].Value
        $query | Should -Not -Match '\$'
    }

    It 'gives the size of a database in MB, or its error without a size, for each database, and does not stop at the first error' {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            # What the remote side returns for a server that does not answer: one row with its error
            Mock Invoke-SPSCommand {
                @(
                    [PSCustomObject]@{ Farm = 'F'; Name = 'A'; SqlServer = 'NOPE.invalid'; UsedDataMB = $null; Error = 'a network-related error' }
                    [PSCustomObject]@{ Farm = 'F'; Name = 'B'; SqlServer = 'SQL1'; UsedDataMB = [decimal]1536.5; Error = '' })
            }
            $rows = @(Get-SPSContentDatabaseUsedSize -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Database @([PSCustomObject]@{ Name = 'A'; SqlServer = 'NOPE.invalid' }, [PSCustomObject]@{ Name = 'B'; SqlServer = 'SQL1' }))
            $rows.Count | Should -Be 2
            $rows[0].UsedDataMB | Should -BeNullOrEmpty
            $rows[0].Error | Should -Match 'network-related'
            $rows[1].UsedDataMB | Should -Be 1536.5
        }
    }

    It 'stops reading when its time budget is spent, and answers the databases left with an error and no size' {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            Mock Invoke-SPSCommand { & $ScriptBlock @($Arguments) }
            $targets = @(1..4 | ForEach-Object { [PSCustomObject]@{ Name = "DB$_"; SqlServer = '127.0.0.1,1' } })
            $rows = @(Get-SPSContentDatabaseUsedSize -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Database $targets -TimeBudgetSeconds 0)
            $rows.Count | Should -Be 4
            foreach ($row in $rows) {
                $row.UsedDataMB | Should -BeNullOrEmpty
                $row.Error | Should -Match 'time budget of 0 seconds'
                $row.Error | Should -Not -Match 'network|connect|server was not found'
            }
            @($rows.Name) | Should -Be @('DB1', 'DB2', 'DB3', 'DB4')
        }
    }

    It 'has a time budget of two minutes by default, that is handed to the remote side, and checks it before each database' {
        $source = Get-Content -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common/Private/Get-SPSContentDatabaseUsedSize.ps1') -Raw
        $source | Should -Match '\$TimeBudgetSeconds = 120'
        $source | Should -Match 'TimeBudgetSeconds = \$TimeBudgetSeconds'
        $source | Should -Match '(?s)foreach \(\$target in .*?\) \{\s*\$row = .*?\[System\.DateTime\]::UtcNow -ge \$deadline'
    }

    It 'returns the error of a server that cannot be reached, with a real connection that fails at once' {
        # The remote block runs here, against a SQL server that does not exist: it must return the error and not throw
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            Mock Invoke-SPSCommand { & $ScriptBlock @($Arguments) }
            $rows = @(Get-SPSContentDatabaseUsedSize -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Database @([PSCustomObject]@{ Name = 'A'; SqlServer = '127.0.0.1,1' }))
            $rows.Count | Should -Be 1
            $rows[0].UsedDataMB | Should -BeNullOrEmpty
            $rows[0].Error | Should -Not -BeNullOrEmpty
            $rows[0].Name | Should -Be 'A'
            $rows[0].Farm | Should -Be 'F'
        } 
    } 
}

Describe 'Get-SPSLimitStatus' {
    BeforeAll {
        function script:New-Call {
            param($Setting, $Fact, $Used = @(), $Sql = @(), [switch]$FactThrows, [switch]$UsedThrows, [switch]$RowThrows)
            InModuleScope SPSWeather.Common -Parameters @{ A = @{ Setting = $Setting; Fact = $Fact; Used = $Used; Sql = $Sql; FactThrows = [bool]$FactThrows; UsedThrows = [bool]$UsedThrows; RowThrows = [bool]$RowThrows }; Cred = $script:cred } {
                param($A, $Cred)
                $script:argsSeen = @{}
                Mock Get-SPSLimitFact { if ($A.FactThrows) { throw 'remoting failed' }; $A.Fact }
                Mock Get-SPSContentDatabaseUsedSize { $script:argsSeen['Database'] = @($Database); if ($A.UsedThrows) { throw 'sql down' }; $A.Used }
                if ($A.RowThrows) { Mock Get-SPSLimitRow { throw 'judgement failed' } }
                $rows = @(Get-SPSLimitStatus -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Setting $A.Setting -SqlDatabase $A.Sql -WarningAction SilentlyContinue -WarningVariable w)
                [PSCustomObject]@{
                    Rows = $rows; Warnings = @($w); FactCalls = (Get-MockCallCount 'Get-SPSLimitFact'); UsedCalls = (Get-MockCallCount 'Get-SPSContentDatabaseUsedSize'); Database = $script:argsSeen['Database']
                }
            }
        }
        function script:Get-MockCallCount { param($Name) 0 }
    }

    It 'is exported, and judges nothing it cannot read: no fact, no row, a warning, no exception' {
        Get-Command -Name Get-SPSLimitStatus -Module SPSWeather.Common | Should -Not -BeNullOrEmpty
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            Mock Get-SPSLimitFact { throw 'remoting failed' }
            Mock Get-SPSContentDatabaseUsedSize { @() }
            $setting = Get-SPSWeatherLimitSetting -Config @{}
            $rows = @(Get-SPSLimitStatus -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Setting $setting -WarningVariable w -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 0
            "$w" | Should -Match "Limits of farm 'F': the farm could not be read \(remoting failed\)"
        }
    }

    It 'says that the farm could not be read when the fact carries an error, and leaves out what needs it' {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            Mock Get-SPSLimitFact { [PSCustomObject]@{ Error = 'access denied'; ContentDatabases = @(); WebApplicationCount = $null; WebApplications = @(); HostNamedManagedPathCount = $null } }
            $setting = Get-SPSWeatherLimitSetting -Config @{}
            $rows = @(Get-SPSLimitStatus -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Setting $setting -DistributedCache @([PSCustomObject]@{ Server = 'WFE2'; Size = '20480' }) -WarningVariable w -WarningAction SilentlyContinue)
            "$w" | Should -Match 'access denied'
            $rows.Count | Should -Be 1 -Because 'the checks that do not need the farm still run'
            $rows[0].Limit | Should -Be 'DistributedCacheSize'
        }
    }

    It 'does not read the farm at all when every check that needs it is off' {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            Mock Get-SPSLimitFact { throw 'must not be called' }
            $setting = Get-SPSWeatherLimitSetting -Config @{ Limits = @{ Disabled = @('ContentDatabaseSize', 'SiteCountPerDatabase', 'ContentDatabasesPerFarm', 'WebApplicationsPerFarm', 'ManagedPaths') } }
            $rows = @(Get-SPSLimitStatus -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Setting $setting -ApplicationPool @(1..12 | ForEach-Object { [PSCustomObject]@{ Server = 'W'; ApplicationPool = "p$_" } }))
            Should -Invoke Get-SPSLimitFact -Times 0 -Exactly
            $rows.Count | Should -Be 1
            $rows[0].Limit | Should -Be 'ApplicationPoolsPerServer'
        }
    }

    It 'reads the used size only of the databases whose allocated size reaches the warning threshold' {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            $script:asked = $null
            Mock Get-SPSLimitFact {
                [PSCustomObject]@{ Error = ''; WebApplicationCount = 1; WebApplications = @(); HostNamedManagedPathCount = 0
                    ContentDatabases = @(
                        [PSCustomObject]@{ Name = 'SMALL'; SqlServer = 'SQL1'; SiteCount = 1; Rbs = $false }
                        [PSCustomObject]@{ Name = 'AT'; SqlServer = 'SQL1'; SiteCount = 1; Rbs = $false }
                        [PSCustomObject]@{ Name = 'BIG'; SqlServer = 'SQL1'; SiteCount = 1; Rbs = $false }
                        [PSCustomObject]@{ Name = 'NOSQL'; SqlServer = 'SQL1'; SiteCount = 1; Rbs = $false }) }
            }
            Mock Get-SPSContentDatabaseUsedSize { $script:asked = @($Database.Name); @([PSCustomObject]@{ Name = 'BIG'; SqlServer = 'SQL1'; UsedDataMB = 160 * 1024; Error = '' }, [PSCustomObject]@{ Name = 'AT'; SqlServer = 'SQL1'; UsedDataMB = 100 * 1024; Error = '' }) }
            $sql = @(
                [PSCustomObject]@{ Name = 'SMALL'; SqlServer = 'SQL1'; DataSizeMB = 10 * 1024 }
                [PSCustomObject]@{ Name = 'AT'; SqlServer = 'SQL1'; DataSizeMB = 150 * 1024 }
                [PSCustomObject]@{ Name = 'BIG'; SqlServer = 'SQL1'; DataSizeMB = 210 * 1024 })
            $setting = Get-SPSWeatherLimitSetting -Config @{}
            $rows = @(Get-SPSLimitStatus -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Setting $setting -SqlDatabase $sql)
            Should -Invoke Get-SPSContentDatabaseUsedSize -Times 1 -Exactly
            @($script:asked | Sort-Object) | Should -Be @('AT', 'BIG')
            $rows.Count | Should -Be 1
            $rows[0].Object | Should -Be 'BIG'
            $rows[0].Status | Should -Be 'Warning' -Because 'the used size (160 GB) replaced the allocated one (210 GB)'
        }
    }

    It 'does not read any used size when no database reaches the threshold, when the check is off, or for an exempt database' -ForEach @(
        @{ Name = 'below'; Config = @{}; GB = 100 }
        @{ Name = 'off'; Config = @{ Limits = @{ Disabled = @('ContentDatabaseSize') } }; GB = 500 }
        @{ Name = 'exempt'; Config = @{ Limits = @{ Exceptions = @(@{ Limit = 'ContentDatabaseSize'; Object = 'DB'; Exempt = $true }) } }; GB = 500 }
        @{ Name = 'no warning threshold'; Config = @{ Limits = @{ ContentDatabaseSize = @{ Warning = $null; Failure = 200 } } }; GB = 500 }
    ) {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred; C = $Config; GB = $GB } {
            param($Cred, $C, $GB)
            Mock Get-SPSLimitFact { [PSCustomObject]@{ Error = ''; WebApplicationCount = 1; WebApplications = @(); HostNamedManagedPathCount = 0; ContentDatabases = @([PSCustomObject]@{ Name = 'DB'; SqlServer = 'SQL1'; SiteCount = 1; Rbs = $false }) } }
            Mock Get-SPSContentDatabaseUsedSize { throw 'must not be called' }
            $null = Get-SPSLimitStatus -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Setting (Get-SPSWeatherLimitSetting -Config $C) -SqlDatabase @([PSCustomObject]@{ Name = 'DB'; SqlServer = 'SQL1'; DataSizeMB = $GB * 1024 })
            Should -Invoke Get-SPSContentDatabaseUsedSize -Times 0 -Exactly
        }
    }

    It 'asks the used size of the database whose own allocated size reaches the threshold, not of one of the same name on another server' {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            $script:asked = @()
            Mock Get-SPSLimitFact {
                [PSCustomObject]@{ Error = ''; WebApplicationCount = 1; WebApplications = @(); HostNamedManagedPathCount = 0
                    ContentDatabases = @(
                        [PSCustomObject]@{ Name = 'WSS_Content'; SqlServer = 'SQL1'; SiteCount = 1; Rbs = $false }
                        [PSCustomObject]@{ Name = 'WSS_Content'; SqlServer = 'SQL2'; SiteCount = 1; Rbs = $false }) }
            }
            Mock Get-SPSContentDatabaseUsedSize { $script:asked = @($Database | ForEach-Object { "$($_.SqlServer)/$($_.Name)" }); @() }
            $sql = @(
                [PSCustomObject]@{ Name = 'WSS_Content'; SqlServer = 'SQL1'; DataSizeMB = 10 * 1024 }
                [PSCustomObject]@{ Name = 'WSS_Content'; SqlServer = 'SQL2'; DataSizeMB = 160 * 1024 })
            $null = Get-SPSLimitStatus -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Setting (Get-SPSWeatherLimitSetting -Config @{}) -SqlDatabase $sql
            $script:asked | Should -Be @('SQL2/WSS_Content')
            $script:asked = @()
            $null = Get-SPSLimitStatus -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Setting (Get-SPSWeatherLimitSetting -Config @{}) -SqlDatabase @($sql[0])
            $script:asked.Count | Should -Be 0 -Because 'the size of the other server must not stand for the size of this database'
        }
    }

    It 'keeps the allocated size and goes on when the used size cannot be read at all' {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            Mock Get-SPSLimitFact { [PSCustomObject]@{ Error = ''; WebApplicationCount = 1; WebApplications = @(); HostNamedManagedPathCount = 0; ContentDatabases = @([PSCustomObject]@{ Name = 'DB'; SqlServer = 'SQL1'; SiteCount = 1; Rbs = $false }) } }
            Mock Get-SPSContentDatabaseUsedSize { throw 'sql is down' }
            $rows = @(Get-SPSLimitStatus -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Setting (Get-SPSWeatherLimitSetting -Config @{}) -SqlDatabase @([PSCustomObject]@{ Name = 'DB'; SqlServer = 'SQL1'; DataSizeMB = 210 * 1024 }) -WarningVariable w -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 1
            $rows[0].Status | Should -Be 'Failure'
            $rows[0].Recommendation | Should -Match '\(allocated\)'
            "$w" | Should -Match 'the used size of the databases could not be read \(sql is down\)'
        }
    }

    It 'never throws, even when the judgement itself fails' {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            Mock Get-SPSLimitFact { [PSCustomObject]@{ Error = ''; WebApplicationCount = 1; WebApplications = @(); HostNamedManagedPathCount = 0; ContentDatabases = @() } }
            Mock Get-SPSLimitRow { throw 'judgement failed' }
            $rows = $null
            $failed = $null
            try { $rows = @(Get-SPSLimitStatus -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Setting (Get-SPSWeatherLimitSetting -Config @{}) -WarningVariable w -WarningAction SilentlyContinue) }
            catch { $failed = $_ }
            $failed | Should -BeNullOrEmpty
            $rows.Count | Should -Be 0
            "$w" | Should -Match 'the limits could not be judged \(judgement failed\)'
        }
    }

    It 'gives a farm below every threshold no row, with real reads simulated' {
        InModuleScope SPSWeather.Common -Parameters @{ Cred = $script:cred } {
            param($Cred)
            Mock Get-SPSLimitFact { [PSCustomObject]@{ Error = ''; WebApplicationCount = 3; WebApplications = @(); HostNamedManagedPathCount = 0; ContentDatabases = @([PSCustomObject]@{ Name = 'DB'; SqlServer = 'SQL1'; SiteCount = 5; Rbs = $false }) } }
            Mock Get-SPSContentDatabaseUsedSize { throw 'must not be called' }
            @(Get-SPSLimitStatus -Server 'APP1' -InstallAccount $Cred -Farm 'F' -Setting (Get-SPSWeatherLimitSetting -Config @{}) -SqlDatabase @([PSCustomObject]@{ Name = 'DB'; SqlServer = 'SQL1'; DataSizeMB = 1024 })).Count | Should -Be 0
        }
    }
}
