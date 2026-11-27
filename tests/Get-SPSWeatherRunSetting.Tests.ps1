# Behavioural tests for Get-SPSWeatherRunSetting: the single place that resolves the thresholds of a run
# and the part of them that the run journal records.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:keys = @('SQLDiskFreeThresholdPercent', 'SQLBackupMaxAgeDays', 'JsonHistoryRetentionDays', 'EmailMaxItemsPerArea', 'LogRetentionDays')
    $script:defaults = @{ SQLDiskFreeThresholdPercent = 15; SQLBackupMaxAgeDays = 3; JsonHistoryRetentionDays = 30; EmailMaxItemsPerArea = 10; LogRetentionDays = 180 }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSWeatherRunSetting' {
    Context 'defaults' {
        It 'uses the default of <Key> and says so when the configuration is empty, null or has no such key' -ForEach @(
            @{ Config = @{} }
            @{ Config = $null }
            @{ Config = @{ SomethingElse = 1 } }
        ) {
            $r = Get-SPSWeatherRunSetting -Config $Config
            foreach ($key in $keys) {
                $r.Value.$key | Should -Be $defaults[$key]
                $r.Record.thresholds.$key.value | Should -Be $defaults[$key]
                $r.Record.thresholds.$key.source | Should -Be 'default'
                $r.Record.thresholds.$key.Contains('invalid') | Should -BeFalse
                $r.Record.thresholds.$key.invalid | Should -BeNullOrEmpty
            }
            @($r.Messages).Count | Should -Be 0
        }

        It 'treats a key that is present with a null value as missing (default, not invalid)' {
            $r = Get-SPSWeatherRunSetting -Config @{ SQLBackupMaxAgeDays = $null }
            $r.Value.SQLBackupMaxAgeDays | Should -Be 3
            $r.Record.thresholds.SQLBackupMaxAgeDays.source | Should -Be 'default'
            @($r.Messages).Count | Should -Be 0
        }
    }

    Context 'values from the configuration' {
        It 'uses SQLBackupMaxAgeDays = <Raw> as <Expected> and records the source config' -ForEach @(
            @{ Raw = 8; Expected = 8 }
            @{ Raw = '8'; Expected = 8 }
            @{ Raw = ' 12 '; Expected = 12 }
            @{ Raw = 0; Expected = 0 }
            @{ Raw = 8.4; Expected = 8 }
        ) {
            $r = Get-SPSWeatherRunSetting -Config @{ SQLBackupMaxAgeDays = $Raw }
            $r.Value.SQLBackupMaxAgeDays | Should -Be $Expected
            $r.Value.SQLBackupMaxAgeDays | Should -BeOfType [int]
            $r.Record.thresholds.SQLBackupMaxAgeDays.value | Should -Be $Expected
            $r.Record.thresholds.SQLBackupMaxAgeDays.source | Should -Be 'config'
            @($r.Messages).Count | Should -Be 0
        }

        It 'resolves every threshold independently' {
            $r = Get-SPSWeatherRunSetting -Config @{ SQLDiskFreeThresholdPercent = 20; JsonHistoryRetentionDays = 7; LogRetentionDays = 60 }
            $r.Value.SQLDiskFreeThresholdPercent | Should -Be 20
            $r.Value.SQLBackupMaxAgeDays | Should -Be 3
            $r.Value.JsonHistoryRetentionDays | Should -Be 7
            $r.Value.EmailMaxItemsPerArea | Should -Be 10
            $r.Value.LogRetentionDays | Should -Be 60
            $r.Record.thresholds.SQLBackupMaxAgeDays.source | Should -Be 'default'
            $r.Record.thresholds.LogRetentionDays.source | Should -Be 'config'
        }

        It 'keeps the historical rule of EmailMaxItemsPerArea: a negative number counts as 0 (lists everything)' {
            $r = Get-SPSWeatherRunSetting -Config @{ EmailMaxItemsPerArea = -3 }
            $r.Value.EmailMaxItemsPerArea | Should -Be 0
            $r.Record.thresholds.EmailMaxItemsPerArea.source | Should -Be 'config'
            @($r.Messages).Count | Should -Be 0
        }
    }

    Context 'a value that cannot be used' {
        It 'falls back to the default of <Key>, flags it invalid and gives a message, for <Raw>' -ForEach @(
            @{ Key = 'SQLBackupMaxAgeDays'; Raw = 'abc' }
            @{ Key = 'SQLBackupMaxAgeDays'; Raw = '' }
            @{ Key = 'SQLBackupMaxAgeDays'; Raw = -1 }
            @{ Key = 'SQLDiskFreeThresholdPercent'; Raw = '15%' }
            @{ Key = 'JsonHistoryRetentionDays'; Raw = -30 }
            @{ Key = 'LogRetentionDays'; Raw = @(1, 2) }
            @{ Key = 'EmailMaxItemsPerArea'; Raw = 'many' }
        ) {
            $r = Get-SPSWeatherRunSetting -Config @{ $Key = $Raw }
            $r.Value.$Key | Should -Be $defaults[$Key]
            $r.Record.thresholds.$Key.value | Should -Be $defaults[$Key]
            $r.Record.thresholds.$Key.source | Should -Be 'default'
            $r.Record.thresholds.$Key.invalid | Should -BeTrue
            @($r.Messages).Count | Should -Be 1
            $r.Messages[0] | Should -Match $Key
            $r.Messages[0] | Should -Match "default $($defaults[$Key])"
        }

        It 'does not copy the invalid value into the record' {
            $r = Get-SPSWeatherRunSetting -Config @{ SQLBackupMaxAgeDays = 'D:\secret\path' }
            (ConvertTo-Json -InputObject $r.Record -Depth 6) | Should -Not -Match 'secret'
        }
    }

    Context 'what the record holds' {
        It 'only has the configuration file name, the thresholds and the exclusion names' {
            $r = Get-SPSWeatherRunSetting -Config @{} -ConfigFile 'x.psd1'
            @($r.Record.PSObject.Properties.Name) | Should -Be @('configFile', 'thresholds', 'exclusionRules')
            @($r.Record.thresholds.PSObject.Properties.Name) | Should -Be $keys
            @($r.Value.PSObject.Properties.Name) | Should -Be $keys
        }

        It 'keeps only the file name of the configuration file: <Path>' -ForEach @(
            @{ Path = 'D:\Temp\SPSWeather-v3.4.0\Config\SPSWeather-QTP.psd1'; Expected = 'SPSWeather-QTP.psd1' }
            @{ Path = '/opt/spsweather/Config/prod.psd1'; Expected = 'prod.psd1' }
            @{ Path = '.\Config\contoso-PROD.psd1'; Expected = 'contoso-PROD.psd1' }
            @{ Path = 'contoso-PROD.psd1'; Expected = 'contoso-PROD.psd1' }
            @{ Path = '\\fileserver\share$\Config\a b.psd1'; Expected = 'a b.psd1' }
        ) {
            (Get-SPSWeatherRunSetting -Config @{} -ConfigFile $Path).Record.configFile | Should -Be $Expected
        }

        It 'records no file name when none is given' -ForEach @(@{ File = $null }, @{ File = '' }, @{ File = '  ' }) {
            (Get-SPSWeatherRunSetting -Config @{} -ConfigFile $File).Record.configFile | Should -BeNullOrEmpty
        }

        It 'records the exclusions once each, always in the order of the fixed list (so two runs can be compared)' {
            $r = Get-SPSWeatherRunSetting -Config @{ ExclusionRules = @('SQLDiskStatus', 'WSPStatus', 'WSPStatus', 'TimerServiceStatus') }
            @($r.Record.exclusionRules) | Should -Be @('WSPStatus', 'TimerServiceStatus', 'SQLDiskStatus')
        }

        It 'accepts a single exclusion given as a string and an empty list' {
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = 'WSPStatus' }).Record.exclusionRules) | Should -Be @('WSPStatus')
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = @() }).Record.exclusionRules).Count | Should -Be 0
            @((Get-SPSWeatherRunSetting -Config @{}).Record.exclusionRules).Count | Should -Be 0
        }

        It 'records only real exclusion values: a path, an address, a URL, a server name, a typo or a wrong case is dropped' {
            $typed = @('WSPStatus', '\\srv\share', 'admin@contoso.com', 'https://portal.contoso.com', 'two words', 'SPWFE01', 'svc_spfarm', 'WSPStatu', 'wspstatus', '', $null, 42, ('A' * 65))
            $r = Get-SPSWeatherRunSetting -Config @{ ExclusionRules = $typed }
            @($r.Record.exclusionRules) | Should -Be @('WSPStatus')
        }

        It 'records an exclusion only with its exact spelling, as the entry script matches it case-sensitively (list of names)' {
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = @('wspstatus', 'WSPSTATUS') }).Record.exclusionRules).Count | Should -Be 0
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = @('wspstatus', 'WSPStatus') }).Record.exclusionRules) | Should -Be @('WSPStatus')
        }

        It 'does not count a list element that only contains a name (<Name>), as the entry script does not' -ForEach @(
            @{ Name = 'LF'; Typed = "WSPStatus`n" }
            @{ Name = 'CRLF'; Typed = "WSPStatus`r`n" }
            @{ Name = 'two LF'; Typed = "WSPStatus`n`n" }
            @{ Name = 'a space'; Typed = 'WSPStatus ' }
        ) {
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = @($Typed) }).Record.exclusionRules).Count | Should -Be 0
        }

        It 'agrees with the entry script on a single string: <Name>' -ForEach @(
            @{ Name = 'a name followed by a space'; Raw = 'WSPStatus '; Expected = @('WSPStatus') }
            @{ Name = 'a name followed by a line break'; Raw = "WSPStatus`r`n"; Expected = @('WSPStatus') }
            @{ Name = 'several names in one string'; Raw = 'WSPStatus, SQLDiskStatus'; Expected = @('WSPStatus', 'SQLDiskStatus') }
            @{ Name = 'one exact name'; Raw = 'WSPStatus'; Expected = @('WSPStatus') }
            @{ Name = 'a wrong case'; Raw = 'wspstatus'; Expected = @() }
            @{ Name = 'something unrelated'; Raw = 'SPWFE01'; Expected = @() }
        ) {
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = $Raw }).Record.exclusionRules) | Should -Be $Expected
        }

        It 'records exactly the exclusions that the entry script applies, for every shape of the value' -ForEach @(
            @{ Raw = @('WSPStatus', 'SQLDiskStatus') }
            @{ Raw = @('WSPStatus ', 'wspstatus') }
            @{ Raw = 'WSPStatus ' }
            @{ Raw = 'WSPStatus,SQLDiskStatus,TimerServiceStatus' }
            @{ Raw = 'None' }
            @{ Raw = @() }
            @{ Raw = '' }
            @{ Raw = 42 }
        ) {
            $known = @('None', 'APIHttpStatus', 'SPSiteHttpStatus', 'EvtViewerStatus', 'IISW3WPStatus', 'HealthStatus', 'WSPStatus', 'FailedTimerJob', 'TimerServiceStatus', 'SQLInstanceStatus', 'SQLDatabaseStatus', 'SQLDiskStatus', 'SQLAvailabilityStatus', 'SQLAliasStatus')
            # What the entry script does with $ExclusionRules = $envCfg.ExclusionRules
            $ExclusionRules = $Raw
            $applied = @($known | Where-Object { try { [bool]$ExclusionRules.Contains($_) } catch { $false } })
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = $Raw }).Record.exclusionRules) | Should -Be $applied
        }

        It 'does not throw on a value of an unexpected type and records no exclusion' -ForEach @(
            @{ Raw = $null }
            @{ Raw = $true }
            @{ Raw = @{ A = 1 } }
            @{ Raw = [PSCustomObject]@{ A = 1 } }
        ) {
            { Get-SPSWeatherRunSetting -Config @{ ExclusionRules = $Raw } } | Should -Not -Throw
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = $Raw }).Record.exclusionRules).Count | Should -Be 0
        }

        It 'knows every exclusion that the entry script tests, and the ones that the example configuration lists' {
            $repoRoot = Split-Path -Path $PSScriptRoot -Parent
            $entry = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1') -Raw
            $inEntry = @([regex]::Matches($entry, 'ExclusionRules\.Contains\([''"](\w+)[''"]\)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
            $inEntry.Count | Should -BeGreaterThan 10
            $recorded = @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = $inEntry }).Record.exclusionRules | Sort-Object)
            $recorded | Should -Be $inEntry

            $example = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'src/Config/CONTOSO-PROD.example.psd1') -Raw
            $documented = [regex]::Match($example, '(?s)Authorized values:(.*?)\.\s*\r?\n\s*ExclusionRules').Groups[1].Value
            $listed = @(($documented -replace '#', ' ') -split '[,\s]+' | Where-Object { $_ } | Sort-Object -Unique)
            $listed.Count | Should -BeGreaterThan 10
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = $listed }).Record.exclusionRules | Sort-Object) | Should -Be $listed
        }

        It 'never lets another value of the configuration reach the record' {
            $config = @{
                ApplicationName = 'zebes-app'
                ConfigurationName = 'zebes-env'
                Domain = 'secret-domain.contoso.local'
                CredentialKey = 'secret-credential-key'
                SMTPServer = 'secret-smtp.contoso.local'
                SMTPToAddress = @('secret-to@contoso.com')
                SMTPFromAddress = 'secret-from@contoso.com'
                Dashboard = @{ OutputPath = '\\secret-share\dash'; Url = 'https://secret-url.contoso.local' }
                Farms = @(@{ Name = 'SECRETFARM'; Server = 'secret-server'; SqlServers = @('secret-sql') })
                SQLBackupMaxAgeDays = 8
                ExclusionRules = @('WSPStatus')
            }
            $r = Get-SPSWeatherRunSetting -Config $config -ConfigFile 'D:\secret-folder\conf.psd1'
            $json = ConvertTo-Json -InputObject $r.Record -Depth 6
            $json | Should -Not -Match 'secret'
            $json | Should -Not -Match 'zebes'
            $json | Should -Match 'conf\.psd1'
        }
    }
}

