# Behavioural tests for the supported-limit checks (#137): the Limits block of the configuration (Get-SPSWeatherLimitSetting), the
# thresholds of an object with its exceptions (Get-SPSLimitThreshold, private) and the judgement of the facts of a farm
# (Get-SPSLimitRow, private, pure). The remote reads have their own file.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force

    function script:Get-Setting { param($Config) Get-SPSWeatherLimitSetting -Config $Config }
    function script:Get-Rows {
        param($Setting, $Fact = $null, $Sql = @(), $Status = @(), $Used = @(), $Cache = @(), $Pools = @(), $Topology = @())
        InModuleScope SPSWeather.Common -Parameters @{ A = @{ Farm = 'F'; Setting = $Setting; Fact = $Fact; SqlDatabase = $Sql; ContentDatabaseStatus = $Status; UsedSize = $Used; DistributedCache = $Cache; ApplicationPool = $Pools; SearchTopology = $Topology } } {
            param($A)
            @(Get-SPSLimitRow @A)
        }
    }
    function script:New-Fact {
        param($Databases = @(), [int]$WebApplications = 1, $Paths = @(), $HostNamed = 0)
        [PSCustomObject]@{ Farm = 'F'; Error = ''; ContentDatabases = @($Databases); WebApplicationCount = $WebApplications; WebApplications = @($Paths); HostNamedManagedPathCount = $HostNamed }
    }
    function script:New-Db {
        param([string]$Name = 'DB', [int]$Sites = 10, $Rbs = $false)
        [PSCustomObject]@{ Name = $Name; SqlServer = 'SQL1'; SiteCount = $Sites; WarningSiteCount = 9000; Rbs = $Rbs }
    }
    function script:New-Sql {
        param([string]$Name = 'DB', [double]$DataGB = 1)
        [PSCustomObject]@{ Name = $Name; SqlServer = 'SQL1'; DataSizeMB = $DataGB * 1024 }
    }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSWeatherLimitSetting' {
    Context 'defaults' {
        It 'gives the agreed thresholds when the block is absent, empty or not a table of the check' -ForEach @(
            @{ Name = 'absent'; Config = @{} }
            @{ Name = 'empty'; Config = @{ Limits = @{} } }
            @{ Name = 'a null configuration'; Config = $null }
        ) {
            $s = Get-Setting -Config $Config
            $s.Messages.Count | Should -Be 0
            $s.Checks['ContentDatabaseSize'].Warning | Should -Be 150
            $s.Checks['ContentDatabaseSize'].Failure | Should -Be 200
            $s.Checks['SiteCountPerDatabase'].Warning | Should -Be 5000
            $s.Checks['SiteCountPerDatabase'].Failure | Should -Be 10000
            $s.Checks['ContentDatabasesPerFarm'].Warning | Should -Be 375
            $s.Checks['ContentDatabasesPerFarm'].Failure | Should -Be 500
            $s.Checks['WebApplicationsPerFarm'].Warning | Should -Be 15
            $s.Checks['WebApplicationsPerFarm'].Failure | Should -Be 20
            $s.Checks['ManagedPaths'].Warning | Should -Be 21
            $s.Checks['ManagedPaths'].Failure | Should -BeNullOrEmpty
            $s.Checks['DistributedCacheSize'].Warning | Should -BeNullOrEmpty
            $s.Checks['DistributedCacheSize'].Failure | Should -Be 16
            $s.Checks['ApplicationPoolsPerServer'].Warning | Should -Be 11
            $s.Checks['ApplicationPoolsPerServer'].Failure | Should -BeNullOrEmpty
            @($s.Checks.Values | Where-Object -FilterScript { -not $_.Enabled }).Count | Should -Be 0
            @($s.Exceptions).Count | Should -Be 0
        }

        It 'says in the record that every value is a default' {
            $s = Get-Setting -Config @{}
            $s.Record.thresholds.'Limits.ContentDatabaseSize.Warning'.value | Should -Be 150
            $s.Record.thresholds.'Limits.ContentDatabaseSize.Warning'.source | Should -Be 'default'
            @($s.Record.disabled).Count | Should -Be 0
            $s.Record.exceptions | Should -Be 0
        }
    }

    Context 'thresholds' {
        It 'takes the values of the configuration, and says so' {
            $s = Get-Setting -Config @{ Limits = @{ ContentDatabaseSize = @{ Warning = 100; Failure = 150 } } }
            $s.Messages.Count | Should -Be 0
            $s.Checks['ContentDatabaseSize'].Warning | Should -Be 100
            $s.Checks['ContentDatabaseSize'].Failure | Should -Be 150
            $s.Record.thresholds.'Limits.ContentDatabaseSize.Failure'.source | Should -Be 'config'
            $s.Checks['SiteCountPerDatabase'].Warning | Should -Be 5000
        }

        It 'keeps the default of the one that is not written' {
            $s = Get-Setting -Config @{ Limits = @{ ContentDatabaseSize = @{ Failure = 180 } } }
            $s.Checks['ContentDatabaseSize'].Warning | Should -Be 150
            $s.Record.thresholds.'Limits.ContentDatabaseSize.Warning'.source | Should -Be 'default'
            $s.Record.thresholds.'Limits.ContentDatabaseSize.Failure'.source | Should -Be 'config'
        }

        It 'accepts a number written as text and a decimal' {
            $s = Get-Setting -Config @{ Limits = @{ ContentDatabaseSize = @{ Warning = '120.5'; Failure = '180.25' } } }
            $s.Messages.Count | Should -Be 0
            $s.Checks['ContentDatabaseSize'].Warning | Should -Be 120.5
            $s.Checks['ContentDatabaseSize'].Failure | Should -Be 180.25
        }

        It 'accepts zero, and a warning equal to the failure' {
            $zero = Get-Setting -Config @{ Limits = @{ ContentDatabaseSize = @{ Warning = 0; Failure = 0 } } }
            $zero.Messages.Count | Should -Be 0
            $zero.Checks['ContentDatabaseSize'].Failure | Should -Be 0
            $equal = Get-Setting -Config @{ Limits = @{ ContentDatabaseSize = @{ Warning = 100; Failure = 100 } } }
            $equal.Messages.Count | Should -Be 0
        }

        It 'takes an explicit $null as none, for the warning and for the failure' {
            $s = Get-Setting -Config @{ Limits = @{ ContentDatabaseSize = @{ Warning = $null; Failure = 200 }; ManagedPaths = @{ Warning = 30; Failure = $null } } }
            $s.Messages.Count | Should -Be 0
            $s.Checks['ContentDatabaseSize'].Warning | Should -BeNullOrEmpty
            $s.Checks['ContentDatabaseSize'].Warning -eq $null | Should -BeTrue
            $s.Checks['ContentDatabaseSize'].WarningSource | Should -Be 'config'
            $s.Checks['ManagedPaths'].Warning | Should -Be 30
        }

        It 'reports <Name>, never casts it, and keeps the defaults of the whole check' -ForEach @(
            @{ Name = 'a word'; Value = 'abc'; Shown = "got 'abc'" }
            @{ Name = 'a negative number'; Value = -5; Shown = 'got a value of type Int32' }
            @{ Name = 'a boolean'; Value = $true; Shown = 'got a value of type Boolean' }
            @{ Name = 'a blank'; Value = '   '; Shown = "got '   '" }
            @{ Name = 'a list'; Value = @(1, 2); Shown = 'got a value of type Object' }
        ) {
            $s = Get-Setting -Config @{ Limits = @{ ContentDatabaseSize = @{ Warning = 100; Failure = $Value } } }
            $s.Messages.Count | Should -Be 1
            $s.Messages[0] | Should -Match 'Limits\.ContentDatabaseSize\.Failure must be a number of 0 or more'
            $s.Messages[0] | Should -Match $Shown
            $s.Checks['ContentDatabaseSize'].Warning | Should -Be 150 -Because 'a check is never half configured'
            $s.Checks['ContentDatabaseSize'].Failure | Should -Be 200
            $s.Checks['ContentDatabaseSize'].FailureSource | Should -Be 'default'
        }

        It 'reports a warning above the failure and keeps the defaults' {
            $s = Get-Setting -Config @{ Limits = @{ ContentDatabaseSize = @{ Warning = 300; Failure = 200 } } }
            $s.Messages.Count | Should -Be 1
            $s.Messages[0] | Should -Match 'the warning \(300\) is above the failure \(200\)'
            $s.Checks['ContentDatabaseSize'].Warning | Should -Be 150
        }

        It 'reports a setting that is not a table, an unknown check and an unknown setting of a check' {
            $s = Get-Setting -Config @{ Limits = @{ ContentDatabaseSize = 'big'; Surprise = 1; SiteCountPerDatabase = @{ Warning = 4000; Colour = 'red' } } }
            $s.Messages.Count | Should -Be 3
            ($s.Messages -join "`n") | Should -Match 'Limits\.ContentDatabaseSize must be a table'
            ($s.Messages -join "`n") | Should -Match 'Limits\.Surprise is not a known setting'
            ($s.Messages -join "`n") | Should -Match 'Limits\.SiteCountPerDatabase\.Colour is not a known setting'
            $s.Checks['SiteCountPerDatabase'].Warning | Should -Be 4000 -Because 'the valid part of a check is kept'
        }

        It 'reports a Limits value that is not a table, for <Name>, and uses the defaults' -ForEach @(
            @{ Name = 'text'; Value = 'maybe' }
            @{ Name = 'a number'; Value = 1 }
            @{ Name = 'a list'; Value = @(1, 2) }
            @{ Name = 'a boolean'; Value = $true }
        ) {
            $s = Get-Setting -Config @{ Limits = $Value }
            $s.Messages.Count | Should -Be 1
            $s.Messages[0] | Should -Match 'Limits must be a table of settings'
            $s.Checks['ContentDatabaseSize'].Failure | Should -Be 200
        }

        It 'has no threshold to set for the search topology, and says so' {
            $s = Get-Setting -Config @{ Limits = @{ SearchTopology = @{ Failure = 5 } } }
            $s.Messages.Count | Should -Be 1
            $s.Messages[0] | Should -Match 'Limits\.SearchTopology has no threshold to set'
        }
    }

    Context 'checks that are turned off' {
        It 'turns off a check by its name, in any case of the list' -ForEach @(
            @{ Name = 'a list'; Value = @('ManagedPaths', 'SearchTopology') }
            @{ Name = 'a single name'; Value = 'ManagedPaths' }
        ) {
            $s = Get-Setting -Config @{ Limits = @{ Disabled = $Value } }
            $s.Checks['ManagedPaths'].Enabled | Should -BeFalse
            $s.Checks['ContentDatabaseSize'].Enabled | Should -BeTrue
            $s.Record.disabled | Should -Contain 'Limits.ManagedPaths'
            $s.Messages.Count | Should -Be 0
        }

        It 'reports a name that is not a check, and a Disabled that is not a list' -ForEach @(
            @{ Name = 'an unknown name'; Value = @('Nope'); Expected = "holds 'Nope'" }
            @{ Name = 'a number in the list'; Value = @(5); Expected = 'a value of type Int32' }
            @{ Name = 'a table'; Value = @{ ManagedPaths = $true }; Expected = 'must be a list of check names' }
            @{ Name = 'a number'; Value = 5; Expected = 'must be a list of check names' }
        ) {
            $s = Get-Setting -Config @{ Limits = @{ Disabled = $Value } }
            $s.Messages.Count | Should -Be 1
            $s.Messages[0] | Should -Match $Expected
            @($s.Checks.Values | Where-Object -FilterScript { -not $_.Enabled }).Count | Should -Be 0
        }
    }

    Context 'exceptions' {
        It 'reads an exception with its thresholds and its reason, or an exemption, and a single table' {
            $s = Get-Setting -Config @{ Limits = @{ Exceptions = @(
                        @{ Limit = 'ContentDatabaseSize'; Object = 'ARCHIVE'; Warning = 3000; Failure = 4000; Reason = 'document archive' }
                        @{ Limit = 'SiteCountPerDatabase'; Object = 'OLD'; Exempt = $true }) } }
            $s.Messages.Count | Should -Be 0
            @($s.Exceptions).Count | Should -Be 2
            $s.Exceptions[0].Warning | Should -Be 3000
            $s.Exceptions[0].Reason | Should -Be 'document archive'
            $s.Exceptions[1].Exempt | Should -BeTrue
            $single = Get-Setting -Config @{ Limits = @{ Exceptions = @{ Limit = 'ContentDatabaseSize'; Object = 'A'; Exempt = 'true' } } }
            @($single.Exceptions).Count | Should -Be 1
            $single.Exceptions[0].Exempt | Should -BeTrue
        }

        It 'never records the name of an object in the journal record' {
            $s = Get-Setting -Config @{ Limits = @{ Exceptions = @(@{ Limit = 'ContentDatabaseSize'; Object = 'SECRET-DB-NAME'; Exempt = $true; Reason = 'private reason' }) } }
            $s.Record.exceptions | Should -Be 1
            ($s.Record | ConvertTo-Json -Depth 6) | Should -Not -Match 'SECRET-DB-NAME|private reason'
        }

        It 'ignores, and reports, an exception that cannot work: <Name>' -ForEach @(
            @{ Name = 'a text'; Item = 'text'; Expected = 'must be a table' }
            @{ Name = 'no Limit'; Item = @{ Object = 'a'; Exempt = $true }; Expected = 'has no valid Limit' }
            @{ Name = 'an unknown Limit'; Item = @{ Limit = 'X'; Object = 'a'; Exempt = $true }; Expected = 'has no valid Limit' }
            @{ Name = 'no Object'; Item = @{ Limit = 'ContentDatabaseSize'; Exempt = $true }; Expected = 'has no Object' }
            @{ Name = 'a blank Object'; Item = @{ Limit = 'ContentDatabaseSize'; Object = '  '; Exempt = $true }; Expected = 'has no Object' }
            @{ Name = 'nothing to change'; Item = @{ Limit = 'ContentDatabaseSize'; Object = 'a' }; Expected = 'changes nothing' }
            @{ Name = 'an Exempt that is not a boolean'; Item = @{ Limit = 'ContentDatabaseSize'; Object = 'a'; Exempt = 'maybe' }; Expected = 'Exempt must be \$true or \$false' }
            @{ Name = 'a threshold that is not a number'; Item = @{ Limit = 'ContentDatabaseSize'; Object = 'a'; Warning = 'x' }; Expected = 'must be a number of 0 or more' }
            @{ Name = 'a warning above the failure'; Item = @{ Limit = 'ContentDatabaseSize'; Object = 'a'; Warning = 9; Failure = 1 }; Expected = 'the warning \(9\) is above the failure \(1\)' }
            @{ Name = 'a threshold for the search topology'; Item = @{ Limit = 'SearchTopology'; Object = 'a'; Failure = 3 }; Expected = 'has no threshold to set' }
        ) {
            $s = Get-Setting -Config @{ Limits = @{ Exceptions = @($Item) } }
            @($s.Exceptions).Count | Should -Be 0
            $s.Messages.Count | Should -Be 1
            $s.Messages[0] | Should -Match $Expected
            $s.Messages[0] | Should -Match 'Limits\.Exceptions\[1\]|Exceptions\[1\]'
        }

        It 'keeps the valid exceptions next to the invalid one, and numbers the message by position' {
            $s = Get-Setting -Config @{ Limits = @{ Exceptions = @(
                        @{ Limit = 'ContentDatabaseSize'; Object = 'a'; Exempt = $true }
                        'bad'
                        @{ Limit = 'ContentDatabaseSize'; Object = 'b'; Exempt = $true }) } }
            @($s.Exceptions).Count | Should -Be 2
            $s.Messages[0] | Should -Match 'Exceptions\[2\]'
        }

        It 'reports an Exceptions value that is not a list of tables' -ForEach @(
            @{ Name = 'text'; Value = 'a' }
            @{ Name = 'a number'; Value = 1 }
            @{ Name = '$null'; Value = $null }
        ) {
            $s = Get-Setting -Config @{ Limits = @{ Exceptions = $Value } }
            $s.Messages.Count | Should -Be 1
            $s.Messages[0] | Should -Match 'Limits\.Exceptions must be a list of tables'
            @($s.Exceptions).Count | Should -Be 0
        }
    }

    It 'never throws, whatever the configuration holds' {
        foreach ($config in @($null, @{ Limits = $null }, @{ Limits = @{ Disabled = @($null, 1, @{}) ; Exceptions = @($null, @{}, 5) } }, @{ Limits = @{ ContentDatabaseSize = @{ Warning = [double]::NaN; Failure = [double]::PositiveInfinity } } })) {
            { Get-Setting -Config $config } | Should -Not -Throw
        }
        $s = Get-Setting -Config @{ Limits = @{ ContentDatabaseSize = @{ Warning = [double]::NaN; Failure = [double]::PositiveInfinity } } }
        $s.Checks['ContentDatabaseSize'].Failure | Should -Be 200
    }
}

