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
                $r.Record.thresholds.$key.PSObject.Properties.Name | Should -Not -Contain 'invalid'
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

        It 'records the names of the exclusion rules once each, in order' {
            $r = Get-SPSWeatherRunSetting -Config @{ ExclusionRules = @('WSPStatus', 'SQLDiskStatus', 'WSPStatus', 'TimerServiceStatus') }
            @($r.Record.exclusionRules) | Should -Be @('WSPStatus', 'SQLDiskStatus', 'TimerServiceStatus')
        }

        It 'accepts a single exclusion given as a string and an empty list' {
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = 'WSPStatus' }).Record.exclusionRules) | Should -Be @('WSPStatus')
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = @() }).Record.exclusionRules).Count | Should -Be 0
            @((Get-SPSWeatherRunSetting -Config @{}).Record.exclusionRules).Count | Should -Be 0
        }

        It 'drops anything that is not a plain check name (a path, an address, a URL, a sentence)' {
            $r = Get-SPSWeatherRunSetting -Config @{ ExclusionRules = @('WSPStatus', '\\srv\share', 'admin@contoso.com', 'https://portal.contoso.com', 'two words', '', $null, 42, ('A' * 65)) }
            @($r.Record.exclusionRules) | Should -Be @('WSPStatus')
        }

        It 'caps the number of recorded exclusions' {
            $many = 1..80 | ForEach-Object { "Rule$_" }
            @((Get-SPSWeatherRunSetting -Config @{ ExclusionRules = $many }).Record.exclusionRules).Count | Should -Be 50
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