Describe 'Get-SPSWeatherRunSetting with the limits' {
    BeforeAll {
        $script:noLimit = Get-SPSWeatherRunSetting -Config @{ SQLBackupMaxAgeDays = 8; ExclusionRules = @('WSPStatus') } -ConfigFile 'C:\x\conf.psd1'
    }

    It 'gives the same record as before the limits when no limit setting is given, or when it is null' {
        $null1 = Get-SPSWeatherRunSetting -Config @{ SQLBackupMaxAgeDays = 8; ExclusionRules = @('WSPStatus') } -ConfigFile 'C:\x\conf.psd1' -LimitSetting $null
        (ConvertTo-Json -InputObject $null1.Record -Depth 6) | Should -Be (ConvertTo-Json -InputObject $noLimit.Record -Depth 6)
        @($noLimit.Record.thresholds.PSObject.Properties.Name | Where-Object { $_ -like 'Limits.*' }).Count | Should -Be 0
    }

    It 'adds the thresholds of the limits, with their source, next to the others, and leaves the others as they were' {
        $limit = Get-SPSWeatherLimitSetting -Config @{ Limits = @{ ContentDatabaseSize = @{ Warning = 100 } } }
        $r = Get-SPSWeatherRunSetting -Config @{ SQLBackupMaxAgeDays = 8 } -LimitSetting $limit
        $r.Record.thresholds.'Limits.ContentDatabaseSize.Warning'.value | Should -Be 100
        $r.Record.thresholds.'Limits.ContentDatabaseSize.Warning'.source | Should -Be 'config'
        $r.Record.thresholds.'Limits.ContentDatabaseSize.Failure'.value | Should -Be 200
        $r.Record.thresholds.'Limits.ContentDatabaseSize.Failure'.source | Should -Be 'default'
        $r.Record.thresholds.SQLBackupMaxAgeDays.value | Should -Be 8
        $r.Value.PSObject.Properties.Name | Should -Not -Contain 'Limits.ContentDatabaseSize.Warning'
    }

    It 'records the checks that are turned off among the excluded names, after the exclusions of the configuration, and the LimitStatus exclusion' {
        $limit = Get-SPSWeatherLimitSetting -Config @{ Limits = @{ Disabled = @('ManagedPaths') } }
        $r = Get-SPSWeatherRunSetting -Config @{ ExclusionRules = @('LimitStatus', 'WSPStatus') } -LimitSetting $limit
        $r.Record.exclusionRules | Should -Contain 'Limits.ManagedPaths'
        $r.Record.exclusionRules | Should -Contain 'LimitStatus'
        $r.Record.exclusionRules | Should -Contain 'WSPStatus'
    }

    It 'never lets an object name of an exception reach the record' {
        $limit = Get-SPSWeatherLimitSetting -Config @{ Limits = @{ Exceptions = @(@{ Limit = 'ContentDatabaseSize'; Object = 'WSS_Content_Archive_secret'; Failure = 4096; Reason = 'secret reason' }) } }
        $r = Get-SPSWeatherRunSetting -Config @{} -LimitSetting $limit
        (ConvertTo-Json -InputObject $r.Record -Depth 6) | Should -Not -Match 'secret'
    }
}