Describe 'Get-SPSLimitThreshold' {
    BeforeAll {
        $script:setting = Get-Setting -Config @{ Limits = @{ Exceptions = @(
                    @{ Limit = 'ContentDatabaseSize'; Object = 'ARCHIVE'; Warning = 3000; Failure = 4000; Reason = 'document archive' }
                    @{ Limit = 'ContentDatabaseSize'; Object = 'SHARED'; Failure = 500 }
                    @{ Limit = 'ContentDatabaseSize'; Object = 'IGNORED'; Exempt = $true }
                    @{ Limit = 'ContentDatabaseSize'; Object = 'IGNORED'; Failure = 1 }
                    @{ Limit = 'SiteCountPerDatabase'; Object = 'ARCHIVE'; Exempt = $true }
                    @{ Limit = 'ContentDatabaseSize'; Object = 'NOWARNING'; Warning = $null }) } }
        function script:Get-Threshold {
            param([string]$Limit, [string]$Object)
            InModuleScope SPSWeather.Common -Parameters @{ S = $script:setting; L = $Limit; O = $Object } { param($S, $L, $O) Get-SPSLimitThreshold -Setting $S -Limit $L -Object $O }
        }
    }

    It 'gives the thresholds of the check to an object that has no exception' {
        $t = Get-Threshold -Limit 'ContentDatabaseSize' -Object 'OTHER'
        $t.Enabled | Should -BeTrue
        $t.Warning | Should -Be 150
        $t.Failure | Should -Be 200
        $t.Reason | Should -Be ''
    }

    It 'gives an object the thresholds of its exception, with the reason' {
        $t = Get-Threshold -Limit 'ContentDatabaseSize' -Object 'ARCHIVE'
        $t.Warning | Should -Be 3000
        $t.Failure | Should -Be 4000
        $t.Reason | Should -Be 'document archive'
    }

    It 'changes only what the exception names' {
        $t = Get-Threshold -Limit 'ContentDatabaseSize' -Object 'SHARED'
        $t.Warning | Should -Be 150
        $t.Failure | Should -Be 500
    }

    It 'matches the object without regard to case' {
        (Get-Threshold -Limit 'ContentDatabaseSize' -Object 'archive').Failure | Should -Be 4000
    }

    It 'applies an exception to its own check only' {
        (Get-Threshold -Limit 'SiteCountPerDatabase' -Object 'ARCHIVE').Enabled | Should -BeFalse
        (Get-Threshold -Limit 'ContentDatabaseSize' -Object 'ARCHIVE').Enabled | Should -BeTrue
    }

    It 'takes the first exception that names the object' {
        $t = Get-Threshold -Limit 'ContentDatabaseSize' -Object 'IGNORED'
        $t.Enabled | Should -BeFalse
        $t.Failure | Should -Be 200 -Because 'the second exception of the object is not read'
    }

    It 'takes an explicit $null of an exception as no threshold' {
        $t = Get-Threshold -Limit 'ContentDatabaseSize' -Object 'NOWARNING'
        $t.Warning -eq $null | Should -BeTrue
        $t.Failure | Should -Be 200
    }

    It 'is off for a check that is turned off, and for a check that does not exist' {
        $off = Get-Setting -Config @{ Limits = @{ Disabled = @('ManagedPaths') } }
        (InModuleScope SPSWeather.Common -Parameters @{ S = $off } { param($S) Get-SPSLimitThreshold -Setting $S -Limit 'ManagedPaths' -Object 'x' }).Enabled | Should -BeFalse
        (Get-Threshold -Limit 'NoSuchCheck' -Object 'x').Enabled | Should -BeFalse
    }
}

