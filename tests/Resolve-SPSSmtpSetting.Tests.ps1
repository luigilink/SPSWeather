# Behavioural tests for Resolve-SPSSmtpSetting (exported: the entry script calls it from outside
# the module): how the SMTPEnabled / SMTPPreview config keys and the deprecated -EnableSmtp
# switch decide what a run does.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-SPSSmtpSetting' {
    BeforeAll {
        $script:smtpKeys = @{ SMTPToAddress = @('admin@contoso.com'); SMTPFromAddress = 'noreply@contoso.com'; SMTPServer = 'smtp.contoso.com' }
    }

    Context 'SMTPEnabled not defined (legacy configs and scheduled tasks)' {
        It 'does not send without the switch' {
            $r = InModuleScope SPSWeather.Common -Parameters @{ Keys = $smtpKeys } { param($Keys) Resolve-SPSSmtpSetting -Config $Keys }
            $r.Send | Should -BeFalse
            $r.ConfigDefinesEnabled | Should -BeFalse
            $r.Messages.Count | Should -Be 0
        }

        It 'still sends with the deprecated switch and says so' {
            $r = InModuleScope SPSWeather.Common -Parameters @{ Keys = $smtpKeys } { param($Keys) Resolve-SPSSmtpSetting -Config $Keys -EnableSmtp }
            $r.Send | Should -BeTrue
            $r.ConfigDefinesEnabled | Should -BeFalse
            ($r.Messages -join ' ') | Should -Match 'deprecated.*SMTPEnabled'
        }
    }

    Context 'SMTPEnabled defined' {
        It 'sends when it is $true, without any switch and without a warning' {
            $r = InModuleScope SPSWeather.Common -Parameters @{ Keys = $smtpKeys } { param($Keys) Resolve-SPSSmtpSetting -Config ($Keys + @{ SMTPEnabled = $true }) }
            $r.Send | Should -BeTrue
            $r.ConfigDefinesEnabled | Should -BeTrue
            $r.Messages.Count | Should -Be 0
        }

        It 'does not send when it is $false, even with the legacy switch (the config wins)' {
            $r = InModuleScope SPSWeather.Common -Parameters @{ Keys = $smtpKeys } { param($Keys) Resolve-SPSSmtpSetting -Config ($Keys + @{ SMTPEnabled = $false }) -EnableSmtp }
            $r.Send | Should -BeFalse
            ($r.Messages -join ' ') | Should -Match 'ignored.*precedence'
        }

        It "accepts the string '<Value>' as a boolean" -ForEach @(
            @{ Value = 'true'; Expected = $true }
            @{ Value = 'False'; Expected = $false }
        ) {
            $r = InModuleScope SPSWeather.Common -Parameters @{ Keys = $smtpKeys; Value = $Value } { param($Keys, $Value) Resolve-SPSSmtpSetting -Config ($Keys + @{ SMTPEnabled = $Value }) }
            $r.Send | Should -Be $Expected
            $r.Messages.Count | Should -Be 0
        }

        It "rejects '<Value>' instead of casting it, and never sends" -ForEach @(
            @{ Value = 'maybe' }
            @{ Value = 'yes' }
            @{ Value = 0 }
        ) {
            $r = InModuleScope SPSWeather.Common -Parameters @{ Keys = $smtpKeys; Value = $Value } { param($Keys, $Value) Resolve-SPSSmtpSetting -Config ($Keys + @{ SMTPEnabled = $Value }) }
            $r.Send | Should -BeFalse
            ($r.Messages -join ' ') | Should -Match 'SMTPEnabled must be'
        }
    }

    Context 'sending enabled but the SMTP settings are incomplete' {
        It 'skips sending and names the missing key <Missing>' -ForEach @(
            @{ Missing = 'SMTPServer'; Config = @{ SMTPEnabled = $true; SMTPToAddress = @('a@b.c'); SMTPFromAddress = 'n@b.c' } }
            @{ Missing = 'SMTPToAddress'; Config = @{ SMTPEnabled = $true; SMTPFromAddress = 'n@b.c'; SMTPServer = 'smtp' } }
            @{ Missing = 'SMTPFromAddress'; Config = @{ SMTPEnabled = $true; SMTPToAddress = @('a@b.c'); SMTPServer = '  ' } }
        ) {
            $r = InModuleScope SPSWeather.Common -Parameters @{ Config = $Config } { param($Config) Resolve-SPSSmtpSetting -Config $Config }
            $r.Send | Should -BeFalse
            ($r.Messages -join ' ') | Should -Match $Missing
            ($r.Messages -join ' ') | Should -Match 'no email will be sent'
        }

        It 'does not require the SMTP settings when sending is off (lab without relay)' {
            $r = InModuleScope SPSWeather.Common { Resolve-SPSSmtpSetting -Config @{ SMTPEnabled = $false; SMTPPreview = $true } }
            $r.Send | Should -BeFalse
            $r.Preview | Should -BeTrue
            $r.Messages.Count | Should -Be 0
        }
    }

    Context 'SMTPPreview' {
        It 'defaults to $false' {
            $r = InModuleScope SPSWeather.Common { Resolve-SPSSmtpSetting -Config @{ SMTPEnabled = $false } }
            $r.Preview | Should -BeFalse
        }

        It 'is independent from sending: both can be on' {
            $r = InModuleScope SPSWeather.Common -Parameters @{ Keys = $smtpKeys } { param($Keys) Resolve-SPSSmtpSetting -Config ($Keys + @{ SMTPEnabled = $true; SMTPPreview = $true }) }
            $r.Send | Should -BeTrue
            $r.Preview | Should -BeTrue
        }

        It 'works with the legacy switch and no SMTPEnabled key' {
            $r = InModuleScope SPSWeather.Common -Parameters @{ Keys = $smtpKeys } { param($Keys) Resolve-SPSSmtpSetting -Config ($Keys + @{ SMTPPreview = $true }) -EnableSmtp }
            $r.Send | Should -BeTrue
            $r.Preview | Should -BeTrue
        }

        It 'parses boolean strings and rejects any other value instead of casting it' {
            $r = InModuleScope SPSWeather.Common { Resolve-SPSSmtpSetting -Config @{ SMTPEnabled = $false; SMTPPreview = 'false' } }
            $r.Preview | Should -BeFalse
            $r.Messages.Count | Should -Be 0
            $bad = InModuleScope SPSWeather.Common { Resolve-SPSSmtpSetting -Config @{ SMTPEnabled = $false; SMTPPreview = 'soon' } }
            $bad.Preview | Should -BeFalse
            ($bad.Messages -join ' ') | Should -Match 'SMTPPreview must be'
        }
    }

    It 'tolerates a $null configuration' {
        $r = InModuleScope SPSWeather.Common { Resolve-SPSSmtpSetting -Config $null }
        $r.Send | Should -BeFalse
        $r.Preview | Should -BeFalse
    }
}