Describe 'Get-SPSLimitRow' {
    BeforeAll { $script:defaults = Get-Setting -Config @{} }

    Context 'a farm below every threshold' {
        It 'gives no row' {
            $rows = Get-Rows -Setting $defaults -Fact (New-Fact -Databases @((New-Db -Name 'A' -Sites 100), (New-Db -Name 'B')) -WebApplications 3 -Paths @([PSCustomObject]@{ Name = 'W'; PathCount = 5 }) -HostNamed 2) `
                -Sql @((New-Sql -Name 'A' -DataGB 10), (New-Sql -Name 'B' -DataGB 149.9)) `
                -Cache @([PSCustomObject]@{ Server = 'WFE1'; Size = '2048' }, [PSCustomObject]@{ Server = 'APP1'; Size = '' }) `
                -Pools @(1..10 | ForEach-Object { [PSCustomObject]@{ Server = 'WFE1'; ApplicationPool = "p$_" } }) `
                -Topology @([PSCustomObject]@{ ComponentHost = 'APP1'; ComponentName = 'CrawlComponent1' }, [PSCustomObject]@{ ComponentHost = 'NotApplicable'; ComponentName = 'Partition:0' })
            $rows.Count | Should -Be 0
        }

        It 'gives no row for no fact at all, whatever the other sections hold' {
            (Get-Rows -Setting $defaults -Fact $null).Count | Should -Be 0
            (Get-Rows -Setting $defaults -Fact ([PSCustomObject]@{ Error = 'the farm is down' })).Count | Should -Be 0
        }
    }

    Context 'the size of a content database' {
        It 'warns from the warning threshold and fails above the limit, and not at the limit itself' -ForEach @(
            @{ GB = 149.99; Status = $null }
            @{ GB = 150; Status = 'Warning' }
            @{ GB = 175; Status = 'Warning' }
            @{ GB = 200; Status = 'Warning' }
            @{ GB = 200.01; Status = 'Failure' }
            @{ GB = 900; Status = 'Failure' }
        ) {
            $rows = Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db -Name 'DB')) -Sql @(New-Sql -Name 'DB' -DataGB $GB)
            if ($null -eq $Status) { $rows.Count | Should -Be 0 }
            else {
                $rows.Count | Should -Be 1
                $rows[0].Status | Should -Be $Status
                $rows[0].Limit | Should -Be 'ContentDatabaseSize'
                $rows[0].Object | Should -Be 'DB'
                $rows[0].Farm | Should -Be 'F'
            }
        }

        It 'follows the severity model: a warning is an information row with a recommendation, a failure is not' {
            $warn = (Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db)) -Sql @(New-Sql -DataGB 160))[0]
            $fail = (Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db)) -Sql @(New-Sql -DataGB 210))[0]
            $warn.IsInfo | Should -BeTrue
            $warn.Recommendation | Should -Not -BeNullOrEmpty
            $fail.IsInfo | Should -BeFalse
            InModuleScope SPSWeather.Common -Parameters @{ W = $warn; F = $fail } { param($W, $F) Get-SPSWeatherRowSeverity -Row $W } | Should -Be 'warn'
            InModuleScope SPSWeather.Common -Parameters @{ W = $warn; F = $fail } { param($W, $F) Get-SPSWeatherRowSeverity -Row $F } | Should -Be 'fail'
        }

        It 'uses the used size when it was read, even when the allocated one is far above the limit' {
            $rows = Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db)) -Sql @(New-Sql -DataGB 210) -Used @([PSCustomObject]@{ Name = 'DB'; UsedDataMB = 160 * 1024; Error = '' })
            $rows.Count | Should -Be 1
            $rows[0].Status | Should -Be 'Warning'
            $rows[0].Value | Should -Be 160
            $rows[0].Recommendation | Should -Match '\(used\)'
        }

        It 'does not alert for a database whose used size is under the threshold, whatever the file was pre-sized to' {
            (Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db)) -Sql @(New-Sql -DataGB 900) -Used @([PSCustomObject]@{ Name = 'DB'; UsedDataMB = 100 * 1024; Error = '' })).Count | Should -Be 0
        }

        It 'falls back to the allocated size and says why when the used size could not be read' {
            $rows = Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db)) -Sql @(New-Sql -DataGB 210) -Used @([PSCustomObject]@{ Name = 'DB'; UsedDataMB = $null; Error = 'login failed' })
            $rows[0].Status | Should -Be 'Failure'
            $rows[0].Recommendation | Should -Match 'allocated; the used size could not be read: login failed'
        }

        It 'says the size is the allocated one when no used size was asked' {
            (Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db)) -Sql @(New-Sql -DataGB 210))[0].Recommendation | Should -Match '\(allocated\)'
        }

        It 'uses the size that SharePoint reports, and says that it includes the log, only when the SQL rows are not there' {
            $status = @([PSCustomObject]@{ DatabaseName = 'DB'; Type = 'Content Database'; DiskSize = '210' })
            $rows = Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db)) -Status $status
            $rows[0].Recommendation | Should -Match 'as reported by SharePoint, log included'
            (Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db)) -Status $status -Sql @(New-Sql -DataGB 5)).Count | Should -Be 0
        }

        It 'never counts the log: a big log does not make a small database big' {
            $sql = @([PSCustomObject]@{ Name = 'DB'; SqlServer = 'SQL1'; DataSizeMB = 10 * 1024; LogSizeMB = 400 * 1024 })
            (Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db)) -Sql $sql).Count | Should -Be 0
        }

        It 'does not take the size of a database of the same name on another SQL server when its own is there' {
            $sql = @([PSCustomObject]@{ Name = 'DB'; SqlServer = 'OTHER'; DataSizeMB = 900 * 1024 }, [PSCustomObject]@{ Name = 'DB'; SqlServer = 'SQL1'; DataSizeMB = 10 * 1024 })
            (Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db)) -Sql $sql).Count | Should -Be 0
        }

        It 'notes that Remote BLOB Storage is not counted, and only for a database that has it' {
            $rbs = (Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db -Rbs $true)) -Sql @(New-Sql -DataGB 160))[0]
            $none = (Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db -Rbs $false)) -Sql @(New-Sql -DataGB 160))[0]
            $unknown = (Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db -Rbs $null)) -Sql @(New-Sql -DataGB 160))[0]
            $rbs.Note | Should -Match 'Remote BLOB Storage is enabled'
            $none.Note | Should -Be ''
            $unknown.Note | Should -Be ''
        }

        It 'gives a database its exception, and leaves the others on the default' {
            $setting = Get-Setting -Config @{ Limits = @{ Exceptions = @(@{ Limit = 'ContentDatabaseSize'; Object = 'ARCHIVE'; Warning = 3000; Failure = 4000; Reason = 'document archive' }) } }
            $rows = Get-Rows -Setting $setting -Fact (New-Fact -Databases @((New-Db -Name 'ARCHIVE'), (New-Db -Name 'OTHER'))) -Sql @((New-Sql -Name 'ARCHIVE' -DataGB 900), (New-Sql -Name 'OTHER' -DataGB 210))
            $rows.Count | Should -Be 1
            $rows[0].Object | Should -Be 'OTHER'
            $over = Get-Rows -Setting $setting -Fact (New-Fact -Databases @(New-Db -Name 'ARCHIVE')) -Sql @(New-Sql -Name 'ARCHIVE' -DataGB 4100)
            $over[0].Status | Should -Be 'Failure'
            $over[0].Recommendation | Should -Match 'Exception: document archive'
        }

        It 'does not look at an exempt database, and does not look at all when the check is off' {
            $exempt = Get-Setting -Config @{ Limits = @{ Exceptions = @(@{ Limit = 'ContentDatabaseSize'; Object = 'DB'; Exempt = $true }) } }
            (Get-Rows -Setting $exempt -Fact (New-Fact -Databases @(New-Db)) -Sql @(New-Sql -DataGB 900)).Count | Should -Be 0
            $off = Get-Setting -Config @{ Limits = @{ Disabled = @('ContentDatabaseSize') } }
            (Get-Rows -Setting $off -Fact (New-Fact -Databases @(New-Db)) -Sql @(New-Sql -DataGB 900)).Count | Should -Be 0
        }

        It 'uses the thresholds of the configuration' {
            $setting = Get-Setting -Config @{ Limits = @{ ContentDatabaseSize = @{ Warning = 1; Failure = 2 } } }
            (Get-Rows -Setting $setting -Fact (New-Fact -Databases @(New-Db)) -Sql @(New-Sql -DataGB 1.5))[0].Status | Should -Be 'Warning'
            (Get-Rows -Setting $setting -Fact (New-Fact -Databases @(New-Db)) -Sql @(New-Sql -DataGB 2.5))[0].Status | Should -Be 'Failure'
        }
    }

    Context 'the other limits of the farm' {
        It 'counts the site collections of a database: warning from 5000, failure above 10000' -ForEach @(
            @{ Sites = 4999; Status = $null }, @{ Sites = 5000; Status = 'Warning' }, @{ Sites = 10000; Status = 'Warning' }, @{ Sites = 10001; Status = 'Failure' }
        ) {
            $rows = Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db -Sites $Sites))
            if ($null -eq $Status) { $rows.Count | Should -Be 0 } else { $rows.Count | Should -Be 1; $rows[0].Status | Should -Be $Status; $rows[0].Limit | Should -Be 'SiteCountPerDatabase' }
        }

        It 'counts the content databases of the farm: warning from 375, failure above 500' -ForEach @(
            @{ Count = 374; Status = $null }, @{ Count = 375; Status = 'Warning' }, @{ Count = 500; Status = 'Warning' }, @{ Count = 501; Status = 'Failure' }
        ) {
            $databases = @(1..$Count | ForEach-Object { New-Db -Name "DB$_" })
            $rows = Get-Rows -Setting $defaults -Fact (New-Fact -Databases $databases)
            if ($null -eq $Status) { $rows.Count | Should -Be 0 } else { $rows.Count | Should -Be 1; $rows[0].Status | Should -Be $Status; $rows[0].Limit | Should -Be 'ContentDatabasesPerFarm'; $rows[0].Object | Should -Be 'F' }
        }

        It 'counts the web applications: warning from 15, failure above 20' -ForEach @(
            @{ Count = 14; Status = $null }, @{ Count = 15; Status = 'Warning' }, @{ Count = 20; Status = 'Warning' }, @{ Count = 21; Status = 'Failure' }
        ) {
            $rows = Get-Rows -Setting $defaults -Fact (New-Fact -WebApplications $Count)
            if ($null -eq $Status) { $rows.Count | Should -Be 0 } else { $rows.Count | Should -Be 1; $rows[0].Status | Should -Be $Status; $rows[0].Limit | Should -Be 'WebApplicationsPerFarm' }
        }

        It 'warns, and never fails, above 20 managed paths of a web application and above 20 host-named ones' -ForEach @(
            @{ Count = 20; Status = $null }, @{ Count = 21; Status = 'Warning' }, @{ Count = 400; Status = 'Warning' }
        ) {
            $rows = Get-Rows -Setting $defaults -Fact (New-Fact -Paths @([PSCustomObject]@{ Name = 'Intranet'; PathCount = $Count }) -HostNamed $Count)
            if ($null -eq $Status) { $rows.Count | Should -Be 0 }
            else {
                $rows.Count | Should -Be 2
                @($rows | Where-Object -FilterScript { $_.Status -ne 'Warning' }).Count | Should -Be 0
                @($rows.Object) | Should -Contain 'Intranet'
                @($rows.Object) | Should -Contain 'host-named site collections'
            }
        }

        It 'says nothing about a count that could not be read' {
            (Get-Rows -Setting $defaults -Fact (New-Fact -WebApplications 1 -Paths @([PSCustomObject]@{ Name = 'W'; PathCount = $null }) -HostNamed $null)).Count | Should -Be 0
            $fact = New-Fact; $fact.WebApplicationCount = $null
            (Get-Rows -Setting $defaults -Fact $fact).Count | Should -Be 0
        }

        It 'fails above 16 GB of memory for the Distributed Cache of a host (the section is in MB), and ignores a server that is not a cache host' {
            $rows = Get-Rows -Setting $defaults -Fact $null -Cache @(
                [PSCustomObject]@{ Server = 'A'; Size = '16384' }, [PSCustomObject]@{ Server = 'B'; Size = '16385' }
                [PSCustomObject]@{ Server = 'C'; Size = '' }, [PSCustomObject]@{ Server = 'D'; Size = $null }, [PSCustomObject]@{ Server = 'E'; Size = 'n/a' })
            $rows.Count | Should -Be 1
            $rows[0].Object | Should -Be 'B'
            $rows[0].Status | Should -Be 'Failure'
            $rows[0].Unit | Should -Be 'GB'
        }

        It 'counts the application pools of each server: warning from 11, never a failure' -ForEach @(
            @{ Count = 10; Status = $null }, @{ Count = 11; Status = 'Warning' }, @{ Count = 40; Status = 'Warning' }
        ) {
            $pools = @(1..$Count | ForEach-Object { [PSCustomObject]@{ Server = 'WFE1'; ApplicationPool = "p$_" } }) + @(1..3 | ForEach-Object { [PSCustomObject]@{ Server = 'WFE2'; ApplicationPool = "q$_" } })
            $rows = Get-Rows -Setting $defaults -Fact $null -Pools $pools
            if ($null -eq $Status) { $rows.Count | Should -Be 0 } else { $rows.Count | Should -Be 1; $rows[0].Object | Should -Be 'WFE1'; $rows[0].Status | Should -Be 'Warning' }
        }

        It 'ignores a pool row that has no server (an unreachable server is another check)' {
            $pools = @(1..20 | ForEach-Object { [PSCustomObject]@{ Server = ''; ApplicationPool = "p$_" } })
            (Get-Rows -Setting $defaults -Fact $null -Pools $pools).Count | Should -Be 0
        }

        It 'gives the same objects whatever the farm does with the other sections' {
            $rows = Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db -Sites 6000)) -Sql $null -Status $null -Cache $null -Pools $null -Topology $null
            $rows.Count | Should -Be 1
        }
    }

    Context 'the topology of the search service application' {
        It 'fails when a server holds more than the components that it can: <Name>' -ForEach @(
            @{ Name = 'two crawl components'; Component = 'CrawlComponent'; Count = 2; Expected = 'crawl components' }
            @{ Name = 'two content processing components'; Component = 'ContentProcessingComponent'; Count = 2; Expected = 'content processing components' }
            @{ Name = 'two query processing components'; Component = 'QueryProcessingComponent'; Count = 2; Expected = 'query processing components' }
            @{ Name = 'two analytics components'; Component = 'AnalyticsProcessingComponent'; Count = 2; Expected = 'analytics processing components' }
            @{ Name = 'five index components'; Component = 'IndexComponent'; Count = 5; Expected = 'index components' }
        ) {
            $rows = Get-Rows -Setting $defaults -Fact $null -Topology @(1..$Count | ForEach-Object { [PSCustomObject]@{ ComponentHost = 'APP1'; ComponentName = "$Component$_" } })
            $rows.Count | Should -Be 1
            $rows[0].Status | Should -Be 'Failure'
            $rows[0].Limit | Should -Be 'SearchTopology'
            $rows[0].Object | Should -Be "APP1 ($Expected)"
        }

        It 'allows what it allows: one of each, and four index components, on a server' {
            $topology = @(1..4 | ForEach-Object { [PSCustomObject]@{ ComponentHost = 'APP1'; ComponentName = "IndexComponent$_" } }) + @(
                'CrawlComponent1', 'ContentProcessingComponent1', 'QueryProcessingComponent1', 'AnalyticsProcessingComponent1', 'AdminComponent1' | ForEach-Object { [PSCustomObject]@{ ComponentHost = 'APP1'; ComponentName = $_ } })
            (Get-Rows -Setting $defaults -Fact $null -Topology $topology).Count | Should -Be 0
        }

        It 'counts a component of each server separately, and ignores the rows that are not on a server' {
            $topology = @(
                [PSCustomObject]@{ ComponentHost = 'APP1'; ComponentName = 'CrawlComponent1' }, [PSCustomObject]@{ ComponentHost = 'APP2'; ComponentName = 'CrawlComponent2' }
                [PSCustomObject]@{ ComponentHost = 'NotApplicable'; ComponentName = 'CrawlComponent3' }, [PSCustomObject]@{ ComponentHost = ''; ComponentName = 'CrawlComponent4' })
            (Get-Rows -Setting $defaults -Fact $null -Topology $topology).Count | Should -Be 0
        }

        It 'fails above the totals of the application: 16 crawl components, 25 partitions' {
            $crawl = @(1..17 | ForEach-Object { [PSCustomObject]@{ ComponentHost = "S$_"; ComponentName = "CrawlComponent$_" } })
            $partitions = @(0..25 | ForEach-Object { [PSCustomObject]@{ ComponentHost = 'NotApplicable'; ComponentName = "Partition:$_" } })
            $rows = Get-Rows -Setting $defaults -Fact $null -Topology ($crawl + $partitions)
            @($rows.Object | Sort-Object) | Should -Be @('F (crawl components)', 'F (index partitions)')
            (Get-Rows -Setting $defaults -Fact $null -Topology ($crawl | Select-Object -First 16)).Count | Should -Be 0
        }

        It 'is off when the check is off, and an exception can name one server' {
            $off = Get-Setting -Config @{ Limits = @{ Disabled = @('SearchTopology') } }
            $two = @(1..2 | ForEach-Object { [PSCustomObject]@{ ComponentHost = 'APP1'; ComponentName = "CrawlComponent$_" } })
            (Get-Rows -Setting $off -Fact $null -Topology $two).Count | Should -Be 0
            $exempt = Get-Setting -Config @{ Limits = @{ Exceptions = @(@{ Limit = 'SearchTopology'; Object = 'APP1 (crawl components)'; Exempt = $true }) } }
            (Get-Rows -Setting $exempt -Fact $null -Topology $two).Count | Should -Be 0
        }
    }

    Context 'the rows' {
        It 'carry the columns that the report, the email and the cockpit need, and a readable text' {
            $row = (Get-Rows -Setting $defaults -Fact (New-Fact -Databases @(New-Db -Name 'BIG')) -Sql @(New-Sql -Name 'BIG' -DataGB 210))[0]
            $row.PSObject.Properties.Name | Should -Contain 'Farm'
            foreach ($column in 'Limit', 'Object', 'Value', 'Unit', 'Warning', 'Failure', 'Status', 'Recommendation', 'Note', 'IsInfo') { $row.PSObject.Properties.Name | Should -Contain $column }
            $row.Recommendation | Should -Be 'Data size: 210 GB (allocated). Warning from 150 GB, failure above 200 GB.'
        }

        It 'says only the thresholds that exist' {
            (Get-Rows -Setting $defaults -Fact $null -Cache @([PSCustomObject]@{ Server = 'A'; Size = '20480' }))[0].Recommendation | Should -Be 'Memory of the cache host: 20 GB. Failure above 16 GB.'
            (Get-Rows -Setting $defaults -Fact $null -Pools @(1..12 | ForEach-Object { [PSCustomObject]@{ Server = 'W'; ApplicationPool = "p$_" } }))[0].Recommendation | Should -Be 'Application pools: 12. Warning from 11.'
        }
    }
}
